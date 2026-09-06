# Built-in camera is upside down

The built-in camera (Intel IPU7, `ov08x40` sensor) delivers a 180°-rotated image to every
application. The external USB webcam is unaffected — it is a plain UVC device on a separate path.

> **Prerequisite:** this is a userspace fix and assumes the rest of the pipeline works. If
> you have *no* image rather than an upside-down one, the problem is not here. Check, in
> order: psys probed and the sensor bound ([kernel.md](kernel.md#verifying)), then that
> `v4l2-relayd` is actually streaming rather than asleep
> ([the boot race](kernel.md#two-things-the-2604-upgrade-broke) — it reports `active` while
> doing nothing).

> **Survives upgrades badly.** The 26.04 upgrade **replaced** this file outright rather than
> prompting, silently dropping `flip-mode=vhflip`. A copy lives in
> [etc/v4l2-relayd-default.conf](etc/v4l2-relayd-default.conf); re-check after any
> `v4l2-relayd` update:
>
> ```sh
> pgrep -af 'v4l2-relayd -i' | grep -o 'flip-mode=[a-z]*'
> ```

## Cause

The sensor is physically mounted rotated 180°, and the kernel knows it:

```console
$ v4l2-ctl -d /dev/v4l-subdev4 --get-ctrl=camera_sensor_rotation
camera_sensor_rotation: 180        # read-only
```

Nothing in the `icamerasrc` → `v4l2-relayd` → `v4l2loopback` (`/dev/video0`) path acts on that
value, so the rotation reaches applications uncorrected.

## Fix

Set `flip-mode=vhflip` on `icamerasrc` in `/etc/v4l2-relayd.d/default.conf`:

```sh
VIDEOSRC=icamerasrc buffer-count=7 flip-mode=vhflip
FORMAT=NV12
WIDTH=1280
HEIGHT=720
FRAMERATE=30/1
CARD_LABEL=Intel MIPI Camera
```

Only `flip-mode=vhflip` is added; every other line is the stock value. The deployed file also
carries a comment block recording the approaches that were tried and rejected, so they don't
get re-attempted:

- appending `! videoconvert ! videoflip method=rotate-180` to the pipeline — `v4l2-relayd`
  silently drops chained elements in both its `-i` and `-o` pipelines, though the element
  itself works fine elsewhere;
- `V4L2_CID_HFLIP`/`VFLIP` on the sensor subdev (via `v4l2-ctl`, a udev rule, an
  `ExecStartPre`, or a `control` block in `/etc/camera/ipu75xa/sensors/ov08x40-uf.json`) — the
  write is accepted and reads back as `1`, but only intermittently reaches the sensor.

Then:

```sh
sudo systemctl restart v4l2-relayd@default.service
```

Note that `ov08x40-uf.json` is not a stock file — `oem-somerville-hypno-meta` diverts it and
substitutes Dell's tuning. See [oem-stack.md](oem-stack.md#the-ov08x40-tuning-diversion)
before editing or removing anything that touches it.

`vhflip` is a vertical + horizontal flip, i.e. a true 180° rotation. It is applied inside the
camera HAL, so it costs no per-frame CPU, keeps the Bayer phase intact (colours stay correct),
and applies to every consumer of `/dev/video0`.

## Verify

```sh
pgrep -a -f 'v4l2-relayd -i'    # argv should contain flip-mode=vhflip
```

Then check the image itself, e.g. <https://mozilla.github.io/webrtc-landing/gum_test.html>.
For a headless check, grab frames and confirm the file sizes *vary* — a single frame, or
identical sizes, means the pipeline is dead rather than merely rotated:

```sh
gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert ! jpegenc \
  ! multifilesink location=frame%02d.jpg
ls -l frame*.jpg | awk '{print $5}' | sort -u | wc -l    # must be > 1
```

The setting is read at service start, so it persists across reboots — but see the upgrade
warning above; the *file* is what does not persist.

Verified on `v4l2-relayd` 0.2.0 / `libcamhal-ipu75xa` `~ubuntu26.04.1` (Ubuntu 26.04,
2026-09-06). The config format is unchanged from 0.1.2: same keys, and the unit still reads
`/etc/v4l2-relayd.d/<instance>.conf`. 0.2.0 also installs a top-level `/etc/v4l2-relayd`
with identical content, which the templated unit does **not** read — edit the `.d/` file.
