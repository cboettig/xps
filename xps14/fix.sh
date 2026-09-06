#!/bin/bash
# Remove the stale noble-built camera modules for 7.0.0-31-generic.
#
#   sudo ./fix.sh
#
# After the release upgrade, BOTH module sets are installed for -31:
#
#   ubuntu/vision/intel_cvs.ko.zst       <- linux-modules-vision-7.0.0-31-generic
#                                           (7.0.0-31.31~24.04.1, built for NOBLE)
#   ubuntu/dkms/vision/intel_cvs.ko.zst  <- linux-main-modules-vision-7.0.0-31-generic
#                                           (7.0.0-31.31+2, built for RESOLUTE)
#
# depmod searches ubuntu/ before ubuntu/dkms/, so modprobe picks the noble
# build, which cannot load against resolute's kernel (different symbol CRCs
# despite identical vermagic). intel_cvs therefore never loads, the sensor's
# I2C device is never created, ov08x40 never binds, and the media graph has no
# sensor -- even though psys now probes correctly.
#
# psys got lucky: it resolved to the dkms copy, which is why
# "IPU psys probe done." already appears.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
bad(){ printf '  [FAIL] %s\n' "$*"; }
K=7.0.0-31-generic
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./fix.sh"; exit 1; }

say "1. Removing noble-built module packages for $K"
apt-get purge -y \
  linux-modules-ipu6-$K \
  linux-modules-ipu7-$K \
  linux-modules-vision-$K 2>&1 | grep -E 'Removing|Purging|error' | sed 's/^/  /'

say "2. Removing leftover backup file from the manual module swap"
rm -fv /lib/modules/$K/ubuntu/ipu7/intel-ipu7-psys.ko.zst.noble-orig | sed 's/^/  /'

say "3. Rebuilding module dependency map"
depmod -a "$K" && ok "depmod done"

say "4. Verifying modprobe now resolves to the resolute build"
for m in intel_cvs intel_ipu7_psys; do
    p=$(modprobe -n -v "$m" 2>/dev/null | awk '/insmod/{print $2}')
    if [ -z "$p" ]; then
        printf "  %-18s already loaded\n" "$m"
    elif case "$p" in */dkms/*) true;; *) false;; esac; then
        ok "$m -> ${p#/lib/modules/$K/}"
    else
        bad "$m -> ${p#/lib/modules/$K/}  (still the wrong copy)"
    fi
done

say "5. Rebuilding initramfs"
update-initramfs -u -k "$K" 2>&1 | tail -2 | sed 's/^/  /'

say "6. Loading intel_cvs now (no reboot)"
if modprobe intel_cvs 2>&1 | sed 's/^/  /'; then
    if lsmod | grep -q '^intel_cvs'; then ok "intel_cvs loaded"
    else bad "intel_cvs still not loaded - a reboot is needed for a cold probe"; fi
fi

say "Status"
printf "  %-26s %s\n" "psys node:" "$([ -e /dev/ipu7-psys0 ] && echo present || echo MISSING)"
printf "  %-26s %s\n" "intel_cvs loaded:" "$(lsmod | grep -q '^intel_cvs' && echo yes || echo no)"
printf "  %-26s %s\n" "sensor in media graph:" "$(media-ctl -d /dev/media0 -p 2>/dev/null | grep -q ov08x40 && echo yes || echo no)"

say "Next"
cat <<'EOF'
  The sensor attaches during the ipu7 ACPI probe at boot, so even if intel_cvs
  loads cleanly now, a reboot is needed for it to actually bind ov08x40.

  Reboot, then check:

    lsmod | grep intel_cvs
    media-ctl -d /dev/media0 -p | grep ov08x40
    gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
      ! jpegenc ! multifilesink location=/tmp/f%02d.jpg
    ls -l /tmp/f*.jpg | awk '{print $5}' | sort -u | wc -l    # must be > 1

  Still do NOT unbind the IPU7 device.
EOF
echo
read -rp "  Reboot now? [y/N] " a
case "$a" in [yY]*) reboot ;; *) echo "  Not rebooting. Run: sudo reboot" ;; esac
