# XPS 13 9343

Configuration notes for the 2015 XPS 13 (Broadwell), still in daily use. The older notes
in the repo root ([graphics.md](../graphics.md)) date from when this machine was new.

## This machine

| | |
|---|---|
| Model | Dell XPS 13 **9343** |
| Motherboard | 0310JH |
| CPU / GPU | Intel Core i7-5500U, HD Graphics 5500 (Broadwell, `i915`) |
| Memory | 8 GB, soldered |
| Panel | Sharp `0x1421`, 3200x1800 only |
| Disk | WD Green M.2 SATA SSD, 240 GB (replaced ~2025 after the original died) |
| BIOS | A20 (2019-06-06) |
| OS | Ubuntu 24.04 LTS (noble), staying put — see [Release](#release) |
| Kernel | 7.0 HWE (`linux-generic-hwe-24.04`) |
| Desktop | Sway, with GNOME kept as a fallback session |

```sh
cat /sys/class/dmi/id/{product_name,board_name,bios_version,bios_date}
```

## Release

This machine stays on 24.04 rather than upgrading to 26.04. Standard support for noble
runs to mid-2029, and the HWE kernel already brings 26.04's kernel. The upgrade would
replace the whole Sway stack (sway 1.9 → 1.11, wlroots 0.17 → 0.19, waybar 0.9 → 0.14)
that the Broadwell workarounds in [display.md](display.md) were tested against. The
plan at end of life is a clean install of something lighter, not an in-place upgrade,
so the upgrade prompt is turned off:

```sh
sudo sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
```

## Desktop

Sway, Waybar, kanshi, foot, fuzzel and mako, with a theme switcher, in a separate
dotfiles repository checked out as `~/.config`. The same repository serves the
[XPS 14](../xps14/), which runs GNOME; the parts that differ per machine are the kanshi
profiles (paired by panel identity) and `scripts/panel.sh`.

Sway was chosen over GNOME on this machine for memory and GPU headroom. Two
environment settings in `~/.config/environment.d/` matter:

- `wlroots.conf`: `WLR_NO_HARDWARE_CURSORS=1`, the fix for Sway freezing on resume
  ([display.md](display.md#sway-freezes-on-resume)). Copy in [etc/](etc/wlroots.conf).
- `ssh-agent.conf`: points `SSH_AUTH_SOCK` at gcr's agent, with `gpg-agent-ssh.socket`
  masked in the user systemd, because gpg-agent cannot hold FIDO2 `sk-` keys.

## Memory

8 GB is the binding constraint, mostly because of Chrome. Swap is zram (zstd, half of
RAM, priority 100) with `/swap.img` as overflow at priority -1:

- [etc/zram-generator.conf](etc/zram-generator.conf) → `/etc/systemd/zram-generator.conf`
  (needs `systemd-zram-generator`; remove `zram-config` if present)
- [etc/99-zram.conf](etc/99-zram.conf) → `/etc/sysctl.d/99-zram.conf`
  (`vm.swappiness=100`, `vm.page-cluster=0`)

Check with `swapon --show`.

## Other system changes

- Kernel parameters `i915.enable_psr=0 i915.enable_dc=0` in `/etc/default/grub`; see
  [display.md](display.md#kernel-parameters).
- [etc/50-zsa.rules](etc/50-zsa.rules) → `/etc/udev/rules.d/`, so Keymapp and Wally can
  flash a ZSA keyboard without root. The user must be in `plugdev`.
- User in the `video` group so `brightnessctl` works without root.

## Contents

| | |
|---|---|
| [display.md](display.md) | kernel parameters, Sway freeze on resume, external monitor dropouts |
| [etc/](etc/) | copies of the hand-edited system and session config |
