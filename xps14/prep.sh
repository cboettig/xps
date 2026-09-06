#!/bin/bash
# Post-upgrade preparation, before the first reboot into 26.04.
#
#   sudo ./prep.sh
#
# 1. restores the camera rotation fix the upgrade overwrote
# 2. installs the linux-oem-26.04 fallback kernel + its camera modules
# 3. refreshes the GRUB menu
#
# Deliberately does NOT run `apt autoremove`: it would remove the OEM 6.17
# camera modules and cost us a fallback. Clean up later, once we know which
# kernel works.

set -u
cd "$(dirname "$(readlink -f "$0")")"
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
bad(){ printf '  [FAIL] %s\n' "$*"; }

[ "$(id -u)" = 0 ] || { echo "run as: sudo ./prep.sh"; exit 1; }

say "1. Restoring camera rotation fix (flip-mode=vhflip)"
SRC=etc/v4l2-relayd-default.conf
DST=/etc/v4l2-relayd.d/default.conf
if [ -f "$SRC" ]; then
    cp -a "$DST" "$DST.pre-restore" 2>/dev/null
    install -m0644 "$SRC" "$DST"
    systemctl restart v4l2-relayd@default.service
    sleep 2
    if pgrep -af 'v4l2-relayd -i' | grep -q flip-mode; then
        ok "v4l2-relayd running with flip-mode=vhflip"
    else
        bad "flip-mode not in the running process -- check after reboot"
    fi
else
    bad "$SRC not found (are you running this from the xps14 dir?)"
fi

say "2. Installing the linux-oem-26.04 fallback kernel"
if apt-get install -y linux-oem-26.04 linux-modules-ipu7-oem-26.04 \
                     linux-modules-vision-oem-26.04; then
    ok "installed"
else
    bad "install failed -- not fatal, you still have 3 kernels"
fi

say "3. Refreshing GRUB"
update-grub 2>&1 | grep -Ei 'found|linux' | sed 's/^/  /'

say "Bootable kernels"
for v in /boot/vmlinuz-*; do
    k=${v#/boot/vmlinuz-}
    p=$(modinfo -k "$k" intel_ipu7_psys 2>/dev/null | awk '/^srcversion/{print $2}')
    case "$p" in
      0DB161AA*) tag="psys REBUILT (26.04) -- the one to test" ;;
      32D18897*) tag="psys old (known-good on this kernel)" ;;
      "")        tag="no psys module installed" ;;
      *)         tag="psys $p" ;;
    esac
    printf "  %-22s %s\n" "$k" "$tag"
done

say "Next"
cat <<'EOF'
  Reboot. GRUB_DEFAULT points at 7.0.0-30-generic, so you land on the
  known-good kernel with the new 26.04 userspace. Check the camera there
  first, then reboot again and pick 7.0.0-31-generic from
  "Advanced options for Ubuntu" to run the real test.

  On either kernel, the check is:

    uname -r
    journalctl -b -k | grep -E 'IPU psys probe done|psys device_register failed'
    ls -l /dev/ipu7-psys0
    gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
      ! jpegenc ! multifilesink location=/tmp/f%02d.jpg
    ls -l /tmp/f*.jpg | awk '{print $5}' | sort -u | wc -l     # must be > 1

  Do NOT run `apt autoremove` yet, and do NOT unbind the IPU7 device on
  7.0.0-31-generic (it NULL-derefs and wedges shutdown).
EOF
