#!/bin/bash
# Point GRUB at 7.0.0-31-generic and reboot into it.
#
#   sudo ./next.sh
#
# Why: under 26.04, v4l2loopback moved into its own module package and is only
# present for -31. 7.0.0-30-generic is now an unsupported hybrid (noble-era
# module packages, no loopback -> v4l2-relayd cannot start), and resolute has
# no v4l2loopback build for it. -31 also carries the REBUILT psys module
# (srcversion 0DB161AA..., vs noble's broken 32D18897...), so this is both the
# supported config and the test we have been trying to run.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./next.sh"; exit 1; }

say "Setting GRUB default to the newest generic kernel"
# GRUB_FLAVOUR_ORDER=generic (zz-flavour-order.cfg) already sorts generic
# first, so entry 0 is the newest generic = 7.0.0-31-generic. Using 0 rather
# than a menu title means it keeps working as newer generic kernels arrive.
cp -a /etc/default/grub /etc/default/grub.bak-$(date +%F)
sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' /etc/default/grub
grep '^GRUB_DEFAULT' /etc/default/grub | sed 's/^/  /'
update-grub 2>&1 | grep -i 'linux' | sed 's/^/  /'

say "Module completeness per kernel"
for v in /boot/vmlinuz-*; do
    k=${v#/boot/vmlinuz-}
    miss=
    for m in intel_ipu7_psys intel_cvs ov08x40 v4l2loopback; do
        modinfo -k "$k" "$m" >/dev/null 2>&1 || miss="$miss $m"
    done
    if [ -z "$miss" ]; then printf "  %-22s COMPLETE\n" "$k"
    else printf "  %-22s missing:%s\n" "$k" "$miss"; fi
done

say "Ready"
cat <<'EOF'
  Rebooting into 7.0.0-31-generic. After it comes up, check:

    uname -r
    journalctl -b -k | grep -E 'IPU psys probe done|psys device_register failed'
    ls -l /dev/ipu7-psys0
    systemctl is-active v4l2-relayd@default.service
    gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
      ! jpegenc ! multifilesink location=/tmp/f%02d.jpg
    ls -l /tmp/f*.jpg | awk '{print $5}' | sort -u | wc -l    # must be > 1

  "IPU psys probe done." means resolute's rebuilt psys fixed the regression.
  "psys device_register failed" means it did not -- then try 7.0.0-1013-oem
  from the GRUB menu (Advanced options), which is a separate ABI line.

  Do NOT unbind the IPU7 device on -31 either way.
EOF
echo
read -rp "  Reboot now? [y/N] " a
case "$a" in [yY]*) reboot ;; *) echo "  Not rebooting. Run: sudo reboot" ;; esac
