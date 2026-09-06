# The camera stack

Intel IPU7 with an `ov08x40` sensor (Panther Lake, `libcamhal-ipu75xa`). The pipeline:

```
ov08x40 sensor -> intel_ipu7 (ISYS: capture) -> intel_ipu7_psys (processing)
                     |
                  libcamhal  ->  icamerasrc  ->  v4l2-relayd  ->  v4l2loopback (/dev/video0)
                                                                        |
                                                                   applications
```

Applications never touch the IPU7 nodes directly — they open `/dev/video0`, a loopback fed by
`v4l2-relayd`. The external USB webcam is unaffected by all of this; it is a plain UVC device.

Setup is automated in [setup.sh](setup.sh). This file is the reference for how it works and
how to debug it.

## The sensor is mounted upside down

The kernel knows, and nothing acts on it:

```console
$ v4l2-ctl -d /dev/v4l-subdev4 --get-ctrl=camera_sensor_rotation
camera_sensor_rotation: 180        # read-only
```

The fix is `flip-mode=vhflip` on `icamerasrc` in `/etc/v4l2-relayd.d/default.conf`:

```sh
VIDEOSRC=icamerasrc buffer-count=7 flip-mode=vhflip
```

`vhflip` is vertical + horizontal, i.e. a true 180° rotation. It happens inside the HAL, so
it costs no per-frame CPU, keeps the Bayer phase intact (colours stay correct), and applies
to every consumer of `/dev/video0`.

Two approaches that do **not** work, so they don't get retried:

- Appending `! videoconvert ! videoflip method=rotate-180` — `v4l2-relayd` silently drops
  chained elements in both its `-i` and `-o` pipelines.
- `V4L2_CID_HFLIP`/`VFLIP` on the sensor subdev (via `v4l2-ctl`, a udev rule, an
  `ExecStartPre`, or a `control` block in `ov08x40-uf.json`) — the write is accepted and
  reads back as `1`, but only intermittently reaches the sensor.

**Release upgrades replace this file without prompting.** A copy lives in
[etc/v4l2-relayd-default.conf](etc/v4l2-relayd-default.conf). After any `v4l2-relayd`
update:

```sh
pgrep -af 'v4l2-relayd -i' | grep -o 'flip-mode=[a-z]*'
```

Verified on `v4l2-relayd` 0.2.0 / `libcamhal-ipu75xa` `~ubuntu26.04.1`. 0.2.0 also installs a
top-level `/etc/v4l2-relayd` with identical content that the templated unit does **not**
read — edit the `.d/` file.

## The relayd kick

`v4l2-relayd`'s first run after boot creates the loopback device but never streams. It is
not a crash — `systemctl` reports `active`, the process sits at ~0% CPU holding no file
descriptor, and the unit logs nothing. `/dev/video0` exists and returns one stale frame.
Restarting the service fixes it until the next boot.

`setup.sh` installs a `Type=oneshot` service that runs after relayd, waits for the loopback
device, and issues one `try-restart`. Oneshot means it cannot loop; it never blocks relayd
from starting.

```sh
journalctl -b -t v4l2-relayd-kick     # "device 'Intel MIPI Camera' present, restarting relayd"
```

**This fix is empirical.** Established: relayd creates the loopback device itself
(`ATTR{format}` on `video0` matches its configured `NV12:1280x720@30`), and a restart with
the device already present streams correctly. Not established: why the first run does not.
Boot timings have been inconsistent between reboots, so treat any causal story with
suspicion.

## Verifying

Work down the stack; each step localises the failure to one layer.

```sh
lsmod | grep -E 'intel_cvs|ipu7_psys|v4l2loopback'   # modules loaded
ls -l /dev/ipu7-psys0                                # processing device exists
media-ctl -d /dev/media0 -p | grep ov08x40           # sensor bound
journalctl -b -t v4l2-relayd-kick                    # relayd was kicked
pgrep -af 'v4l2-relayd -i' | grep -o 'flip-mode=[a-z]*'
```

A working boot log shows:

```
intel-ipu7 0000:00:05.0: Found supported sensor OVTI08F4:00
intel_ipu7_isys.isys ...: All sensor registration completed.
intel_ipu7_psys.psys ...: IPU psys probe done.
```

Then capture actual pixels:

```sh
gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert ! jpegenc \
  ! multifilesink location=f%02d.jpg
ls -l f*.jpg | awk '{print $5}' | sort -u | wc -l    # must be > 1
```

### Three traps

**`/dev/video0` always yields a frame.** It is a loopback, so a capture succeeds and returns
a placeholder even when the camera is completely dead. **Count distinct file sizes, not
files** — one frame, or twenty identical ones, is a failure. This is the single most
misleading thing about debugging this stack.

**Running `icamerasrc` as your user fails on a working system.** `/dev/ipu7-psys0` is
`root:root 0600`, and libcamhal's shared-memory segment is root-owned, so a user-run pipeline
reports `Fail to allocate shared memory by shmget` or `configure psys dag failed:-38`.
`v4l2-relayd` runs as root and is unaffected. Test through `/dev/video0`.

**`systemctl is-active` says `active` when relayd is doing nothing.** See
[the relayd kick](#the-relayd-kick). Check CPU and open fds, not unit state.

## Diagnosing

| Symptom | Cause |
|---|---|
| One frame then stall, everything else looks fine | relayd not streaming — kick it, see above |
| `psys device_register failed`, no `/dev/ipu7-psys0` | kernel regression; on 24.04 see [kernel.md](kernel.md#the-700-31-regression-2404-only) |
| `CamHAL: parseSensors: No sensors available`, no `ov08x40` in media graph | `intel_cvs` not loaded — missing or shadowed `vision` module package |
| `Failed to find module 'v4l2loopback'`, relayd `start-limit-hit` | no `v4l2loopback` for this kernel; boot a newer generic kernel |
| `disagrees about version of symbol module_layout` | module built for a different kernel build — see [kernel.md](kernel.md#module-packages) |
| Image upside down | `flip-mode=vhflip` lost from the relayd config |

`sudo ./setup.sh` re-checks and repairs most of these.
