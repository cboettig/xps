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

### Audio output

Audio is PipeWire with WirePlumber. Kanshi runs `scripts/audio-default` on every
profile change, so the default output follows the displays: HDMI audio when a monitor
that can play sound is attached, the laptop speakers otherwise. To choose by hand,
right-click the Waybar volume module. That opens `scripts/audio-menu`, a fuzzel list of
the outputs with the current one marked. Picking one makes it the default and moves
anything already playing onto it, since streams pinned to a device do not follow the
default. The menu's last entry opens GNOME's Sound panel. Left-click mutes and scroll
sets the volume.

GNOME Settings refuses to start outside a GNOME session, so under Sway it has to be
launched as `XDG_CURRENT_DESKTOP=GNOME gnome-control-center sound`. The Sound panel works
there because it talks to PipeWire through its PulseAudio interface. From a terminal,
`wpctl status` lists the outputs and `wpctl set-default <id>` switches; the ids change
across reboots.

## Memory

8 GB is the binding constraint, mostly because of Chrome. Swap is zram (zstd, half of
RAM, priority 100) with `/swap.img` as overflow at priority -1:

- [etc/zram-generator.conf](etc/zram-generator.conf) → `/etc/systemd/zram-generator.conf`
  (needs `systemd-zram-generator`; remove `zram-config` if present)
- [etc/99-zram.conf](etc/99-zram.conf) → `/etc/sysctl.d/99-zram.conf`
  (`vm.swappiness=100`, `vm.page-cluster=0`)

Check with `swapon --show`.

## Suspend

On AC power the machine never suspends; on battery it suspends on lid close and, under
GNOME, after 15 minutes idle. Sway's swayidle only locks and blanks the screens, so
under Sway the only thing that ever suspends is systemd-logind reacting to the lid.

By default `HandleLidSwitchExternalPower` inherits `HandleLidSwitch=suspend`. A lid
closed with an external display attached counts as docked and is ignored, but logind
rechecks, so the machine suspends as soon as that display drops out or the dock is
unplugged, often long after the lid was closed. The fix is
[etc/logind-lid-ac.conf](etc/logind-lid-ac.conf):

```sh
sudo install -Dm644 etc/logind-lid-ac.conf /etc/systemd/logind.conf.d/50-lid-ac.conf
sudo systemctl reload systemd-logind
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager HandleLidSwitchExternalPower   # s "ignore"
```

The GNOME fallback session takes over the lid from logind, so it needs the matching
setting (stored in dconf, which the `~/.config` repository does not track):

```sh
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
```

GNOME's idle suspend on AC (`sleep-inactive-ac-type`) is already `'nothing'`.

## Disk health

A baseline to compare against later, from `sudo smartctl -x /dev/sda` and a long self-test
on 2026-11-14. Ubuntu 24.04's smartctl drive database predates this model, so most
attributes show as `Unknown_Attribute` until `sudo update-smart-drivedb` is run. The
names below are from the WD Blue/Green SSD entry in the current database.

| ID | Attribute | Raw | |
|---|---|---|---|
| 241 | Host writes (GiB) | 1299 | about 2% of the ~80 TB rated endurance |
| 242 | Host reads (GiB) | 1801 | |
| 233 / 234 | NAND writes TLC / SLC (GiB) | 1467 / 1716 | write amplification about 1.13 |
| 173 / 168 / 166 | P/E cycles average / max / min | 6 / 8 / 2 | |
| 169 / 170 | Bad blocks total / grown | 297 / 0 | the 297 are from the factory; grown is the one to watch |
| 171 / 172 | Program / erase failures | 0 / 0 | |
| 5, 187, 188, 199 | Reallocated, uncorrectable, timeouts, CRC | 0 | |
| 174 | Unexpected power loss | 3 | |
| 194 | Temperature | 28 °C (min 12, max 54) | |
| 9 | Power-on hours | 105 | counts only time awake, not wall-clock time |

Short and extended self-tests both passed, and the error log is empty. Without root,
UDisks reports the same data (it shows 241/242 in 32 MiB units):

```sh
gdbus call --system -d org.freedesktop.UDisks2 \
  -o /org/freedesktop/UDisks2/drives/$(busctl --system tree org.freedesktop.UDisks2 | grep -o 'WD_Green[^ ]*' | head -1) \
  -m org.freedesktop.UDisks2.Drive.Ata.SmartGetAttributes '{}'
```

A drive like this can still fail without warning, as the original did. Nothing on it
lives only here except the config, and that is in git.

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
