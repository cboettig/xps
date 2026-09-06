# Upgrading noble → resolute (24.04 → 26.04)

> **Done: 2026-09-06.** The upgrade succeeded and the camera works on
> `7.0.0-31-generic`, verified across a clean boot. It needed two fixes afterwards,
> neither anticipated by the plan below — see
> [What actually happened](#what-actually-happened) at the end.

Checklist for this machine specifically. The camera is the fragile part; see
[kernel.md](kernel.md) and [oem-stack.md](oem-stack.md) for why.

**Strategy:** upgrade with several bootable kernels in place, then test them from
the GRUB menu rather than betting the first reboot on 26.04's default kernel.
`GRUB_DEFAULT` names `7.0.0-30-generic`, which exists in resolute, so the first
post-upgrade boot should land on the known-good kernel.

## Before

Config we care about is snapshotted in [etc/](etc/) — restore from there if an
upgrade prompt clobbers something.

1. **Backups.** Confirmed present before starting.

2. **Release the holds.** `do-release-upgrade` will not proceed cleanly with
   held packages:

   ```sh
   sudo apt-mark unhold \
     linux-image-7.0.0-30-generic linux-modules-7.0.0-30-generic \
     linux-modules-ipu6-7.0.0-30-generic linux-modules-ipu7-7.0.0-30-generic \
     linux-modules-vision-7.0.0-30-generic
   ```

3. **Be fully current on noble first:**

   ```sh
   sudo apt update && sudo apt full-upgrade
   ```

4. **Record the starting point** so regressions are attributable:

   ```sh
   uname -r; dpkg -l | grep -c '^ii'; ls /boot/vmlinuz-*
   ```

## During

```sh
sudo do-release-upgrade
```

Three prompts matter:

| Prompt | Answer | Why |
|---|---|---|
| Config file changed — replace? (`/etc/default/grub`, `/etc/v4l2-relayd.d/default.conf`) | **keep current** (the default, `N`) | ours carry `GRUB_DEFAULT`, the flavour order, and `flip-mode=vhflip`. Replacing silently loses the camera rotation fix and the boot pin. |
| Disable third-party sources? | allow it | the upgrader re-points `dell.archive.canonical.com` at `resolute` itself; verify afterwards |
| Remove obsolete packages? | **No** | this is what would remove `linux-image-6.17.0-1032-oem`, which is *not* in resolute and is a fallback. Clean up later, deliberately. |

## After the upgrade, BEFORE rebooting

```sh
# Dell archive must be active and pointing at resolute -- the camera userspace
# (libcamhal / icamerasrc) exists nowhere else.
grep -r resolute /etc/apt/sources.list.d/ | grep dell

# Camera userspace still installed?
dpkg -l | grep -E 'libcamhal|gstreamer1.0-icamera|v4l2-relayd' | awk '{print $1,$2,$3}'

# Kernels still on disk? Want at least -30 plus one other.
ls /boot/vmlinuz-*

# Our config survived the prompts?
grep ^GRUB_DEFAULT /etc/default/grub
grep flip-mode /etc/v4l2-relayd.d/default.conf

# Add the separate-ABI fallback while still online (7.0.0-1013, not the -31 line)
sudo apt install linux-oem-26.04 linux-modules-ipu7-oem-26.04 linux-modules-vision-oem-26.04

# Camera modules for -30 under resolute's new package names
sudo apt install linux-main-modules-ipu7-7.0.0-30-generic \
                 linux-main-modules-vision-7.0.0-30-generic
sudo update-grub
```

## Testing kernels, in order

Reboot and pick each from the GRUB menu. The check is the same every time:

```sh
uname -r
journalctl -b -k | grep -E 'IPU psys probe done|psys device_register failed'
ls -l /dev/ipu7-psys0
gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=20 ! videoconvert ! jpegenc \
  ! multifilesink location=/tmp/f%02d.jpg
ls -l /tmp/f*.jpg | awk '{print $5}' | sort -u | wc -l    # must be > 1
```

1. ~~**`7.0.0-30-generic`** — the default, known-good on noble.~~ **Wrong.** On 26.04
   `v4l2loopback` is a separate module package that exists only for `-31`, so `-30` cannot
   run the camera at all. Go straight to `-31`.
2. **`7.0.0-31-generic`** — 26.04's default. Broken on noble
   ([LP #2166612](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612));
   the question is whether resolute's rebuilt psys fixes it. **Do not unbind the
   IPU7 device on this kernel** — it NULL-derefs and wedges shutdown.
3. **`7.0.0-1013-oem`** — separate ABI line, only if both above fail.

Whichever works, make it the default and re-apply holds:

```sh
sudo sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux <VERSION>"|' /etc/default/grub
sudo update-grub
```

## If it all goes wrong

`6.17.0-1032-oem` should still be installed and bootable (it is not in resolute,
so it will not have been updated, but the files remain). It is the last-resort
entry under *Advanced options*.

## Afterwards

- Update the kernel table in [README.md](README.md).
- Re-check [oem-stack.md](oem-stack.md): `oem-hwe-meta` / `oem-nantou-meta` /
  `wpa-hwe` are expected to go obsolete, and `oem-somerville-hypno-meta` should
  now depend on `linux-generic-hwe-26.04`.
- Confirm the `ov08x40-uf.json` diversion still holds:
  `dpkg -S /etc/camera/ipu75xa/sensors/ov08x40-uf.json`


## What actually happened

The upgrade itself was clean — `dpkg --audit` empty, no half-configured packages, all four
kernels intact, camera userspace upgraded to the 26.04 builds. It was interrupted at the
final "remove obsolete packages?" prompt (unrelated GUI freeze from launching Startup Disk
Creator mid-upgrade); `apt -f install` confirmed nothing was left broken.

**The good news:** [LP #2166612](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612)
is fixed on 26.04. `7.0.0-31-generic` reports `IPU psys probe done.` with resolute's rebuilt
psys module. That was the question this whole exercise existed to answer.

**Three things the plan got wrong:**

1. **`7.0.0-30-generic` is not a fallback on 26.04.** `v4l2loopback` became its own module
   package and only exists for `-31`. Booting `-30` gives `Failed to find module
   'v4l2loopback'` and `v4l2-relayd` fails with `start-limit-hit`. The whole "land on the
   known-good kernel first" strategy was built on this and was backwards. `7.0.0-1013-oem`
   has the same gap.

2. **Stale noble module packages shadow resolute's.** Both sets stay installed for `-31`;
   `depmod` prefers `ubuntu/` over `ubuntu/dkms/`, so `modprobe` picks noble builds that
   cannot load. Fixed by [fix.sh](fix.sh). Details in
   [kernel.md](kernel.md#two-things-the-2604-upgrade-broke).

3. **`v4l2-relayd` does not stream after boot.** It reports `active` while sitting idle at
   0% CPU holding no device, and `/dev/video0` returns a single stale frame. Fixed by
   [fix-relayd-kick.sh](fix-relayd-kick.sh), which kicks relayd once from a oneshot service
   after the device exists. The mechanism is not fully understood — see
   [kernel.md](kernel.md#v4l2-relayd-does-not-stream-after-boot).

**Conffile handling was not as promised.** The plan said to answer "keep current" at the
config prompts. `/etc/default/grub` and `zz-flavour-order.cfg` did survive — but
`/etc/v4l2-relayd.d/default.conf` was **replaced outright**, silently dropping
`flip-mode=vhflip`. Restored from [etc/](etc/). Snapshotting those files beforehand is the
single most useful thing in this checklist; do it again next time.

**Sequence that worked**, for reference:

```sh
sudo ./prep.sh              # restore camera config, add oem-26.04 fallback, update-grub
sudo ./next.sh              # GRUB_DEFAULT=0 -> newest generic, reboot into -31
sudo ./fix.sh               # purge shadowing noble modules, depmod, initramfs, reboot
sudo ./fix-relayd-kick.sh   # oneshot service that kicks relayd once after boot
```
