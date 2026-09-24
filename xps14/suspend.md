# Suspend, and how a camera leak kills the speakers

On 2026-09-23 the machine stopped suspending on lid close and the speakers went
silent. Those are the same bug: one leaked reference in the camera stack, and a
chain of consequences from the aborted suspend it causes.

## The chain

```
Zoom opens /dev/video0          v4l2-relayd starts the icamerasrc pipeline
        |                       and takes a runtime-PM reference on intel_ipu7.psys
Zoom exits                      *** the reference is never released ***
        |
lid close -> suspend            psys_suspend() returns -EBUSY (-16)
        |                       "PM: Some devices failed to suspend"
suspend aborted mid-unwind      devices already suspended get resumed again
        |
cs35l56 resume                  initialization_complete timed out -> -ETIMEDOUT (-110)
        |                       runtime PM marks all four amps status=error
PipeWire opens Speaker sink     pm_runtime_get() on a device in error -> -EINVAL (-22)
        |                       retries every ~5s, forever
```

The lasting damage is that last step. Once an amp is in `runtime_status=error`
nothing resumes it again, so the speakers stay dead and the journal fills at a
few lines per second until reboot or a driver rebind.

## Recognising it

`./suspend-check.sh` (read-only, no root) reports all three signatures. By hand:

```console
$ cat /sys/bus/auxiliary/devices/intel_ipu7.psys.40/power/runtime_usage
1                                       # leaked; 0 when healthy

$ cat /sys/bus/soundwire/drivers/cs35l56/sdw:*/power/runtime_status
error                                   # x4; "suspended" or "active" when healthy

$ journalctl -b -k | grep -c 'failed to suspend'
712
```

In the journal the tell is the pair

```
intel_ipu7_psys.psys: PM: failed to suspend: error -16
cs35l56 sdw:0:2:01fa:3557:01:2: initialization_complete timed out
```

and then `snd_soc_pcm_component_pm_runtime_get ... ASoC error (-22)` on repeat.
The `-22` lines are the symptom, not the cause — don't start there.

Other visible symptoms, in case the journal isn't where you start: the camera
privacy LED stays lit after the call ends, the lid does nothing, and the
battery drains as if the machine were awake — because it is.

## Recovery

```sh
sudo systemctl restart v4l2-relayd@default.service   # releases the IPU7 reference
sudo ./amp-rebind.sh                                 # clears the amp error state
```

The relayd restart is reliable and instant, and un-sticks suspend immediately.

**The amps usually need a reboot.** Check before bothering with the rebind:

```console
$ cat /sys/bus/soundwire/devices/sdw:*/status
Attached                                # the CS42L43 headset codec on master 0
UNATTACHED                              # the four CS35L57 amps on masters 2 and 3
UNATTACHED
UNATTACHED
UNATTACHED
```

If they read `UNATTACHED` they have dropped off the SoundWire bus, not merely
failed a resume. `amp-rebind.sh` re-probes the *driver*, which cannot
re-enumerate a link: probe just hits `cs35l56_component_probe: init_completion
timed out` again and the amps stay in error. Re-attaching needs a link reset,
which in practice means a reboot — reloading the SOF stack is not an option, as
`snd_sof` has nine dependent modules and `snd_sof_intel_hda_mlink` six, all live
while the card is open.

The rebind is worth trying only when the amps are still `Attached` and merely
`status=error`. It reloads ~1MB of DSP firmware per amp and reapplies
calibration; `amp-rebind.sh` checks bus status first and refuses otherwise.

## Prevention

[etc/v4l2-relayd-release](etc/v4l2-relayd-release), installed by `setup.sh` as
`/etc/systemd/system-sleep/v4l2-relayd-release`, runs before every suspend. If
the psys reference is held but nothing has `/dev/video0` open — exactly the leak
signature — it restarts relayd and waits for the reference to drop, so the
suspend that follows is not aborted and the amps are never asked to resume out
of order.

It deliberately does nothing when a process *does* hold `/dev/video0`: that is a
real capture, and killing the pipeline under it is worse than a failed suspend.

```console
$ journalctl -t v4l2-relayd-release
... psys pinned with no camera client; restarting relayd
... psys runtime_usage now 0
```

## Why the leak exists

`v4l2-relayd` runs the `icamerasrc -> v4l2sink` pipeline as a long-lived process
(one since boot, restarted only by the kick service). When the last consumer of
the loopback closes, the pipeline is supposed to drop to NULL and release the
HAL. It doesn't — the process idles at 0% CPU with the IPU still powered:

```console
$ ps -o etime=,pcpu= -p "$(pgrep -f 'v4l2-relayd -i')"
   5-05:55:10  0.1                      # 0 jiffies over a 3s sample
$ cat /sys/bus/auxiliary/devices/intel_ipu7.isys.40/power/runtime_active_time
26955676                                # 7h29m "active" with nothing streaming
```

Not yet reported upstream; it needs a clean reproduction on a stock image
(open camera, close app, check `runtime_usage`) before it is worth filing
against `v4l2-relayd` or `libcamhal-ipu75xa`.
