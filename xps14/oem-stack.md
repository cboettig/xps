# The OEM package stack, and what can go

Dell preloads a vendor package set from two archives. Knowing which piece does what matters
because some of it is inert factory scaffolding and some of it is load-bearing for the
camera.

| Archive | Components | Supplies |
|---|---|---|
| `dell.archive.canonical.com` | `somerville`, `somerville-hypno` | camera userspace (`libcamhal*`, `gstreamer1.0-icamera`, `libia-*`), `oem-somerville-*-meta` |
| `oem.archive.canonical.com` | `hwe`, `nantou` | `oem-hwe-meta`, `oem-nantou-meta`, `wpa-hwe`, `manage-estar-settings` |

`hypno` is the Dell platform codename for this machine; `somerville` is the Dell program as
a whole.

## What the metapackages actually contain

Mostly nothing — they are dependency shims plus a few config files. `dpkg -L` is the fastest
way to see it:

| Package | Real payload |
|---|---|
| `oem-somerville-hypno-meta` | `oem-flavour.cfg` (GRUB), **`ov08x40-uf.json`** (camera tuning), apt source |
| `oem-somerville-meta` | nothing (`/usr` dirs only) |
| `oem-somerville-factory-meta` | nothing |
| `oem-somerville-factory-hypno-meta` | nothing |
| `oem-hwe-meta` | `/etc/apt/preferences.d/20-hwe`, apt source |
| `oem-nantou-meta` | apt source only |
| `wpa-hwe` | `/etc/apt/preferences.d/30-wpa-hwe` |

### The ov08x40 tuning diversion

This is the non-obvious one and the reason `oem-somerville-hypno-meta` should stay:

```console
$ dpkg -S /etc/camera/ipu75xa/sensors/ov08x40-uf.json
diversion by oem-somerville-hypno-meta from: /etc/camera/ipu75xa/sensors/ov08x40-uf.json
diversion by oem-somerville-hypno-meta to: /etc/camera/ipu75xa/sensors/ov08x40-uf.json.orig
libcamhal-ipu75xa-common: /etc/camera/ipu75xa/sensors/ov08x40-uf.json
```

The OEM meta *diverts* the stock sensor tuning file shipped by `libcamhal-ipu75xa-common`
and substitutes its own Dell-tuned version from
`/usr/share/oem-somerville-hypno-meta/ov08x40-uf.json`. Removing the meta reverts the camera
to generic Intel tuning. Nothing in the camera pipeline will error — the image quality just
quietly changes. See [camera.md](camera.md).

### The apt pins

`oem-hwe-meta` ships a pin that *demotes* the HWE archive to priority 1, i.e. never install
from it by default:

```
Package: *
Pin: release o=UbuntuHWE
Pin-Priority: 1
```

`wpa-hwe` then re-promotes exactly one package set back to 520:

```
Package: hostapd wpagui wpasupplicant wpasupplicant-udeb eapoltest libwpa-client-dev
Pin: release o=UbuntuHWE
Pin-Priority: 520
```

Which is why `wpasupplicant` is the OEM build (`2:2.11-0ubuntu4~24.04hwe1`) and nothing else
is. Don't remove `oem-hwe-meta` without understanding that its pin is what keeps the rest of
the HWE archive *out*.

## What is safe to remove

**Remove now — inert factory scaffolding.** These exist so the Dell factory line can select
an image; they carry no files and nothing depends on them except each other:

```sh
sudo apt purge oem-somerville-factory-hypno-meta oem-somerville-factory-meta
```

**Purge stale kernel leftovers.** Config-only (`rc`) remnants of superseded kernels:

```sh
dpkg -l | awk '$1=="rc"{print $2}' | grep -E '^linux-' | xargs -r sudo dpkg --purge
```

**Keep — load-bearing:**

| Package | Why |
|---|---|
| `oem-somerville-hypno-meta` | diverts `ov08x40-uf.json`; pulls the camera stack |
| `oem-somerville-meta` | dependency of the above |
| `libcamhal*`, `gstreamer1.0-icamera`, `libia-*` | *are* the camera userspace |
| `linux-oem-24.04d` + OEM kernel | known-good camera fallback; see [kernel.md](kernel.md) |
| `oem-hwe-meta` | required by `oem-somerville-hypno-meta` **on 24.04**; also owns the HWE pin |
| `wpa-hwe` | owns the pin exception that selects the OEM `wpasupplicant` |

`oem-nantou-meta` has no reverse dependencies and ships only an apt source, but it Recommends
`manage-estar-settings` (Energy Star power defaults), which is installed. Removing the meta
orphans that but does not uninstall it. Low value either way; leaving it is harmless.

**Do not remove the OEM kernel while `7.0.0-31-generic` is broken.** It is currently the only
fallback besides the held `7.0.0-30-generic`.

## Ubuntu 26.04 (resolute)

### The upgrader's "foreign packages" warning is a non-issue

Every package it flags resolves in resolute. Verified by grepping the fetched resolute
indexes directly rather than trusting `apt-cache` (see the caveat below):

- **`UbuntuESMApps` group** — `buildah`, `gh`, `rclone`, `libde265-0`, `libopenexr-3-1-30`,
  `libsoup-2.4-1`, `libsoup2.4-common`, `python3-pip-whl`. These are ordinary Ubuntu packages
  that happen to be served from the ESM pocket under Ubuntu Pro. All present in resolute
  `main`/`universe`; they upgrade normally.
- **`Canonical` group** — the whole `libcamhal*` / `libia-*` / `gstreamer1.0-icamera` camera
  stack and the `oem-somerville-*` metas. All present in
  `dell.archive.canonical.com resolute/somerville` (index fetched 2026-09-02, so current).

`oem.archive.canonical.com` does publish a `resolute` suite (its `InRelease` is present), but
no `hwe` or `nantou` component indexes have been fetched for it — only for `noble`. So
`oem-hwe-meta` / `oem-nantou-meta` / `wpa-hwe` *probably* go obsolete on upgrade, but that is
inferred from missing indexes, not confirmed.

> **Caveat 1 — the resolute data here is cached, and partly stale.** This machine runs noble;
> the resolute figures below come from index files left in `/var/lib/apt/lists/` by earlier
> upgrade checks, not from a live resolute system. Check their age before trusting a version
> number:
>
> ```console
> $ ls -l --time-style=+%F /var/lib/apt/lists/ | grep resolute.*Packages$
> 2026-04-23  archive.ubuntu.com ... resolute/{main,universe}   # ~release-time, stale
> 2026-09-02  dell.archive ... resolute/somerville              # current
> ```
>
> Package *presence* is reliable; *versions* from the Ubuntu resolute indexes may have moved.
> Re-fetch before depending on a specific version.

> **Caveat 2 that cost real time:** `apt-cache policy` and `apt-cache madison` report from
> `pkgcache.bin`, which on this machine is in a mixed state after a `do-release-upgrade` dry
> run — it showed resolute versions for some packages and none for others (claiming `htop`
> and `rclone` are absent from resolute, which is false). Grep the index files instead:
>
> ```sh
> grep -h '^Package: rclone$' \
>   /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_resolute*_{main,universe}_binary-amd64_Packages
> ```

### The camera userspace does carry forward

**An earlier revision of these notes said `libcamhal*` and `gstreamer1.0-icamera` are absent
from resolute and that the `icamerasrc` path would not survive the upgrade. That was wrong.**
They are absent from the *Ubuntu* archive but present in the *Dell* archive, which this
machine already has enabled. The conclusion came from a live-USB session, which has no
`dell.archive.canonical.com` source configured — so they genuinely look missing there.

Present in `dell.archive.canonical.com resolute/somerville`:

```
libcamhal-ipu75xa         0~git202604141000.58e6f01-1~ubuntu26.04.1
libcamhal0                0~git202601200757.9899efa~ubuntu26.04.2
gstreamer1.0-icamera      0~git202509261737.4fb31db~ubuntu26.04.1
```

`v4l2-relayd` is in resolute `universe` (0.2.0, up from 0.1.2). So the
`icamerasrc` → `v4l2-relayd` → `v4l2loopback` pipeline and the `flip-mode=vhflip` rotation
fix in [camera.md](camera.md) are all expected to carry over. The `v4l2-relayd` 0.1.2 → 0.2.0
jump is the one thing worth re-checking, since the fix lives in its config file.

Resolute also ships libcamera 0.7.0 with a native `intel-ipu7` pipeline handler, which is an
*alternative* path, not a forced migration.

### Kernel packages do not come from Dell

Worth stating plainly, because it is easy to assume otherwise: **`dell.archive.canonical.com`
ships no kernel packages at all.** Everything Dell provides is userspace — `libcamhal*`,
`gstreamer1.0-icamera`, `libia-*`. Every kernel driver, OEM flavour included, comes from
`archive.ubuntu.com`:

```console
$ apt-cache policy linux-oem-24.04d linux-modules-ipu7-oem-24.04d
  500 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
```

**The converse is also true and is the more important half: the Dell *userspace* is not
optional.** What is actually running is `icamerasrc` linked against Dell's HAL:

```console
$ ldd .../gstreamer-1.0/libgsticamerasrc.so | grep camhal
libcamhal.so.0 => /lib/x86_64-linux-gnu/libcamhal.so.0
```

Noble ships only `libcamera 0.2.0`, which has no IPU7 pipeline handler, so on 24.04 there is
**no non-Dell userspace path at all**. Moving from the OEM kernel to generic removed exactly
zero `dell.archive` packages — the OEM kernel and the Dell archive were never the same
dependency (`linux-oem-24.04d` ships from `archive.ubuntu.com`). Anyone reasoning "get off the
OEM kernel, then we are free of somerville" is conflating the two; it does not follow, and it
is not what happened.

That turns out not to matter, because somerville has resolute builds. The goal is "Dell
userspace plus a working kernel on 26.04", not "escape Dell".

There is no "vendor driver" fallback in kernel space, and no open-vs-proprietary
split between the OEM and generic kernels: `intel_ipu7`/`intel_ipu7_isys` are in-tree staging
in both, and `intel_ipu7_psys`/`intel_cvs` are the same out-of-tree modules rebuilt per ABI.
The two flavours differ in version and build, not in origin or licensing.

The corollary matters for triage: **the Dell userspace cannot compensate for a broken kernel
half.** `icamerasrc` → `libcamhal` opens `/dev/ipu7-psys0`. On `7.0.0-31` the complete Dell
stack was installed and `v4l2-relayd` was running normally, and the camera was still dead. If
psys has not probed, no userspace change will help.

### The upgrade switches the default to generic — but OEM remains available

`oem-somerville-hypno-meta` changes shape in 26.04:

| | 24.04ubuntu5 (installed) | 26.04ubuntu6 (resolute) |
|---|---|---|
| Depends | `linux-oem-24.04d`, `oem-hwe-meta`, `oem-somerville-meta` | **`linux-generic-hwe-26.04`**, `oem-somerville-meta` |
| Recommends | `wpa-hwe`, `libcamhal-ipu75xa`, `linux-modules-{ipu6,ipu7,usbio,vision}-oem-24.04d` | `libcamhal-ipu75xa`, `linux-modules-{ipu6,ipu7,usbio,v4l2loopback,vision}-generic-hwe-26.04` |

So Dell/Canonical themselves move this platform off the OEM kernel onto generic at 26.04, and
the module packages we installed by hand become Recommends of the vendor meta. The manual
work in [kernel.md](kernel.md) is the same thing, one release early.

**This is a change of default, not a withdrawal.** 26.04 has a full OEM kernel series with
matching camera modules:

```
linux-oem-26.04 / -26.04a / -26.04b    7.0.0-1013.13
linux-modules-ipu7-oem-26.04
linux-modules-vision-oem-26.04
linux-modules-usbio-oem-26.04
linux-modules-v4l2loopback-oem-26.04
```

That is the fallback if generic stays broken after upgrading, and it is a genuinely
independent bet: `7.0.0-1013` is the OEM `10xx` ABI line, built separately from the
`7.0.0-31` generic kernel whose core update broke psys. Same upstream base, different build,
different module set.

Consequences to plan for:

- `linux-oem-24.04d` and the `6.17.0-*-oem` kernels become orphaned — the `24.04d` series has
  no resolute successor. **Do not let the upgrade autoremove them until the camera is
  confirmed on a 26.04 kernel**; until then they are the fallback. Note the replacement is
  `linux-oem-26.04` (7.0.0-1013), a different series, not an upgrade of `24.04d`.
- `oem-hwe-meta` and `oem-nantou-meta` have no resolute candidate and
  `oem.archive.canonical.com` has no resolute suite indexed here at all. They will go
  obsolete. `wpa-hwe` goes with them, and `wpasupplicant` reverts to the archive build
  (`2:2.11-0ubuntu5`) — fine, but it is a real change to wifi supplicant code.

### Open question: does 26.04 fix 7.0.0-31?

Resolute carries `linux-modules-ipu7-generic-hwe-26.04` at `7.0.0-31.31+2`, a different build
of the same ABI as the `7.0.0-31.31~24.04.1` that is broken here. **Untested.** If it fixes
the psys probe, the held `7.0.0-30` pin can be dropped after upgrading. If it does not, 26.04
lands on a kernel whose camera does not work — so verify before releasing the holds.

Given that, the sane order is: confirm the camera on a 26.04 generic kernel *first* (live USB
or a snapshot), then upgrade, then clean up the OEM kernel — not the other way round.

Decision tree once on 26.04:

1. Boot the generic `-31`-series kernel. If `IPU psys probe done.` appears, nothing else to do
   — release the `7.0.0-30` holds.
2. If psys still fails, install `linux-oem-26.04` plus its `linux-modules-{ipu7,vision}-oem-26.04`
   and boot that. Different ABI, separately built, so the `-31` regression need not apply.
3. Only if *both* fail is the `icamerasrc` path in question — and that is the point to test
   resolute's libcamera 0.7.0 `intel-ipu7` pipeline handler as an alternative userspace.

### Testing 26.04 from a live USB

An earlier revision of these notes recorded that the `26.04.1` desktop ISO ships
`linux-image-7.0.0-30-generic`. **Re-check that before trusting it** — it was written before
`7.0.0-31` existed, and a point-release ISO respin may well carry `-31`, in which case the
live session will show a dead camera for the reason in
[kernel.md](kernel.md#the-700-31-regression) rather than anything to do with 26.04. Check
`uname -r` in the live session first and read the result accordingly.

If the ISO does carry `-30`, the module packages apply verbatim. The ISO does *not* include
`linux-modules-{vision,ipu7,ipu6}-*`, so the camera will not work in a stock live session.
Add them by hand (~300 KB, fine in the RAM overlay):

```sh
sudo apt update
sudo apt install linux-modules-vision-7.0.0-30-generic linux-modules-ipu7-7.0.0-30-generic
```

Use the version-pinned names, not the `-hwe-26.04` metapackages, in a throwaway session.

Two things a live session gets wrong, both of which produced false conclusions before:

1. **No Dell archive.** `libcamhal*` and `gstreamer1.0-icamera` are not on the ISO and not in
   the Ubuntu archive, so they look permanently missing. Add the source first:
   ```sh
   echo 'deb http://dell.archive.canonical.com/ resolute somerville somerville-hypno' \
     | sudo tee /etc/apt/sources.list.d/dell.list
   sudo apt update
   ```
   Without this you are testing libcamera-only, which is not the configuration this machine
   runs.
2. **You cannot reboot for a cold probe.** The obvious workaround is a driver rebind — but
   see the oops warning in [kernel.md](kernel.md#do-not-unbind-the-ipu7-device-on-700-31).
   On `7.0.0-30` the rebind is safe:
   ```sh
   sudo modprobe intel_cvs
   echo 0000:00:05.0 | sudo tee /sys/bus/pci/drivers/intel-ipu7/unbind
   echo 0000:00:05.0 | sudo tee /sys/bus/pci/drivers/intel-ipu7/bind
   media-ctl -d /dev/media0 -p | grep ov08x40
   ```
   On any kernel where psys fails to probe, do **not** unbind — use a persistent live USB so a
   real reboot is possible.

Then test both userspace paths and compare:

```sh
# the path this machine actually uses
gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert ! jpegenc \
  ! multifilesink location=/tmp/relay%02d.jpg
# the native libcamera path new in 26.04
gst-launch-1.0 -q libcamerasrc num-buffers=20 ! videoconvert ! jpegenc \
  ! multifilesink location=/tmp/lc%02d.jpg
```

The JPEGs also settle whether the 180° rotation still needs correcting, and whether it needs
correcting *differently* on the libcamera path.
