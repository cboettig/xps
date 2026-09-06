#!/bin/bash
# Correct fix for v4l2-relayd not streaming after boot on 26.04.
#
#   sudo ./fix-relayd-kick.sh
#
# Supersedes fix-relayd-race.sh, which was wrong twice over:
#
#   1. Its ExecStartPre was a multi-line inline shell script in a unit file.
#      systemd mangled the quoting and dropped the ';' separators, so the wait
#      loop never ran -- relayd started 5s after boot as before.
#   2. Even correctly parsed it would have DEADLOCKED. relayd creates the
#      loopback device itself (~10s after it starts; ATTR{format} on video0
#      matches relayd's configured NV12:1280x720@30), so waiting for the device
#      before starting relayd waits for something only relayd can produce.
#
# What actually happens: relayd's first run creates the loopback device but
# then never streams -- it sits at ~0% CPU holding no fd while systemd reports
# "active". A restart, with the device already present, works correctly.
#
# So: let relayd start normally, then kick it once the device exists. A oneshot
# service runs once per boot, so there is no restart loop.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
bad(){ printf '  [FAIL] %s\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./fix-relayd-kick.sh"; exit 1; }

say "1. Removing the earlier broken drop-in"
if [ -e /etc/systemd/system/v4l2-relayd@.service.d/wait-for-loopback.conf ]; then
    rm -f /etc/systemd/system/v4l2-relayd@.service.d/wait-for-loopback.conf
    rmdir --ignore-fail-on-non-empty /etc/systemd/system/v4l2-relayd@.service.d 2>/dev/null
    ok "removed wait-for-loopback.conf"
else
    ok "not present"
fi

say "2. Installing /usr/local/sbin/v4l2-relayd-kick"
cat > /usr/local/sbin/v4l2-relayd-kick <<'SCRIPT'
#!/bin/sh
# Wait for the v4l2loopback device v4l2-relayd creates, then restart relayd
# once so it actually streams. See xps14/kernel.md.
set -u
CONF=/etc/v4l2-relayd.d/default.conf
LABEL=$(sed -n 's/^CARD_LABEL=//p' "$CONF" 2>/dev/null | tr -d '"' | head -1)
[ -n "$LABEL" ] || LABEL="Intel MIPI Camera"

i=0
while [ "$i" -lt 120 ]; do
    for f in /sys/devices/virtual/video4linux/*/name; do
        [ -e "$f" ] || continue
        if [ "$(cat "$f" 2>/dev/null)" = "$LABEL" ]; then
            logger -t v4l2-relayd-kick "device '$LABEL' present, restarting relayd"
            exec systemctl try-restart v4l2-relayd@default.service
        fi
    done
    i=$((i + 1))
    sleep 0.5
done
logger -t v4l2-relayd-kick "device '$LABEL' never appeared after 60s; not restarting"
exit 0
SCRIPT
chmod 0755 /usr/local/sbin/v4l2-relayd-kick
ok "installed"

say "3. Installing the oneshot unit"
cat > /etc/systemd/system/v4l2-relayd-kick.service <<'UNIT'
[Unit]
Description=Kick v4l2-relayd once its loopback device exists
Documentation=https://github.com/cboettig/xps/tree/master/xps14
After=v4l2-relayd@default.service
Wants=v4l2-relayd@default.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/v4l2-relayd-kick

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable v4l2-relayd-kick.service 2>&1 | sed 's/^/  /'
ok "enabled"

say "4. Running it now"
systemctl start v4l2-relayd-kick.service
sleep 4
systemctl is-active v4l2-relayd@default.service | sed 's/^/  relayd: /'
pgrep -af 'v4l2-relayd -i' | grep -o 'flip-mode=[a-z]*' | head -1 | sed 's/^/  /'

say "5. Capture test"
cd /tmp && rm -f k*.jpg
timeout 30 gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
  ! jpegenc ! multifilesink location=k%02d.jpg >/dev/null 2>&1
n=$(ls k*.jpg 2>/dev/null | wc -l); u=$(ls -l k*.jpg 2>/dev/null | awk '{print $5}' | sort -u | wc -l)
echo "  frames=$n distinct=$u"
if [ "$n" -ge 10 ] && [ "$u" -gt 1 ]; then ok "live video"; else bad "not live"; fi

say "Next"
echo "  Reboot and check WITHOUT restarting anything:"
echo
echo "    systemctl status v4l2-relayd-kick.service --no-pager | head -5"
echo "    journalctl -b -t v4l2-relayd-kick"
echo "    cd /tmp && gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 \\"
echo "      ! videoconvert ! jpegenc ! multifilesink location=b%02d.jpg"
echo "    ls -l /tmp/b*.jpg | awk '{print \$5}' | sort -u | wc -l    # > 1"
