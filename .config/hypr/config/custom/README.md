# custom/ — per-machine overrides

The files in `config/` are the **committed defaults** and describe one machine
fully. Anything that differs on another machine goes in here instead.

`hyprland.lua` requires every module in `config/`, then requires the file of the
same name in `config/custom/` if it exists. Later calls win, so an override only
has to restate the part that differs.

```
config/monitor.lua          ← committed default (this machine's layout)
config/custom/monitor.lua   ← loaded after, wins
```

**These `.lua` files are gitignored** — that is the point. Editing one never
shows up as a repo change, so a machine's quirks never get pushed. This README
is tracked so the folder exists in a fresh clone; the stubs are recreated by
hand (an empty file, or no file at all, is perfectly valid).

## What tends to live here

| File | Typical contents |
|---|---|
| `monitor.lua` | `hl.monitor` for this machine's outputs, and the workspace→monitor rules that depend on their names |
| `environment.lua` | GPU vars — the defaults set `LIBVA_DRIVER_NAME`/`__GLX_VENDOR_LIBRARY_NAME` to nvidia |
| `input.lua` | `hl.device` blocks, which key off exact device names such as `elan0788:00-04f3:321a-touchpad` |
| `autorun.lua` | hardware-bound daemons, e.g. `solaar` for a Logitech receiver |
| `keybind.lua` | a different terminal/browser, or extra machine-only binds — give each a `desc` (below) |
| `rules.lua` `theme.lua` `animation.lua` | rarely needed; available for symmetry |

## Overriding, in practice

Re-declaring wins, because the later call is applied last:

```lua
-- custom/monitor.lua — a single-screen laptop
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1.0 })

-- the default puts odd workspaces on an external monitor that does not exist
-- here, so send every workspace to the built-in panel
for workspace = 1, 10 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = "eDP-1" })
end
```

There is no "unset" — an override replaces or adds, it cannot delete a default.
If something in `config/` proves impossible to override, that is a sign it
belongs here rather than there.

## Name your binds with `desc`

Binds added here show up on the cheatsheet (`SUPER` + `/`) automatically, but
only `desc` can say what they *do*:

```lua
-- custom/keybind.lua
hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"), { desc = "Launch: GIMP" })
```

The cheatsheet reads `hyprctl binds -j`, and under the Lua config provider every
bind is a `__lua` callback — the combo is visible, the action is not. `desc` is
the only field that survives. Use `"Group: Label"`; an existing group name puts
the bind in that card, a new one creates a card. Without a `desc` the bind is
listed under **Undescribed**, which is a reminder rather than a failure.

## If an override seems to do nothing

A broken override is reported rather than swallowed. You get a critical
notification naming the file and line, and a durable record in:

```bash
cat ~/.cache/hypr-custom.log
# 2026-08-13 07:41:19 custom/rules.lua: .../custom/rules.lua:6: syntax error near 'is'
```

A broken override never takes the session down — everything else still loads.

Two things are worth knowing if you ever change how this is loaded:

- **`require` cannot detect a broken override here.** Hyprland's `require` does
  not raise on a module with a syntax error; it returns a table and reports
  success, so `pcall(require, ...)` sees nothing wrong. `hyprland.lua` uses
  `loadfile()` instead, which returns `nil` plus a message, then runs the chunk
  under `pcall` to catch runtime errors too.
- **`io.stderr` from the config does not reach Hyprland's log.** That is why
  failures go to `~/.cache/hypr-custom.log` and `notify-send` instead.

Check syntax before reloading, which is cheaper than debugging a dead session:

```bash
luac -p ~/.config/hypr/config/custom/*.lua && hyprctl reload
```
