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
| OS | Ubuntu 24.04.4 LTS |
| Kernel | 6.17.0-1032-oem (OEM, GRUB default) / 7.0.0-30-generic (both work) |

Identifying info came from:

```sh
cat /sys/class/dmi/id/{sys_vendor,product_name,product_sku,board_name,bios_version,bios_date}
uname -r
```

Notes are specific to this hardware revision and kernel/OEM stack; the camera stack in
particular (Intel IPU7) differs from the IPU6 generation in the XPS 13 notes.

## Contents

- [camera.md](camera.md) — built-in camera is upside down
- [kernel.md](kernel.md) — OEM vs generic kernel, the module packages the camera needs on generic, and notes on 26.04
