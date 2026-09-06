# Kernels and module packaging

Reference for why kernel choice matters on this machine. Setup is automated in
[setup.sh](setup.sh); the camera stack itself is in [camera.md](camera.md).

## Which kernel boots

Two mechanisms, easy to confuse.

**Flavour order.** `oem-somerville-hypno-meta` installs a GRUB drop-in — a symlink into its
own data directory — setting `GRUB_FLAVOUR_ORDER=oem`:

```console
$ cat /etc/default/grub.d/oem-flavour.cfg
GRUB_FLAVOUR_ORDER=oem
```

`/usr/lib/grub/grub-sort-version` treats that as a flavour priority list and sorts matching
flavours ahead of everything else **before** any version comparison — so an OEM kernel wins
the default slot over a much newer generic one. It is not a version or `saved_entry` effect.

That file is package-owned and gets rewritten on update. `grub-mkconfig` sources
`/etc/default/grub.d/*.cfg` in glob order, so a later-sorting drop-in wins:

```console
$ cat /etc/default/grub.d/zz-flavour-order.cfg
GRUB_FLAVOUR_ORDER=generic
```

**Version.** `GRUB_DEFAULT=0` plus the above means "newest generic". To pin one specific
kernel instead, `GRUB_DEFAULT` can name a menu entry, but the string must match verbatim —
derive it rather than typing it:

```sh
grep -oP "^\s*menuentry '\KUbuntu, with Linux [0-9.]+-generic(?=')" /boot/grub/grub.cfg
```

Two things that look like evidence but are not: `/boot/vmlinuz` symlinks to the highest
version but GRUB does not consult them, and `grub-editenv list` is empty.

## Module packages

The camera needs five module packages beyond the kernel itself. On 26.04:

| Package (`-generic-hwe-26.04`) | Supplies | Without it |
|---|---|---|
| `linux-modules-vision-*` | `intel_cvs` | sensor's I²C device never created; no sensor in the media graph |
| `linux-modules-ipu7-*` | `intel-ipu7-psys` | no `/dev/ipu7-psys0`; HAL has no processing device |
| `linux-modules-ipu6-*` | `ov08x40` | sensor driver missing |
| `linux-modules-usbio-*` | USBIO GPIO/I²C | GPIO chip for the sensor power rails |
| `linux-modules-v4l2loopback-*` | `v4l2loopback` | no `/dev/video0`; `v4l2-relayd` fails `start-limit-hit` |

`intel_cvs` is the Intel Vision Sensing Controller; it satisfies the ACPI chain (`INTC10E1`)
that `OVTI08F4:00` hangs off. It is not upstreamed — other distros build it from
[intel/vision-drivers](https://github.com/intel/vision-drivers) by hand. On Ubuntu it is a
package.

These are versioned separately from the kernel and **an update can leave one behind**. That
is not hypothetical: it is how the camera has broken twice here. Re-run `sudo ./setup.sh`
after any kernel update.

### Two packaging traps

**Matching `vermagic` does not mean a module will load.** `CONFIG_MODVERSIONS` is on, so
symbol CRCs must match too. Modules built for a different build of the *same* kernel version
are rejected with `disagrees about version of symbol module_layout`. This is why modules
cannot be borrowed across releases.

**`depmod` searches `ubuntu/` before `ubuntu/dkms/`.** If two packages provide the same
module in those two locations, the `ubuntu/` copy wins regardless of which is correct. A
release upgrade leaves both installed — see [upgrade.md](upgrade.md). Check with:

```sh
modprobe -n -v intel_cvs        # want a path under ubuntu/dkms/ on 26.04
```

## Module load order

`int3472-discrete` races the USBIO GPIO controller at boot:

```
int3472-discrete INT3472:00: cannot find GPIO chip INTC10E2:00, deferring
```

A softdep forces the ordering (`/etc/modprobe.d/ipu7-order.conf`, installed by `setup.sh`):

```
softdep intel_ipu7 pre: usbio gpio_usbio i2c_usbio intel_cvs intel_skl_int3472_discrete
```

It must be in every kernel's initramfs — use `update-initramfs -u -k all`, and verify with
`lsinitramfs /boot/initrd.img-<version> | grep ipu7-order`.

One warning persists on a working system and is benign here:

```
int3472-discrete INT3472:00: GPIO type 0x02 unknown; the sensor may not work
```

GPIO type 0x02 is a strobe / IR-flood line used for face authentication. Mainline support is
[in flight upstream](https://lwn.net/Articles/1065085/). The main camera works regardless.

## The 7.0.0-31 regression (24.04 only)

On Ubuntu 24.04, `7.0.0-31-generic` cannot probe the IPU7 processing unit:

```
bus_add_device: cannot add device 'ipu7-psys0' to unregistered bus 'intel-ipu7-psys'
intel_ipu7_psys.psys ...: probe with driver intel_ipu7_psys.psys failed with error -22
```

The in-tree `intel_ipu7` core changed between `-30` and `-31` while the out-of-tree
`intel_ipu7_psys` did not, so the auxiliary device is probed before the psys bus is
registered.

Filed as [LP #2166612](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612).

**Fixed on 26.04**, which ships a rebuilt psys module (srcversion `0DB161AA0DFA3D4C864A551`
against 24.04's `32D18897D60F8FF10DA6F05`) for the same `7.0.0-31` ABI. Upgrading is the fix;
on 24.04 the workaround is to stay on `7.0.0-30-generic`.

> **Do not unbind the IPU7 PCI device on an affected kernel.** It NULL-derefs in
> `ipu7_pci_remove`, leaves the task with irqs disabled, and wedges shutdown — recovery is
> SysRq REISUB. Reboot into a working kernel instead of trying to re-probe.
