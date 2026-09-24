#!/bin/bash
# Read-only check for the two states that wedge this machine: a leaked IPU7
# camera reference (blocks suspend, leaves the privacy LED on) and cs35l56
# speaker amps parked in runtime-PM error (silent speakers, journal flood).
#
#   ./suspend-check.sh            # no root needed
#
# See suspend.md for the causal chain and the recovery commands.

ok(){   printf '  [ OK ] %s\n' "$*"; }
no(){   printf '  [FAIL] %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
say(){  printf '\n\033[1m== %s\033[0m\n' "$*"; }
BAD=0

say "Camera / IPU7"
for n in isys psys; do
    p=/sys/bus/auxiliary/devices/intel_ipu7.$n.40/power
    [ -r "$p/runtime_usage" ] || { info "$n not present"; continue; }
    u=$(cat "$p/runtime_usage"); s=$(cat "$p/runtime_status")
    if [ "$u" -eq 0 ]; then
        ok "$n idle (status=$s)"
    else
        no "$n pinned (status=$s usage=$u)"
        BAD=1
    fi
done
holders=$(for fd in /proc/[0-9]*/fd/*; do
    [ "$(readlink "$fd" 2>/dev/null)" = /dev/video0 ] || continue
    p=${fd#/proc/}; echo "$(cat "/proc/${p%%/*}/comm" 2>/dev/null) (${p%%/*})"
done | sort -u)
[ -n "$holders" ] && info "/dev/video0 held by: $(echo "$holders" | tr '\n' ' ')"

say "Speaker amps (cs35l56)"
n_err=0 n_tot=0
for d in /sys/bus/soundwire/drivers/cs35l56/sdw:*/power/runtime_status; do
    [ -r "$d" ] || continue
    n_tot=$((n_tot + 1))
    [ "$(cat "$d")" = error ] && n_err=$((n_err + 1))
done
if [ "$n_tot" -eq 0 ]; then
    info "no cs35l56 amps bound"
elif [ "$n_err" -eq 0 ]; then
    ok "$n_tot amps healthy"
else
    no "$n_err of $n_tot amps in runtime-PM error"
    unatt=$(grep -lx UNATTACHED /sys/bus/soundwire/devices/sdw:*/status 2>/dev/null | wc -l)
    if [ "$unatt" -gt 0 ]; then
        info "$unatt also UNATTACHED on the SoundWire bus -- only a reboot fixes that"
    else
        info "recover: sudo ./amp-rebind.sh   (or reboot)"
    fi
    BAD=1
fi

say "Recent suspend attempts"
fails=$(journalctl -b -k --no-pager 2>/dev/null | grep -c 'failed to suspend')
last_ok=$(journalctl -b -k --no-pager -o short-iso 2>/dev/null | grep 'PM: suspend exit' | tail -1 | cut -d' ' -f1)
if [ "$fails" -eq 0 ]; then
    ok "no aborted suspends this boot"
else
    no "$fails aborted suspends this boot"
    journalctl -b -k --no-pager 2>/dev/null | grep 'failed to suspend' \
        | sed 's/.*kernel: //' | sort | uniq -c | sort -rn | head -5 | sed 's/^/         /'
    BAD=1
fi
[ -n "$last_ok" ] && info "last suspend exit: $last_ok"

say "Result"
[ "$BAD" -eq 0 ] && ok "nothing wedged" || no "see above"
exit "$BAD"
