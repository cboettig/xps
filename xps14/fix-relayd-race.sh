#!/bin/bash
# Fix the v4l2-relayd boot race introduced by the 26.04 upgrade.
#
#   sudo ./fix-relayd-race.sh
#
# Problem: the unit orders itself only After=modprobe@v4l2loopback.service,
# which waits for the MODULE, not for the loopback device node. On this
# machine the node appears ~10s later:
#
#   13:26:44.6  v4l2loopback module inserted
#   13:26:46.8  v4l2-relayd started      <- nothing to attach to yet
#   13:26:56.9  /dev/video0 created      <- too late
#
# relayd finds no loopback, never opens it to watch for clients, and idles
# forever at ~0.1% CPU without logging anything. The camera then returns only
# a stale placeholder frame. Restarting the service by hand fixes it until the
# next boot.
#
# Fix: an ExecStartPre that waits for a video4linux device whose name matches
# CARD_LABEL before relayd starts. If it never appears, relayd now fails
# visibly instead of idling silently.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./fix-relayd-race.sh"; exit 1; }

DIR=/etc/systemd/system/v4l2-relayd@.service.d
say "Writing drop-in: $DIR/wait-for-loopback.conf"
mkdir -p "$DIR"
cat > "$DIR/wait-for-loopback.conf" <<'EOF'
# Wait for the v4l2loopback device node, not just the module.
# See xps14/kernel.md -- the stock unit races on 26.04 (v4l2-relayd 0.2.0 +
# v4l2loopback 0.15.3) and relayd silently idles if it starts too early.
[Service]
ExecStartPre=/bin/sh -c 'for i in $(seq 1 60); do \
    grep -l -m1 -E "^${CARD_LABEL}$" /sys/devices/virtual/video4linux/*/name >/dev/null 2>&1 && exit 0; \
    sleep 0.5; \
  done; \
  echo "v4l2loopback device \"${CARD_LABEL}\" never appeared" >&2; exit 1'
EOF
sed 's/^/  /' "$DIR/wait-for-loopback.conf"

say "Reloading systemd"
systemctl daemon-reload && echo "  done"

say "Restarting to verify"
systemctl restart v4l2-relayd@default.service
sleep 3
systemctl is-active v4l2-relayd@default.service | sed 's/^/  active: /'
pgrep -af 'v4l2-relayd -i' | grep -o 'flip-mode=[a-z]*' | head -1 | sed 's/^/  /'

say "Capture test"
cd /tmp && rm -f rz*.jpg
timeout 30 gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
  ! jpegenc ! multifilesink location=rz%02d.jpg >/dev/null 2>&1
n=$(ls rz*.jpg 2>/dev/null | wc -l); u=$(ls -l rz*.jpg 2>/dev/null | awk '{print $5}' | sort -u | wc -l)
echo "  frames=$n distinct=$u"
if [ "$n" -ge 10 ] && [ "$u" -gt 1 ]; then echo "  [ OK ] live video"; else echo "  [FAIL] not live"; fi

say "Next"
echo "  Reboot to confirm the race is actually fixed at boot (that is the"
echo "  whole point -- it already works after a manual restart)."
echo
echo "  After reboot, WITHOUT restarting anything:"
echo "    systemctl is-active v4l2-relayd@default.service"
echo "    cd /tmp && gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 \\"
echo "      ! videoconvert ! jpegenc ! multifilesink location=b%02d.jpg"
echo "    ls -l /tmp/b*.jpg | awk '{print \$5}' | sort -u | wc -l   # > 1"
