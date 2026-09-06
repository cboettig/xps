#!/bin/bash
# Test the XPS 14 (DA14260) built-in camera from a live USB session.
#
#   sudo bash live-test.sh
#
# Answers one question: does the IPU7 camera work on the kernel this live
# session is running? Prints a verdict at the end. Safe to re-run.
#
# It never unbinds the IPU7 PCI device. On 7.0.0-31-generic that oopses
# (ipu7_pci_remove NULL deref) and wedges shutdown. See kernel.md.
#
# Context: https://github.com/cboettig/xps/tree/master/xps14
# Bug:     https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612

set -u
LOG=/root/camera-live-test.log
exec > >(tee -a "$LOG") 2>&1

KVER=$(uname -r)
CODENAME=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-unknown}")
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()  { printf '  [ OK ] %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; }
note(){ printf '         %s\n' "$*"; }

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

say "Session"
echo "  kernel:   $KVER"
echo "  release:  $CODENAME"
echo "  log:      $LOG   (copy this off before rebooting)"
case "$KVER" in
  7.0.0-31-*) note "This is the ABI known to be broken on noble (LP #2166612)." ;;
  7.0.0-30-*) note "Known-good ABI on noble. A pass here says little about -31." ;;
  *)          note "Neither of the ABIs tested so far; result is new information." ;;
esac

# ---------------------------------------------------------------- Dell archive
# The camera userspace (libcamhal / icamerasrc) is ONLY in Dell's archive.
# Without this, you are testing libcamera alone, which is not what this
# machine normally runs.
say "Enabling the Dell OEM archive"
apt-get install -y ubuntu-oem-keyring >/dev/null 2>&1 \
  && ok "ubuntu-oem-keyring installed" || bad "could not install ubuntu-oem-keyring"
printf 'deb http://dell.archive.canonical.com/ %s somerville somerville-hypno\n' "$CODENAME" \
  > /etc/apt/sources.list.d/dell-test.list
ok "added dell.archive.canonical.com $CODENAME"
apt-get update -qq 2>&1 | grep -Ei 'dell|error|warn' | sed 's/^/         /'

# ------------------------------------------------------------ kernel modules
# Package naming differs by release: noble uses linux-modules-<thing>-<ver>,
# resolute renamed them to linux-main-modules-<thing>-<ver>.
say "Installing kernel camera modules for $KVER"
for thing in vision ipu7 v4l2loopback; do
  installed=no
  for pfx in linux-main-modules linux-modules; do
    pkg="$pfx-$thing-$KVER"
    if apt-get install -y "$pkg" >/dev/null 2>&1; then
      ok "$pkg"; installed=yes; break
    fi
  done
  [ "$installed" = yes ] || bad "no package found for '$thing' on $KVER"
done

# ------------------------------------------------------------------- probing
# No reboot is possible in a live session, so load the modules by hand. The
# psys module registers its bus at module_init; the aux device already exists
# from boot, so probe fires on load. DO NOT unbind to force a re-probe.
say "Loading modules"
for m in intel_cvs intel_ipu7_psys v4l2loopback; do
  modprobe "$m" 2>&1 | sed 's/^/         /'
  lsmod | grep -q "^${m//-/_}" && ok "$m loaded" || bad "$m not loaded"
done

say "Kernel verdict"
PSYS=no
if [ -e /dev/ipu7-psys0 ]; then ok "/dev/ipu7-psys0 exists"; PSYS=yes
else bad "/dev/ipu7-psys0 missing"; fi
dmesg | grep -iE 'IPU psys probe done|psys device_register failed|unregistered bus|disagrees about version' \
  | tail -5 | sed 's/^/         /'
if media-ctl -d /dev/media0 -p 2>/dev/null | grep -q ov08x40; then
  ok "sensor ov08x40 present in the media graph"
else
  bad "sensor ov08x40 NOT in the media graph"
fi
note "Caveat: modules were loaded late, not at boot. A cold boot can still"
note "differ. For a real answer use a persistent live USB and reboot."

# ----------------------------------------------------------------- userspace
say "Installing camera userspace"
apt-get install -y gstreamer1.0-icamera libcamhal-ipu75xa v4l2-relayd \
      gstreamer1.0-libcamera gstreamer1.0-tools v4l-utils >/dev/null 2>&1 \
  && ok "icamera + libcamera userspace installed" \
  || bad "userspace install failed (check the Dell archive lines above)"

CONF=/etc/v4l2-relayd.d/default.conf
if [ -d /etc/v4l2-relayd.d ]; then
  cat > "$CONF" <<'EOF'
VIDEOSRC=icamerasrc buffer-count=7 flip-mode=vhflip
FORMAT=NV12
WIDTH=1280
HEIGHT=720
FRAMERATE=30/1
CARD_LABEL=Intel MIPI Camera
EOF
  ok "wrote $CONF (with the 180-degree flip fix)"
  systemctl restart v4l2-relayd@default.service 2>/dev/null
  sleep 3
  systemctl is-active --quiet v4l2-relayd@default.service \
    && ok "v4l2-relayd running" || bad "v4l2-relayd not running"
else
  bad "/etc/v4l2-relayd.d missing - v4l2-relayd 0.2.0 may use a new config layout"
  note "check: dpkg -L v4l2-relayd | grep -i conf"
fi

# ------------------------------------------------------------------- capture
# /dev/video0 is a v4l2loopback node: it yields a placeholder frame even when
# the camera is dead. Distinct file SIZES are the only honest signal.
grab() {
  local label=$1 pipeline=$2 dir=/root/frames-$1
  rm -rf "$dir"; mkdir -p "$dir"
  timeout 40 gst-launch-1.0 -q $pipeline num-buffers=20 ! videoconvert ! jpegenc \
    ! multifilesink location="$dir/f%02d.jpg" >/dev/null 2>&1
  local n u
  n=$(ls "$dir"/*.jpg 2>/dev/null | wc -l)
  u=$(ls -l "$dir"/*.jpg 2>/dev/null | awk '{print $5}' | sort -u | wc -l)
  if [ "$n" -ge 10 ] && [ "$u" -gt 1 ]; then
    ok "$label: $n frames, $u distinct sizes -> REAL VIDEO"; return 0
  else
    bad "$label: $n frames, $u distinct sizes -> not live"; return 1
  fi
}
say "Capturing frames"
RELAY=fail; LIBCAM=fail
grab relayd    "v4l2src device=/dev/video0" && RELAY=pass
grab libcamera "libcamerasrc"               && LIBCAM=pass
note "JPEGs in /root/frames-*/ - open them to check orientation too."

# -------------------------------------------------------------------- verdict
say "VERDICT for $KVER on $CODENAME"
echo "  psys device node ......... $PSYS"
echo "  icamerasrc + v4l2-relayd . $RELAY   <- the path this machine normally uses"
echo "  libcamerasrc (native) .... $LIBCAM  <- the 26.04 alternative"
echo
if [ "$RELAY" = pass ]; then
  echo "  => Camera works on this kernel via the normal path. Upgrading should be safe."
elif [ "$LIBCAM" = pass ]; then
  echo "  => Dell HAL path is broken but libcamera works. Viable, but the flip fix"
  echo "     in camera.md would need a libcamera-side equivalent."
elif [ "$PSYS" = no ]; then
  echo "  => psys did not probe: same failure as LP #2166612. Do NOT rely on this"
  echo "     kernel. Try linux-oem-26.04 (7.0.0-1013, a separate ABI line) instead."
else
  echo "  => psys probed but no frames: failure is in userspace, not the kernel."
  echo "     Check that the Dell archive lines above actually succeeded."
fi
echo
echo "  Full log: $LOG  (in RAM - copy to the USB stick before rebooting)"
