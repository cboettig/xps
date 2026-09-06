# Upgrading the factory 24.04 image to 26.04

Done on this machine 2026-09-06. The camera works on 26.04 and the upgrade is worth doing:
26.04 fixes the `7.0.0-31` psys regression that breaks the camera on 24.04
([LP #2166612](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-7.0/+bug/2166612)).

For a clean 26.04 install instead, see [setup.md](setup.md).

## Before

Dell ships this machine with `Prompt=never` in `/etc/update-manager/release-upgrades`; set it
to `lts` for the upgrade to be offered at all.

1. **Have a backup.** A failed release upgrade can require a reinstall.

2. **Snapshot the hand-edited config.** The upgrade replaces
   `/etc/v4l2-relayd.d/default.conf` **without prompting**, silently dropping the camera
   rotation fix. Copies live in [etc/](etc/); confirm they match your system first:

   ```sh
   diff etc/v4l2-relayd-default.conf /etc/v4l2-relayd.d/default.conf
   ```

3. **Release any `apt-mark hold`s** — `do-release-upgrade` will not proceed cleanly with
   held packages. `apt-mark showhold` lists them.

4. **Be current on 24.04 first:** `sudo apt update && sudo apt full-upgrade`

## During

```sh
sudo do-release-upgrade
```

| Prompt | Answer |
|---|---|
| Disable third-party sources? | Allow. The upgrader re-points `dell.archive.canonical.com` at `resolute` itself. |
| Remove obsolete packages? | **No.** This would remove the OEM 6.17 kernel's camera modules while leaving the kernel bootable — losing a fallback. Clean up later, deliberately. |

## After, before rebooting

```sh
cd xps/xps14
sudo ./setup.sh
```

That handles everything the upgrade leaves wrong:

- **Restores `flip-mode=vhflip`**, which the upgrade dropped.
- **Purges the stale 24.04-built module packages.** The upgrade leaves both sets installed
  for the same kernel, and `depmod` searches `ubuntu/` before `ubuntu/dkms/`, so `modprobe`
  picks the 24.04 builds. They cannot load against a 26.04 kernel — identical `vermagic`,
  different symbol CRCs — so `intel_cvs` never loads, `ov08x40` never binds, and the media
  graph has no sensor.
- **Sets `GRUB_DEFAULT=0`** so you boot the newest generic kernel.
- **Installs the relayd kick service.**

Then reboot and re-run `sudo ./setup.sh` to confirm.

## Kernel selection after the upgrade

**Boot the newest generic kernel (`7.0.0-31` or later).** Do not fall back to
`7.0.0-30-generic`, even though it was the working kernel on 24.04: on 26.04 `v4l2loopback`
became a separate module package built only for `-31` and later, so `-30` gives
`Failed to find module 'v4l2loopback'` and `v4l2-relayd` fails with `start-limit-hit`.
`7.0.0-1013-oem` has the same gap.

If you need a last-resort fallback, the factory `6.17.0-1032-oem` kernel remains installed
and bootable under *Advanced options* — it is not in the 26.04 archive, so it will not be
updated, but the files stay unless you autoremove them.

## Afterwards

`apt autoremove` will want to remove ~175 packages including the OEM 6.17 camera modules.
Decide deliberately whether you still want that fallback before running it.
