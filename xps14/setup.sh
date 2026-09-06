#!/bin/bash
# Configure the built-in camera on a Dell XPS 14 DA14260 running Ubuntu 26.04.
#
#   sudo ./setup.sh
#
# Idempotent: safe to run on a fresh install, after a release upgrade, or on a
# working system to verify it still matches these notes. Prints a verdict.
#
# See camera.md for how the stack fits together and kernel.md for the module
# packaging.

set -u
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok(){ printf '  [ OK ] %s\n' "$*"; }
no(){ printf '  [FAIL] %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
CHANGED=0
[ "$(id -u)" = 0 ] || { echo "run as: sudo ./setup.sh"; exit 1; }
cd "$(dirname "$(readlink -f "$0")")"

. /etc/os-release
say "System"
info "$PRETTY_NAME, kernel $(uname -r)"
[ "${VERSION_CODENAME:-}" = resolute ] || {
    no "these notes target Ubuntu 26.04 (resolute); found ${VERSION_CODENAME:-unknown}"
    info "for the 24.04 -> 26.04 path see upgrade.md"; exit 1; }

# ---------------------------------------------------------------- Dell archive
# libcamhal / icamerasrc exist ONLY in Dell's archive. Without it you get
# libcamera only, which is not what this machine runs.
say "Dell OEM archive"
if ! grep -rqs 'dell.archive.canonical.com' /etc/apt/sources.list.d/; then
    apt-get install -y ubuntu-oem-keyring >/dev/null 2>&1
    cat > /etc/apt/sources.list.d/dell-somerville.sources <<EOF
Types: deb
URIs: http://dell.archive.canonical.com/
Suites: $VERSION_CODENAME
Components: somerville somerville-hypno
Signed-By: /usr/share/keyrings/ubuntu-oem-keyring.gpg
EOF
    apt-get update -qq; CHANGED=1; ok "added"
else
    ok "already configured"
fi

# ------------------------------------------------------------------- packages
say "Packages"
PKGS="
linux-modules-ipu7-generic-hwe-26.04
linux-modules-ipu6-generic-hwe-26.04
linux-modules-vision-generic-hwe-26.04
linux-modules-usbio-generic-hwe-26.04
linux-modules-v4l2loopback-generic-hwe-26.04
libcamhal-ipu75xa
gstreamer1.0-icamera
v4l2-relayd
oem-somerville-hypno-meta
"
MISSING=$(for p in $PKGS; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok' || echo "$p"; done)
if [ -n "$MISSING" ]; then
    info "installing:$(echo $MISSING | tr '\n' ' ')"
    apt-get install -y $MISSING && { CHANGED=1; ok "installed"; } || no "install failed"
else
    ok "all present"
fi

# Upgrade leftovers: noble-built module packages shadow resolute's, because
# depmod searches ubuntu/ before ubuntu/dkms/. They cannot load on a resolute
# kernel. Only present on an upgraded system.
say "Shadowing noble module packages"
K=$(uname -r)
STALE=$(dpkg-query -W -f='${Package}\n' "linux-modules-ipu6-$K" "linux-modules-ipu7-$K" \
        "linux-modules-vision-$K" 2>/dev/null | grep -v '^$')
if [ -n "$STALE" ]; then
    info "removing:$(echo $STALE | tr '\n' ' ')"
    apt-get purge -y $STALE >/dev/null 2>&1
    depmod -a "$K"; update-initramfs -u -k "$K" >/dev/null 2>&1
    CHANGED=1; ok "purged (reboot needed)"
else
    ok "none"
fi

# ---------------------------------------------------------------- config files
say "Config"
inst(){ # src dst label
    if [ ! -f "$2" ] || ! cmp -s "$1" "$2"; then
        install -D -m0644 "$1" "$2"; CHANGED=1; ok "$3 written"
    else ok "$3 current"; fi
}
# 180-degree rotation, applied inside the HAL. Release upgrades REPLACE this
# file without prompting, so re-check it after any v4l2-relayd update.
inst etc/v4l2-relayd-default.conf   /etc/v4l2-relayd.d/default.conf      "camera flip"
# Module ordering: int3472 races the USBIO GPIO controller at boot.
inst etc/modprobe.d-ipu7-order.conf /etc/modprobe.d/ipu7-order.conf      "module softdep"
# oem-somerville-hypno-meta ships GRUB_FLAVOUR_ORDER=oem, which sorts *-oem
# kernels ahead of generic regardless of version. Drop-ins are sourced in glob
# order, so zz- wins. That file is package-owned; do not edit it.
inst etc/grub.d-zz-flavour-order.cfg /etc/default/grub.d/zz-flavour-order.cfg "GRUB flavour order"

if ! grep -q '^GRUB_DEFAULT=0' /etc/default/grub; then
    cp -a /etc/default/grub /etc/default/grub.bak-$(date +%F)
    sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' /etc/default/grub
    CHANGED=1; ok "GRUB_DEFAULT=0 (newest generic)"
else ok "GRUB_DEFAULT current"; fi

# --------------------------------------------------------------- relayd kick
# relayd's first run after boot creates the loopback device but does not
# stream: active, ~0% CPU, no fd, one stale frame. A restart with the device
# present works. Empirical; see camera.md.
say "v4l2-relayd kick service"
inst etc/v4l2-relayd-kick.service /etc/systemd/system/v4l2-relayd-kick.service "kick unit"
if [ ! -f /usr/local/sbin/v4l2-relayd-kick ] || ! cmp -s etc/v4l2-relayd-kick /usr/local/sbin/v4l2-relayd-kick; then
    install -D -m0755 etc/v4l2-relayd-kick /usr/local/sbin/v4l2-relayd-kick
    CHANGED=1; ok "kick script written"
else ok "kick script current"; fi
systemctl daemon-reload
systemctl is-enabled v4l2-relayd-kick.service >/dev/null 2>&1 \
    || { systemctl enable v4l2-relayd-kick.service >/dev/null 2>&1; CHANGED=1; ok "enabled"; }

if [ "$CHANGED" = 1 ]; then update-grub >/dev/null 2>&1; fi

# -------------------------------------------------------------------- verify
say "Verify"
for m in intel_ipu7_psys intel_cvs ov08x40 v4l2loopback; do
    modinfo -k "$K" "$m" >/dev/null 2>&1 && ok "module $m" || no "module $m MISSING"
done
[ -e /dev/ipu7-psys0 ] && ok "/dev/ipu7-psys0" || no "/dev/ipu7-psys0 missing (reboot?)"
media-ctl -d /dev/media0 -p 2>/dev/null | grep -q ov08x40 && ok "sensor in media graph" \
    || no "sensor not bound (reboot?)"

systemctl restart v4l2-relayd@default.service 2>/dev/null; sleep 3
pgrep -af 'v4l2-relayd -i' | grep -q flip-mode && ok "relayd running with flip-mode" \
    || no "relayd not running with flip-mode"

cd /tmp && rm -f setupchk*.jpg
timeout 30 gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert \
    ! jpegenc ! multifilesink location=setupchk%02d.jpg >/dev/null 2>&1
n=$(ls setupchk*.jpg 2>/dev/null | wc -l); u=$(ls -l setupchk*.jpg 2>/dev/null | awk '{print $5}' | sort -u | wc -l)
rm -f setupchk*.jpg

say "Result"
if [ "$n" -ge 10 ] && [ "$u" -gt 1 ]; then
    ok "LIVE VIDEO ($n frames, $u distinct sizes)"
    info "Check orientation too: https://mozilla.github.io/webrtc-landing/gum_test.html"
else
    no "no live video ($n frames, $u distinct sizes)"
    info "If packages or modules changed above, reboot and re-run this script."
    info "Otherwise see camera.md -> Diagnosing."
fi
[ "$CHANGED" = 1 ] && info "Changes were made; reboot to confirm they hold from cold."
