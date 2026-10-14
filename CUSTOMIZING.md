# Customizing

Your changes go in files the repo does not track. Updates never overwrite
them, and `git status` stays clean. `install.sh` creates a commented starter
for each one the first time and never touches it again.

Almost all of them are in one folder:

```
~/.config/archdots/
  hypr/<module>.lua      Hyprland, loaded after the matching default in
                         ~/.config/hypr/config/<module>.lua
  local/zshrc            zsh
  local/alacritty.toml   the terminal
```

GTK only reads its own folders, so those two files live there:
`~/.config/gtk-4.0/user.css` and `~/.config/gtk-3.0/gtk.css`.

## To change X, edit Y

| To change | Edit | Example |
|---|---|---|
| Monitor layout, resolution, scale | `hypr/monitor.lua` (install.sh writes a first guess) | `hl.monitor({ output = "DP-1", mode = "2560x1440@165", position = "1920x0", scale = 1.0 })` |
| Which monitor a workspace opens on | `hypr/monitor.lua` | `hl.workspace_rule({ workspace = "3", monitor = "DP-1" })` |
| Add a keybind | `hypr/keybind.lua` | `hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"), { desc = "Launch: GIMP" })` |
| Change or remove a default keybind | `hypr/keybind.lua`, through the helper (below) | `bind.rebind("SUPER + E", hl.dsp.exec_cmd("nautilus"), { desc = "Launch: File manager" })` |
| Terminal, browser, file manager | `hypr/keybind.lua`: rebind their keys (SUPER + RETURN, B, E) | as above |
| Keyboard layout, touchpad | `hypr/input.lua` | `hl.config({ input = { kb_layout = "de" } })` |
| A device's own settings | `hypr/input.lua`, an `hl.device` block keyed by the name in `hyprctl devices` | |
| Gaps, borders, rounding | `hypr/theme.lua` | `hl.config({ general = { gaps_out = 10 } })` |
| Animations | `hypr/animation.lua` | |
| Window rules | `hypr/rules.lua` | `hl.window_rule({ ... })` |
| Apps started at login | `hypr/autorun.lua` | `hl.on("hyprland.start", function() hl.exec_cmd("discord") end)` |
| Environment variables | `hypr/environment.lua` | `hl.env("XCURSOR_SIZE", "32")` |
| Which GPU Hyprland renders on | `~/.config/uwsm/env-hyprland.d/10-gpu.sh` (written by install.sh; uwsm reads it before Hyprland starts, so it cannot be Lua) | `export AQ_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0"` |
| Aliases, prompt, PATH, plugin settings | `local/zshrc` | `alias ll="eza -l"` |
| Terminal font, size, opacity, padding | `local/alacritty.toml` | `[font]` `size = 14.0` |
| GTK 4 / libadwaita apps | `~/.config/gtk-4.0/user.css` | |
| GTK 3 apps | `~/.config/gtk-3.0/gtk.css` | |
| Wallpaper and colours | the wallpaper picker (SUPER + W); colours follow the wallpaper. Shift+Enter sets it for one screen | |
| Light or dark colours, colour scheme | `theme.mode`, `theme.backend` in `settings.json`, or the launcher's `>` actions | |
| Bar contents, per screen | `bar.*` and `bar.monitors` in `settings.json` | `"monitors": {"HDMI-A-1": {"showCpu": false}}` |
| Stay awake (no dim, lock or suspend) | SUPER + SHIFT + I toggles it | |

Not yet: idle timeouts (they are in the tracked `~/.config/hypr/hypridle.conf`
for now). They come with the settings app (TODO.md, phase 5).

## The shell: `settings.json`

The shell (bar, panels, wallpaper, notifications, lock screen) reads
`~/.config/archdots/settings.json`, and edits apply as soon as you save. Only
the keys you set matter; everything else keeps its default. The file is
created by the shell itself the first time it changes a setting (pinning an
app, switching light mode); unknown keys and your own formatting are kept.

Every key, with its default:

```json
{
  "bar": {
    "showMedia": true,
    "showCpu": true,
    "showBattery": true,
    "clockFormat": "hh:mm AP",
    "emptyTitle": "Chit",
    "titleChars": 20,
    "mediaChars": 28,
    "monitors": {},
    "excluded": []
  },
  "launcher": {
    "favourites": [],
    "hidden": [],
    "terminal": "alacritty",
    "searchUrl": "https://www.google.com/search?q=%s"
  },
  "wallpaper": {
    "directory": "~/Pictures/wallpapers",
    "cycleMinutes": 0,
    "transitionMs": 700
  },
  "theme": {
    "mode": "dark",
    "backend": "wal"
  },
  "battery": {
    "lowPercent": 20,
    "criticalPercent": 10,
    "actionPercent": 5,
    "criticalAction": "suspend"
  },
  "toasts": {
    "charging": true,
    "locks": true,
    "keyboardLayout": true,
    "audioDevice": true,
    "vpn": true,
    "nowPlaying": false,
    "dnd": true
  },
  "lock": {
    "enabled": false,
    "pamConfig": "login"
  },
  "audio": {
    "scrollStep": 5,
    "maxVolume": 2.0
  }
}
```

| Key | What it does |
|---|---|
| `bar.clockFormat` | [Qt's date format](https://doc.qt.io/qt-6/qml-qtqml-qt.html#formatDateTime-method): `HH:mm` for 24-hour, add `:ss` for seconds |
| `bar.monitors` | any `bar` key per screen: `{"HDMI-A-1": {"showCpu": false}}` |
| `bar.excluded` | screens with no bar: `["DP-2"]` |
| `launcher.favourites` / `hidden` | desktop entry ids; easier with Ctrl+P / Ctrl+H in the launcher |
| `wallpaper.cycleMinutes` | switch to another wallpaper from the folder every N minutes; 0 is off |
| `theme.mode` | `light` or `dark` palette from the wallpaper (the launcher's `>` has it too) |
| `theme.backend` | pywal16's colour backend: `wal`, `colorthief`, `colorz`, `haishoku`, … |
| `battery.criticalAction` | at `actionPercent`, after a 30 s countdown you can cancel: `suspend`, `hibernate`, `poweroff` or `none` |
| `toasts.*` | which events pop up a small message |
| `lock.enabled` | use the shell's lock screen instead of hyprlock (hyprlock stays the fallback). Try `qs -c archdots ipc call lock preview` first |
| `audio.maxVolume` | 1.0 is 100%; the default allows boosting to 200% |

To change one from a script: `qs -c archdots ipc call settings set bar.showCpu false`.

## Hyprland overrides

Each file in `~/.config/archdots/hypr/` is plain Lua with the same `hl` API as
the defaults, run after them. Name the file after the default module it
changes: `monitor`, `keybind`, `input`, `theme`, `animation`, `rules`,
`autorun` or `environment`.

**Setting something again wins** for settings, monitors and rules: the later
call is applied last.

**Keybinds are the exception.** Binding a combo that is already bound adds a
second bind, and both actions fire. To change or delete a default, use the
helper, which unbinds first:

```lua
-- ~/.config/archdots/hypr/keybind.lua
local bind = require("config.helpers.bind")

bind.rebind("SUPER + B", hl.dsp.exec_cmd("firefox"), { desc = "Launch: Browser" })
bind.remove("SUPER + F")
```

Give every bind a `desc` (`"Group: Label"`). The cheatsheet (SUPER + /) can
only show what a bind does through it.

**A broken file does not take the session down.** You get a critical
notification naming the file and line, and a line in `~/.cache/hypr-custom.log`;
everything else still loads. Check before reloading:

```bash
luac -p ~/.config/archdots/hypr/*.lua && hyprctl reload
```

`~/.config/hypr/config/custom/` is the old location for these files. It is
still loaded, before `~/.config/archdots/hypr/`, so a machine set up earlier
keeps working. To move, copy each file across and delete the old one.

## What not to edit

- **Tracked files** in the repo (`home/` and everything under it). An update
  would conflict with your change or undo it. Override them instead.
- **Generated files.** Anything that starts with `GENERATED by pywal16` is
  rewritten on every wallpaper change: `~/.cache/wal/*`,
  `~/.config/gtk-4.0/colors.css` and the `colors.css` files in
  `~/.themes/archdots/`. Change the template it names in
  `~/.config/wal/templates/` instead (that one is tracked, so it is a change
  to the dots themselves).
