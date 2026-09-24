# GNOME desktop

Tweaks to the stock Ubuntu GNOME session, matching the old sway setup. The
theme switcher lives outside this repo at `~/.config/scripts/theme`.

- **Themes:** `theme nord|mocha|latte|default`, and `theme follow on` to track
  GNOME's Light/Dark setting. The script covers sway, waybar, foot, Ptyxis
  (writes `~/.local/share/org.gnome.Ptyxis/palettes/theme-*.palette` from the
  foot palette), GTK, and the shell (User Themes extension).
  - GTK4: `~/.config/gtk-4.0/gtk.css` must `@import` the theme's stylesheet,
    not symlink it. With a symlink, Nordic's window-button images can't be
    found, so the buttons disappear.
- **Top-bar monitor:** enable the `system-monitor@gnome-shell-extensions.gcampax.github.com`
  extension. It stays hidden unless `gnome-system-monitor` is installed.
- **No dock:** `gnome-extensions disable ubuntu-dock@ubuntu.com`. Auto-hide
  still shows the dock on an empty desktop.
