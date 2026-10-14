# archdots shell (Quickshell)

The desktop shell: the bar, the wallpaper, every panel, the notification
daemon, the OSD, the polkit agent and (opt-in) the lock screen. Started at
login by `hypr/config/autorun.lua` (`shell.restart()` in
`hypr/config/helpers/shell.lua`).

```
shell.qml        entry point: what is on screen, and the IPC targets
config/          Config (settings.json over defaults), Colours (pywal16)
services/        state, no UI: Audio, Battery, Brightness, CpuTemp, Displays,
                 Events, Hypr, Idle, IdleTimers, Media, Notifs, Panels, Power,
                 PowerProfile, SettingsState, Theme, UsageCounts
widgets/         shared pieces: Panel, SearchPanel, ListPanel, ListRow,
                 CardMenu, Island, BarText, Hot, Toggle, Slider, InfoRow, …
modules/         one folder per surface: bar, launcher, clipboard, emoji,
                 calendar, battery, control, notifications, osd, powermenu,
                 screenshot, keybinds, wallpaper, polkit, lock, settings
settings.qml     the settings app on its own (qs -p …/settings.qml)
```

Imports go through Quickshell's `qs.` module paths (`import qs.config`).
Singletons are files with `pragma Singleton`.

## Running it

```bash
qs -c archdots                                       # stowed as ~/.config/quickshell/archdots
qs -p ~/archdots/home/.config/quickshell/archdots    # straight from a clone
qs kill -c archdots                                  # stop it
```

## IPC

`qs -c archdots ipc show` lists every target. The main ones:

```bash
qs -c archdots ipc call panel toggle launcher     # any panel: services/Panels.qml
qs -c archdots ipc call launcher open "@"         # open prefilled (modes: ? = / @ ! >)
qs -c archdots ipc call control open audio        # a control-centre tab
qs -c archdots ipc call brightness up             # also down, set <percent>
qs -c archdots ipc call wallpaper set <path>      # also next, random, mode light|dark
qs -c archdots ipc call notifications toast "Title" "Body"
qs -c archdots ipc call settings set bar.showCpu false
qs -c archdots ipc call settings open displays    # the settings app ('' = last page)
qs -c archdots ipc call displays revert           # also keep, refresh
qs -c archdots ipc call lock preview              # the lock screen, without locking
qs -c archdots ipc call shell reload
```

`show` and `hide` cannot be function names: `qs ipc call x show` parses
`show` as the ipc subcommand of that name.

## Settings

`config/Config.qml` declares every setting with its default;
`~/.config/archdots/settings.json` overrides any of them, and edits to it apply
live. Write with `Config.set("bar.showCpu", false)`, never `writeAdapter()`:
on quickshell 0.3.2 that rewrites the whole file from the declared properties,
dropping keys it does not know and writing every default. `set()` changes only
the one key and leaves an unparsable file alone. User docs: CUSTOMIZING.md.

## Testing without replacing the running shell

`qs -p <path>` runs a second copy next to whatever is running. Give it its own
state with a scratch `HOME` **and** `XDG_CACHE_HOME`, `XDG_STATE_HOME`,
`XDG_DATA_HOME` (tools such as cliphist and pywal16 follow those, not `HOME`):

```bash
H=/tmp/qshome
HOME=$H XDG_CACHE_HOME=$H/.cache XDG_STATE_HOME=$H/.local/state \
    XDG_DATA_HOME=$H/.local/share qs -p home/.config/quickshell/archdots
```

Drive panels over IPC rather than by typing. The notification server and the
polkit agent cannot register while another one holds the session; run the
copy under `dbus-run-session` to test notifications.

Things learnt the hard way:

- `Hyprland.activeToplevel` is null until the first focus change after start;
  `services/Hypr.qml` covers that gap from `hyprctl activewindow`.
- A handler can run before bindings on the same property update; read derived
  values through `Qt.callLater` there.
- `font.pixelSize` takes whole pixels only; `BarText.px` goes through points.
- `MonthGrid` has no implicit height inside a layout.
