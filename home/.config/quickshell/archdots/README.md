# archdots shell (Quickshell)

The Quickshell rewrite of `fabric_shell`. For now it is the bar only, run side
by side with fabric's daemon, which still provides the launcher, popups and
notifications (TODO.md, phases 3 and 4).

```
shell.qml        entry point: a bar per screen, the IPC targets
config/          Config (settings.json over defaults), Colours (pywal16)
services/        state, no UI: Audio, Battery, Media, CpuTemp, Hypr, Fabric
widgets/         shared pieces: Island, BarText, Divider, Hot
modules/bar/     the bar and its islands
```

Imports go through Quickshell's `qs.` module paths (`import qs.config`).
Singletons are files with `pragma Singleton`.

## Running it

```bash
qs -c archdots                        # stowed as ~/.config/quickshell/archdots
qs -p ~/archdots/home/.config/quickshell/archdots   # straight from a clone
```

At login, `hypr/config/helpers/shell.lua` starts it in place of fabric's
`bar.py` when `ARCHDOTS_BAR=quickshell` is set, for example in
`~/.config/archdots/hypr/environment.lua`:

```lua
hl.env("ARCHDOTS_BAR", "quickshell")
```

## IPC

```bash
qs -c archdots ipc show                               # every target and function
qs -c archdots ipc call bar toggle                    # also open, close
qs -c archdots ipc call settings set bar.showCpu false
qs -c archdots ipc call shell reload
```

`show` and `hide` cannot be function names: `qs ipc call bar show` parses
`show` as the ipc subcommand of that name.

## Settings

`config/Config.qml` declares every setting with its default;
`~/.config/archdots/settings.json` overrides any of them, and edits to it apply
live. Write with `Config.set("bar.showCpu", false)`, never `writeAdapter()`:
on quickshell 0.3.2 that rewrites the whole file from the declared properties,
dropping keys it does not know and writing every default. `set()` changes only
the one key and leaves an unparsable file alone.

## Testing without replacing the running bar

`qs -p <path>` runs a second copy next to whatever is running. Point `HOME`
at a scratch folder to give it its own `settings.json`:

```bash
HOME=/tmp/qshome qs -p home/.config/quickshell/archdots
```

`Hyprland.activeToplevel` is null until the first focus change after start;
`services/Hypr.qml` covers that gap from `hyprctl activewindow`.
