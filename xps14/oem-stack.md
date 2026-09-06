# The Dell/OEM package stack

Reference. What Dell actually provides, and what is safe to remove.

## Two archives, and what each supplies

| Archive | Components | Supplies |
|---|---|---|
| `dell.archive.canonical.com` | `somerville`, `somerville-hypno` | camera userspace (`libcamhal*`, `gstreamer1.0-icamera`, `libia-*`), `oem-somerville-*-meta` |
| `oem.archive.canonical.com` | `hwe`, `nantou` | `oem-hwe-meta`, `oem-nantou-meta`, `wpa-hwe` (24.04 only; no 26.04 successors) |

`hypno` is Dell's codename for this machine; `somerville` is the program.

**Dell ships no kernel packages at all.** Every kernel and kernel module, OEM flavour
included, comes from `archive.ubuntu.com` — `linux-oem-*` is an Ubuntu package. Only the
camera *userspace* is Dell's.

The converse matters more: **the Dell userspace is not optional.** `icamerasrc` links against
`libcamhal.so.0`, and Ubuntu's own `libcamera` has no IPU7 pipeline handler at the version
shipped here. There is no non-Dell path for this camera, so choosing a kernel flavour never
frees the machine from `dell.archive`. The two are independent axes.

## What the metapackages contain

Mostly nothing — dependency shims plus a few config files:

| Package | Real payload |
|---|---|
| `oem-somerville-hypno-meta` | `oem-flavour.cfg` (GRUB), `intel-ipu7-firmware.conf`, apt source |
| `oem-somerville-meta` | nothing |
| `oem-somerville-factory-*-meta` | nothing — factory-line scaffolding |
| `oem-hwe-meta` | `/etc/apt/preferences.d/20-hwe` |
| `wpa-hwe` | `/etc/apt/preferences.d/30-wpa-hwe` |

`oem-somerville-hypno-meta` is worth keeping: on 26.04 it depends on
`linux-generic-hwe-26.04` and recommends the five camera module packages, so it is the
vendor's own definition of a working configuration.

It also still ships `GRUB_FLAVOUR_ORDER=oem`, which is why the
`zz-flavour-order.cfg` override in [kernel.md](kernel.md#which-kernel-boots) is needed.

### A stale diversion

`oem-somerville-hypno-meta` holds a dpkg diversion on the sensor tuning file:

```console
$ dpkg -S /etc/camera/ipu75xa/sensors/ov08x40-uf.json
diversion by oem-somerville-hypno-meta from: /etc/camera/ipu75xa/sensors/ov08x40-uf.json
```

On 24.04 it substituted a Dell-tuned version. The 26.04 package no longer ships a
replacement, so the diversion remains registered but the content now matches libcamhal's own.
Harmless; noted so it isn't mistaken for a problem.

## What is safe to remove

**Inert factory scaffolding** — no files, nothing depends on them:

```sh
sudo apt purge oem-somerville-factory-hypno-meta oem-somerville-factory-meta
```

**Stale kernel config remnants:**

```sh
dpkg -l | awk '$1=="rc"{print $2}' | grep '^linux-' | xargs -r sudo dpkg --purge
```

**Keep:** `oem-somerville-hypno-meta`, `oem-somerville-meta`, and the whole
`libcamhal*` / `libia-*` / `gstreamer1.0-icamera` set — that is the camera.

**Decide deliberately:** `apt autoremove` after the 26.04 upgrade wants to remove ~175
packages including the OEM 6.17 kernel's camera modules. The kernel stays bootable but
loses its camera, costing a fallback.

`oem-hwe-meta`, `oem-nantou-meta` and `wpa-hwe` have no 26.04 successors and go obsolete on
upgrade. `oem-hwe-meta`'s pin is what keeps the rest of the HWE archive *out*, and `wpa-hwe`
re-promotes `wpasupplicant` from it — so on 24.04, don't remove one without the other.
