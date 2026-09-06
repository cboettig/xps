# Fresh install: Ubuntu 26.04 on the XPS 14

For a clean 26.04.1 install. Coming from the factory 24.04 image instead? See
[upgrade.md](upgrade.md).

Everything except the OS install itself is done by [setup.sh](setup.sh):

```sh
git clone https://github.com/cboettig/xps.git
cd xps/xps14
sudo ./setup.sh
sudo reboot
sudo ./setup.sh          # re-run after reboot; should report LIVE VIDEO with no changes
```

It is idempotent — re-running it on a working system verifies the machine still matches
these notes and changes nothing.

## What it does, and why each step is needed

| Step | Why |
|---|---|
| Adds `dell.archive.canonical.com` (`somerville`, `somerville-hypno`) | `libcamhal` and `icamerasrc` exist **only** there. Without it you have libcamera alone, which is not this stack. `ubuntu-oem-keyring` (in Ubuntu `main`) supplies the signing key. |
| Installs 5 module metapackages | `ipu7` (psys), `vision` (`intel_cvs`), `ipu6` (`ov08x40`), `usbio`, `v4l2loopback`. Miss any one and the camera fails in a different place. |
| Installs `libcamhal-ipu75xa`, `gstreamer1.0-icamera`, `v4l2-relayd` | the userspace pipeline |
| Installs `oem-somerville-hypno-meta` | vendor metapackage for this platform; also supplies the IPU7 firmware config |
| Writes `/etc/v4l2-relayd.d/default.conf` | adds `flip-mode=vhflip` — the sensor is mounted upside down. See [camera.md](camera.md). |
| Writes `/etc/modprobe.d/ipu7-order.conf` | softdep so `intel_ipu7` loads after the USBIO GPIO controller |
| Writes `/etc/default/grub.d/zz-flavour-order.cfg` | the OEM meta sets `GRUB_FLAVOUR_ORDER=oem`, which sorts OEM kernels ahead of generic *regardless of version*. This overrides it back to generic. |
| Sets `GRUB_DEFAULT=0` | with the above, "newest generic" |
| Installs the `v4l2-relayd-kick` oneshot service | relayd does not stream on its first run after boot. See [camera.md](camera.md#the-relayd-kick). |

## Verifying

`setup.sh` ends with a live-capture test and prints a verdict. The one thing it cannot check
is image orientation — confirm that yourself at
<https://mozilla.github.io/webrtc-landing/gum_test.html>.

If it reports no live video after a reboot, see [camera.md](camera.md#diagnosing).

## Kernel choice

26.04 offers generic (`linux-generic-hwe-26.04`) and Dell/OEM (`linux-oem-26.04`,
`7.0.0-1013`). Generic is the default and is what this machine runs; the vendor metapackage
itself depends on generic at 26.04.

**Test the camera after any kernel update.** This hardware has been broken by one before
([LP #2166612](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612)), and
the camera depends on five separately-versioned module packages that an update can leave
behind. `sudo ./setup.sh` is the check.
