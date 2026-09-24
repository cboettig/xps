#!/bin/bash
# Recover the cs35l56/CS35L57 speaker amps from runtime-PM error state without
# rebooting. Unbinding and rebinding the driver clears the error and re-runs the
# probe, which reloads the DSP firmware and reapplies calibration.
#
#   sudo ./amp-rebind.sh
#
# A reboot is the guaranteed fix; this is the cheaper thing to try first. See
# suspend.md for how the amps get into this state.
set -u
[ "$(id -u)" = 0 ] || { echo "needs root: sudo $0" >&2; exit 1; }

DRV=/sys/bus/soundwire/drivers/cs35l56
[ -d "$DRV" ] || { echo "cs35l56 driver not loaded" >&2; exit 1; }

mapfile -t DEVS < <(cd "$DRV" && ls -d sdw:* 2>/dev/null)
[ "${#DEVS[@]}" -gt 0 ] || { echo "no amps bound to cs35l56" >&2; exit 1; }

echo "amps: ${DEVS[*]}"
for d in "${DEVS[@]}"; do
    printf '  before %s: status=%-9s bus=%s\n' "$d" \
        "$(cat "$DRV/$d/power/runtime_status" 2>/dev/null)" \
        "$(cat /sys/bus/soundwire/devices/$d/status 2>/dev/null)"
done

# A rebind re-probes the driver; it cannot re-enumerate the SoundWire link. If
# the peripherals have dropped off the bus, probe will just time out waiting for
# initialization_complete again. Say so instead of wasting a minute on it.
unatt=0
for d in "${DEVS[@]}"; do
    [ "$(cat /sys/bus/soundwire/devices/$d/status 2>/dev/null)" = UNATTACHED ] \
        && unatt=$((unatt + 1))
done
if [ "$unatt" -gt 0 ]; then
    echo
    echo "$unatt of ${#DEVS[@]} amps are UNATTACHED on the SoundWire bus." >&2
    echo "A driver rebind cannot fix that -- re-attaching needs a link reset," >&2
    echo "and the SOF module stack is too deeply in use to reload. Reboot." >&2
    exit 1
fi

# PipeWire retries the failing Speaker sink every ~5s. Stop it poking the amps
# while they are half-bound.
RESTART_PW=0
if systemctl --user -M "${SUDO_USER:-root}@" is-active pipewire.service >/dev/null 2>&1; then
    RESTART_PW=1
fi

echo "unbinding..."
for d in "${DEVS[@]}"; do echo "$d" > "$DRV/unbind" || echo "  unbind $d failed" >&2; done
sleep 1
echo "binding..."
for d in "${DEVS[@]}"; do echo "$d" > "$DRV/bind" || echo "  bind $d failed" >&2; done

# Probe reloads ~1MB of DSP firmware per amp; give it a moment.
sleep 4

rc=0
for d in "${DEVS[@]}"; do
    s=$(cat "$DRV/$d/power/runtime_status" 2>/dev/null || echo gone)
    printf '  after  %s: %s\n' "$d" "$s"
    [ "$s" = error ] && rc=1
done

if [ "$RESTART_PW" = 1 ]; then
    echo "restarting pipewire for ${SUDO_USER:-root}..."
    systemctl --user -M "${SUDO_USER:-root}@" restart pipewire.service wireplumber.service 2>/dev/null \
        || echo "  could not restart pipewire; log out/in or restart it yourself" >&2
fi

if [ "$rc" = 0 ]; then
    echo "OK - amps out of error state. Test: speaker-test -c2 -twav -l1"
else
    echo "still in error - reboot" >&2
fi
exit "$rc"
