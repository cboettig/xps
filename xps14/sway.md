# Sway desktop

The XPS 14 runs the same Sway desktop as the XPS 13, from the shared
[cboettig/config](https://github.com/cboettig/config) repo checked out as `~/.config`.
GNOME is still installed (see [gnome.md](gnome.md)). Pick the session at the GDM login.

## Machine-specific settings

The shared config picks per-machine settings by the panel's identity, not the hostname:

- **kanshi** (`~/.config/kanshi/config`): the XPS 13 profiles name its panel
  (`Sharp Corporation 0x1421 Unknown`) and come first. The generic `eDP-1` twins after
  them are the XPS 14's. The panel here is `LG Display 0x07C8`, 1920x1200@120 Hz, at
  scale 1.
- **`~/.config/scripts/panel.sh`** does the same lookup for `present` and
  `display-rescue`.

## XPS 13 workarounds turned off here

| Workaround | Why the XPS 13 needs it | XPS 14 |
|---|---|---|
| `WLR_NO_HARDWARE_CURSORS=1` (`environment.d/wlroots.conf`) | Broadwell cursor plane freezes Sway on resume | Overridden by an untracked `~/.config/environment.d/zz-xps14-local.conf` that sets it to `0`. Takes effect at the next login. |
| U3417W pinned to 3440x1440@50Hz | i915 FIFO underruns at 60 Hz | `docked_uw` leaves the mode unpinned, so the monitor runs at its preferred 60 Hz |

## kanshi on 26.04

kanshi 1.7+ refuses to load a file that has two `output "*"` lines in one profile:

```
directive 'output': duplicate output '*' in profile
failed to parse config file
```

It then exits, so none of the profiles apply: no dock switching, no projector mirroring,
and no `audio-default` hooks. The two-unknown-externals fallback is commented out for this
reason. To check kanshi is alive:

```sh
pgrep -a kanshi
journalctl --user -t kanshi -b | tail
```

## Unaffected by the desktop

- **Suspend:** the pre-sleep unit in [suspend.md](suspend.md) runs under systemd.
  `swayidle` also locks before sleep.
- **YubiKey:** only `sudo` uses the key. swaylock authenticates through
  `/etc/pam.d/swaylock` → `login`, so it still asks for the password, the same as GDM. See
  [yubikey.md](yubikey.md).
