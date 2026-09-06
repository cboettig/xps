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
| OS | Ubuntu 24.04.4 LTS (noble) — shipped this way by Dell |
| Release upgrades | `Prompt=lts` — changed locally from the `never` Dell ships, so 26.04 is offered |
| Kernel | **7.0.0-30-generic** (GRUB default, held) |
| Fallback kernel | 6.17.0-1032-oem (works; keep) |
| Known-bad kernel | 7.0.0-31-generic (camera dead — see [kernel.md](kernel.md)) |

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
