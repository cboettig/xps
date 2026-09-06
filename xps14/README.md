# XPS 14

Configuration notes for the XPS 14, as distinct from the XPS 13 notes in the repo root.

## This machine

| | |
|---|---|
| Model | Dell XPS 14 **DA14260** |
| System SKU | 0DB9 |
| Motherboard | 0H2HX9 |
| CPU | Intel Core Ultra X7 358H |
| BIOS | 1.8.2 (2026-05-22) |
| OS | Ubuntu 26.04.1 LTS (resolute) — upgraded from 24.04 on 2026-09-06 |
| Release upgrades | `Prompt=lts` — changed locally from the `never` Dell ships |
| Kernel | **7.0.0-31-generic** (GRUB default via `GRUB_DEFAULT=0`) |
| Camera | working — see [camera.md](camera.md) |

Identifying info came from:

```sh
cat /sys/class/dmi/id/{sys_vendor,product_name,product_sku,board_name,bios_version,bios_date}
uname -r
```

Notes are specific to this hardware revision and kernel/OEM stack; the camera stack in
particular (Intel IPU7) differs from the IPU6 generation in the XPS 13 notes.

## Contents

- [camera.md](camera.md) — built-in camera is upside down, and the fix
- [kernel.md](kernel.md) — which kernel boots and why, the module packages the camera needs
  on generic, and the `7.0.0-31` regression
- [oem-stack.md](oem-stack.md) — what the Dell/OEM packages actually do, what is safe to
  remove, and the Ubuntu 26.04 upgrade
- [live-test.sh](live-test.sh) — self-contained camera test for a live USB (kept for
  future releases; the 26.04 upgrade was done in place instead)
- [upgrade-26.04.md](upgrade-26.04.md) — the noble → resolute upgrade: checklist, what
  actually broke, and the two fixes it needed
- [etc/](etc/) — copies of the hand-edited config files, for restoring after an upgrade
  overwrites them (the 26.04 upgrade replaced the camera config without prompting)
- `prep.sh`, `next.sh`, `fix.sh`, `fix-relayd-kick.sh` — the upgrade steps, in order; see
  [upgrade-26.04.md](upgrade-26.04.md#what-actually-happened)

## Testing the camera from a live USB

No notes or network access to this repo needed beyond one download:

```sh
curl -O https://raw.githubusercontent.com/cboettig/xps/master/xps14/live-test.sh
sudo bash live-test.sh
```

It adds the Dell archive, installs the kernel modules and camera userspace for
whatever kernel the live session is running, captures frames, and prints a verdict.
It never unbinds the IPU7 device — that oopses on `7.0.0-31-generic`.

Results land in `/root/camera-live-test.log` and `/root/frames-*/`, both in the live
session's RAM overlay — copy them to the USB stick before rebooting.
