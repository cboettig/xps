# Built-in camera is upside down

The built-in camera (Intel IPU7, `ov08x40` sensor) delivers a 180°-rotated image to every
application. The external USB webcam is unaffected — it is a plain UVC device on a separate path.

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

Only `flip-mode=vhflip` is added; every other line is the stock value. Then:

```sh
sudo systemctl restart v4l2-relayd@default.service
```

`vhflip` is a vertical + horizontal flip, i.e. a true 180° rotation. It is applied inside the
camera HAL, so it costs no per-frame CPU, keeps the Bayer phase intact (colours stay correct),
and applies to every consumer of `/dev/video0`.

## Verify

```sh
pgrep -a -f 'v4l2-relayd -i'    # argv should contain flip-mode=vhflip
```

Then check the image itself, e.g. <https://mozilla.github.io/webrtc-landing/gum_test.html>.

The setting is read at service start, so it persists across reboots.
