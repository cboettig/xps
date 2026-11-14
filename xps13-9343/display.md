# Display

The Broadwell display engine is the fragile part of this machine. Three separate
problems, each with its own fix.

## Kernel parameters

```
GRUB_CMDLINE_LINUX_DEFAULT="i915.enable_psr=0 i915.enable_dc=0"
```

These turn off panel self-refresh and display C-states. They fixed a blank screen before
the login screen appeared. Keep them: they are not the cause of the Sway freeze below
(GNOME runs fine with them), and `enable_dc=0` did not prevent it either.

## Sway freezes on resume

**Symptom.** After suspend and resume, or on login after an earlier resume, Sway shows a
frozen cursor and nothing else: no bar, no background, no keyboard. The machine itself
is alive. GNOME on the same boot is fine.

**Cause.** wlroots fails its DRM atomic commit on every frame:

```
[ERROR] [wlr] [backend/drm/atomic.c:239] Failed to acquire FB for plane 44
```

wlroots commits every plane in one atomic commit, so one plane that cannot get a scanout
framebuffer blocks every frame. Plane 44 is the hardware cursor plane. At a cold start
wlroots recovers after a few errors; after resume it does not. A warm `reboot` does not
reset the display engine, so the bad state survives it; only a full power-off clears it.
mutter handles the plane differently and is unaffected.

**Fix.** Use a software cursor, so wlroots never touches that plane:

```sh
# ~/.config/environment.d/wlroots.conf
WLR_NO_HARDWARE_CURSORS=1
```

GNOME ignores `WLR_*` variables, so it is safe to leave set globally. Confirm inside Sway
with `env | grep WLR`. If it is missing, the display manager did not read
`environment.d`; put the line in `/etc/environment` instead.

If it comes back, the next steps in order are `WLR_DRM_NO_MODIFIERS=1`, both together,
then `WLR_DRM_NO_ATOMIC=1`. To test without rebooting each time, start `sway` from a
text console (`Ctrl+Alt+F3`) while a GNOME session stays up on another VT, and
`pkill -9 sway` from there if it wedges.

**Diagnose with** `journalctl _COMM=sway | grep 'plane'`.

## External ultrawide drops out

**Symptom.** A 3440x1440 ultrawide (Dell U3417W) on DisplayPort goes blank on window
focus changes, never when idle. The laptop sees no unplug event; only replugging
recovers it.

**Cause.** `CPU pipe A FIFO underrun` in the kernel log: bursts of memory traffic starve
the display FIFO. Not a cable or link fault; there are no link-training or hotplug
errors. Running on battery in the `quiet` power profile makes it worse by raising memory
latency. A 4K monitor at 60 Hz works, despite the higher pixel rate, so this is a
watermark threshold rather than raw bandwidth.

**Fix.** Run that monitor at 3440x1440 **50 Hz**. In kanshi the profile pins
`mode 3440x1440@50Hz` and matches the monitor by make, model and serial, never by
connector name, so the mode is not forced onto other monitors. Under GNOME it is set in
Settings → Displays and stored in `~/.config/monitors.xml`. Fifteen minutes of
switching focus at 50 Hz gave no underruns, against 9 before.

To keep 60 Hz on battery instead, the kernel parameter `intel_idle.max_cstate=2` limits
deep C-states, or run on AC in the Balanced profile.

**Diagnose with** `journalctl -b -k | grep 'FIFO underrun'`.

## No monitor detected after resume

**Symptom.** After an S3 resume, a connected external monitor (any of them, projectors
included) never appears. Every external connector reports `disconnected` and the kernel
logs no hotplug.

**Check first:**

```sh
cat /sys/class/drm/card1-*/status
```

If the external connectors say `disconnected`, the problem is below Sway and kanshi.

**Recovery.** Force a probe, then replug:

```sh
echo detect | sudo tee /sys/class/drm/card1-DP-1/status /sys/class/drm/card1-HDMI-A-1/status
```

It is not yet known which of the two steps is the fix. An unprivileged client cannot
force a probe, so an automatic fix would have to be a root system-sleep hook.
