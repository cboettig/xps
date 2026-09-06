# Built-in camera is upside down

The built-in camera (Intel IPU7, `ov08x40` sensor) delivers a 180°-rotated image to every
application. The external USB webcam is unaffected — it is a plain UVC device on a separate path.

> **Prerequisite:** this is a userspace fix and assumes the kernel half already works. If you
> have *no* image rather than an upside-down one, the problem is not here — check that the
> psys device probed, per [kernel.md](kernel.md#verifying). On `7.0.0-31-generic` it does not.

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

The setting is read at service start, so it persists across reboots.
