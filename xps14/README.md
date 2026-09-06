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

## Getting the camera working

- **Fresh 26.04 install** → [setup.md](setup.md), then `sudo ./setup.sh`
- **Factory 24.04 image** → [upgrade.md](upgrade.md)
- **Something broke** → [camera.md](camera.md#diagnosing), or just re-run `sudo ./setup.sh`

## Contents

| | |
|---|---|
| [setup.md](setup.md) | fresh install on 26.04 |
| [upgrade.md](upgrade.md) | factory 24.04 → 26.04 |
| [setup.sh](setup.sh) | idempotent installer; also verifies a working system |
| [camera.md](camera.md) | how the camera stack fits together, verification, debugging |
| [kernel.md](kernel.md) | boot selection, module packaging, the 24.04 `7.0.0-31` regression |
| [oem-stack.md](oem-stack.md) | Dell/OEM packages: what they do, what is removable |
| [etc/](etc/) | the config files `setup.sh` installs |
| [bug/](bug/) | the report filed as LP #2166612 |
