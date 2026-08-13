# Development notes

How this setup actually works, why a few things are the way they are, and what
is still on the list. [README.md](README.md) is the tour; this is the manual.

**Contents**

- [Repo layout](#repo-layout)
- [fabric_shell](#fabric_shell)
- [Theming pipeline](#theming-pipeline)
- [Per-machine config](#per-machine-config)
- [Naming keybinds](#naming-keybinds)
- [Settings that cannot be stowed](#settings-that-cannot-be-stowed)
- [Package notes](#package-notes)
- [Known rough edges](#known-rough-edges)
- [The install script](#the-install-script)
- [Roadmap](#roadmap)

---

## Repo layout

```
.config/
  hypr/            Hyprland — hyprland.lua + config/*.lua, hyprlock, hyprpaper
    config/custom/   per-machine overrides, loaded last (untracked)
  fabric_shell/    the desktop shell (Python + GTK3 layer-shell)
  wal/templates/   pywal templates — the source of all theming
  alacritty/ eza/ fastfetch/ cliphist/ fontconfig/
  Kvantum/ qt6ct/ kdeglobals    Qt theming
  uwsm/            session env (forces Hyprland onto the iGPU)
.themes/           GTK theme
.themes_sddm/      SDDM theme
.ohmyzsh_custom/   zsh theme + plugins (git submodules)
wallpapers/
.zshrc
```

Everything is stowed into `$HOME` except what `.stow-local-ignore` lists —
`install.sh`, the two markdown files, `wallpapers/` and git's own files.
Anything added at the repo root that is *not* meant to land in `$HOME` has to be
added there too.

`wallpapers/` is on that list because the picker reads `~/Pictures/wallpapers`
([`wallpapers.py:29`](.config/fabric_shell/wallpapers.py)), not the repo — a
`~/wallpapers` symlink would just be dead weight. `install.sh` copies them
across instead.

---

## fabric_shell

A small desktop shell written with [Fabric](https://github.com/Fabric-Development/fabric)
(Python + GTK3 + layer-shell). It replaces waybar, rofi, dunst and nwg-bar.

Fabric is not packaged for Arch, so the shell brings its own virtualenv at
`.config/fabric_shell/.venv`, installed from `fabric_shell/requirements.txt`.

That file is deliberately **one line** — fabric, pinned to an exact commit.
`click`, `loguru`, `pycairo` and `PyGObject==3.50.0` are fabric's own declared
dependencies and arrive with it, so listing them again would only create a
second place to drift. Pinning the commit matters more than it looks: fabric has
no releases, so an unpinned install tracks `main` and can change under you.

pip **compiles** pycairo and PyGObject rather than fetching wheels, so the
system needs `cairo`, `gobject-introspection` and `pkgconf` present — they come
with `python-gobject` and `gtk3` in the core package list.

**Two long-lived processes**, started by `hypr/config/autorun.lua`:

| Process | Role |
|---|---|
| `bar.py` | one bar per monitor — workspaces, window title, media, volume/temp/battery, clock |
| `daemon.py` | notification service + every overlay, listening on `/tmp/fabric-shell.sock` |

**Overlays** are constructed once and kept alive hidden, never respawned — which
is why the launcher opens instantly:

| Window | What it is |
|---|---|
| `launcher` | app search with frequency ranking, `?` prefix for a web search |
| `clipboard` | `cliphist` history with image thumbnails |
| `emoji` | searchable grid with a category rail, remembers your most used |
| `powermenu` | full-screen scrim: lock / logout / restart / shutdown |
| `control` | Wi-Fi, Bluetooth, volume + brightness, player, tray, DND — tabbed |
| `notifications` | history with per-urgency styling, clear-all and a DND switch |
| `calendar` | month grid, dropped from the clock island |
| `wallpaper` | thumbnail picker that sets the wallpaper *and* re-themes live |
| `screenshot` | region / window / screen / delayed, to file **and** clipboard |
| `osd` | volume, mic and brightness level, bottom-centre, auto-dismiss |
| `battery` | low/critical warning, centred, auto-dismiss unless critical |
| `keybinds` | cheatsheet of every bind, read live from Hyprland |

`ctl.py toggle|show|hide <window> [arg]` writes one line to the daemon's socket;
that is all a keybind does. Window names live in `windows.py`, which `ctl.py`,
`daemon.py` and `bar.py` all import so the list cannot drift. Shared window,
animation, keyboard and stylesheet logic lives in `common.py`.

`.config/fabric_shell/todolist.md` is the blow-by-blow build log for the shell —
every gotcha found while writing it, with the reasoning. Worth reading before
changing anything in there.

### The shell is the notification daemon

It owns `org.freedesktop.Notifications`, so anything calling `notify-send` draws
as a shell card and expires on the sender's timeout (5s default; critical waits
for you).

**Never install a second notification daemon.** dunst, mako and swaync each ship
a systemd user service that grabs that bus name at login. The fabric daemon
cannot take a name someone else already owns, so its cards simply never appear
and nothing anywhere reports an error. If notifications go quiet, check the
owner first:

```bash
busctl --user status org.freedesktop.Notifications   # compare PID with the daemon
pgrep -f fabric_shell/daemon.py
```

blueman is a related trap: it draws its *own* centred GTK window when no
notification daemon has claimed the bus yet — exactly the situation at boot,
when a headset auto-connects before the shell is up. See
[Settings that cannot be stowed](#settings-that-cannot-be-stowed).

---

## Theming pipeline

There is no hardcoded palette. **pywal** generates colors from the current
wallpaper, and templates in `.config/wal/templates/` push them everywhere:

| Template | Feeds | How |
|---|---|---|
| `colors-hyprland.lua` | borders, shadows | `theme.lua` does `dofile` on `~/.cache/wal/colors-hyprland.lua` |
| `colors-fabric.css` | the whole shell | copied into `fabric_shell/css/`, live-reloaded on change |
| `colors-alacritty.toml` | terminal | imported by the alacritty config |

`color4` is the accent throughout — workspace highlight, selected-row glow,
search caret, window border gradient. Every config falls back to a dark neutral
palette when `~/.cache/wal/` is missing, so a fresh install works before the
first `wal` run.

The wallpaper picker (`SUPER` + `W`) sets the wallpaper on every monitor, runs
pywal, copies the palette into `fabric_shell/css/`, and rewrites the paths in
`hyprpaper.conf` so the choice survives a reboot.

**The shell recolours in place** because every window watches that palette file
through `common._watch_palette()`. One catch worth knowing: `monitor_file()`
returns a `Gio.FileMonitor` that stops watching the moment it is garbage
collected, so the monitors are parked in `common._MONITORS` for the life of the
process. Dropping that reference is what made colors apply only after a restart.
The same applies to `watch_audio()` and `media.watch()`, which return
subprocesses.

---

## Per-machine config

`hyprland.lua` requires every module in `config/`, then loads the file of the
same name in `config/custom/` if it exists. Later calls win, so an override only
restates the part that differs:

```
config/monitor.lua          committed default — the owner's layout
config/custom/monitor.lua   loaded after, wins
```

`config/custom/*.lua` is gitignored; `config/custom/README.md` is tracked and
documents what belongs there. What usually differs: monitor layout and the
workspace rules that name monitors, GPU env vars, `hl.device` blocks (they key
off exact device names), and hardware-bound autostarts like `solaar`.

Two things that are not obvious, both found by testing:

- **`require` cannot detect a broken override.** Hyprland's `require` does not
  raise on a module with a syntax error — it returns a table and reports
  success, so `pcall(require, ...)` sees nothing wrong. `hyprland.lua` uses
  `loadfile()` instead, which returns `nil` plus a message, then runs the chunk
  under `pcall` to catch runtime errors too.
- **`io.stderr` from the config never reaches Hyprland's log.** Failures are
  therefore appended to `~/.cache/hypr-custom.log` and raised as a critical
  notification. A broken override never takes the session down; the rest of the
  config still loads.

Check syntax before reloading — cheaper than debugging a dead session:

```bash
luac -p ~/.config/hypr/config/custom/*.lua && hyprctl reload
```

---

## Naming keybinds

The cheatsheet (`SUPER` + `/`) is generated from `hyprctl binds -j` every time
it opens, so binds added in `config/custom/keybind.lua` appear with no code
change.

The catch: **hyprctl knows the key combo but not the action.** Under the Lua
config provider every bind is registered as a `__lua` callback, so `dispatcher`
is always `"__lua"` with an opaque index — all 64 binds look identical. The only
field that survives is `description`, set per bind with `desc`:

```lua
hl.bind(mainMod .. "+ B", hl.dsp.exec_cmd(browser), { desc = "Launch: Browser" })
```

Convention is `"Group: Label"`. The group becomes a card heading; binds sharing
a group and label collapse into one row, which is how ten workspace binds render
as `SUPER 1…0`. A bind with no `desc` still appears, under **Undescribed** —
visible by design, because a new bind that silently did not show up would look
broken.

Collapsing only folds digit runs (`1…0`) and arrow sets (`←→↑↓`). An earlier
version folded any single-character key and turned the four focus binds into the
nonsense `←…↓`.

---

## Settings that cannot be stowed

Some settings live in **GSettings/dconf** (`~/.config/dconf/user`), a binary
database. They cannot be stowed and must be applied by command.

### blueman's centred "device connected" window

```bash
gsettings set org.blueman.general plugin-list \
  "['!ConnectionNotifier', '!AutoConnect']"
```

The `!` prefix is blueman's disabled marker; undo with
`gsettings reset org.blueman.general plugin-list`.

**Two different plugins can produce that window — disabling one is not enough.**
They were found the hard way, in this order:

| Plugin | What it sends | Cost of disabling |
|---|---|---|
| `ConnectionNotifier` | "Connected" / "Disconnected" | notifications only |
| `AutoConnect` | "Automatically connected to *service* on *device*" (`AutoConnect.py:67`) | **also stops the auto-connecting itself** |

`AutoConnect` is the one that fires at boot. Note the second row: that plugin
*performs* the reconnect (on start, on adapter power-on, and every 60s) and only
notifies afterwards, so switching it off means blueman no longer reconnects
anything. If auto-reconnect matters, use `bluetoothctl trust <MAC>` so bluez
does it instead, or leave `AutoConnect` on and accept the card once the shell
is up.

### Bluetooth not staying off across a reboot

bluez powers on every controller it finds at startup — `/etc/bluetooth/main.conf`
says *"AutoEnable ... Defaults to 'true'"* and leaves the line commented, so the
default applies. `bluetoothctl power off` only clears the adapter's runtime
`Powered` property, so it is undone on the next boot.

**rfkill state is what persists**: systemd saves it at shutdown under
`/var/lib/systemd/rfkill/` and restores it at boot. The control centre's
Bluetooth toggle therefore rfkill-blocks as well as powering down, so "off"
stays off. For the same effect system-wide, set `AutoEnable=false` in
`/etc/bluetooth/main.conf` (root-owned, so not part of these dotfiles).

---

## Package notes

The lists in [README.md](README.md#packages) are curated — they cover the
desktop, not every package on the machine. Notes on the non-obvious ones:

- `foot` is only used by the launcher to run terminal apps; alacritty is the
  interactive terminal.
- `libnotify` provides `notify-send`; the card itself is drawn by the shell.
- `bluez-utils` provides `bluetoothctl`, which the control centre uses to power
  the adapter and connect paired devices. **Pairing a new device still has to be
  done from `bluetoothctl`** — it needs a passkey prompt the panel has nowhere
  to show.
- `nmcli` (networkmanager) backs the Wi-Fi list. The control centre reads it
  with `--rescan no`: without that, nmcli forces a scan and blocks ~5 seconds on
  the GTK main loop, which made the panel look like it had hung.
- JetBrainsMono Nerd Font is the shell's font — without it every glyph in the
  bar renders as a box.

To regenerate the lists from a working machine:

```bash
pacman -Qqen          # explicit, from the official repos
pacman -Qqem          # foreign / AUR
flatpak list --app --columns=application
```

---

## Known rough edges

- **GTK transparency is not uniform.** The catppuccin theme was hand-modified to
  be transparent, so it is definitely broken in places.
- **Dolphin's list view is broken** under Kvantum `KvGlass`. Use icon view.
- **`uwsm/env-hyprland` pins specific DRM device paths** to force Hyprland onto
  the iGPU. It is not Lua, so the per-machine override mechanism does not cover
  it — `install.sh` detects and rewrites it instead, which leaves the tracked
  file dirty. Same for `hyprpaper.conf` and `hyprlock.conf`.
- **`config/monitor.lua` keeps one laptop's layout as the default**, which is
  wrong elsewhere until overridden in `config/custom/`. `install.sh` writes a
  starter override from the detected outputs, but the positions in it are a
  left-to-right guess.
- **Some tray icons fall back to a generic glyph.** Apps advertising an icon
  name breeze-dark does not carry (spotify's, for one) get a placeholder;
  `fabric_shell/tray.py` keeps them clickable rather than dropping the item —
  fabric's own tray drops the whole item, which is why the tray once looked
  empty.

  `tray.py` also exists for a second, worse reason: **fabric's tray replaces the
  process-wide icon theme's search path** with whatever single directory a tray
  item advertises (`service.py`: `Gtk.IconTheme.get_default()` followed by
  `set_search_path([...])`). One such item — spotify — and every icon in the
  daemon stops resolving, launcher and notifications included, permanently and
  across restarts. `tray.py` resolves icons in a private theme built from a
  search path captured at import, and never touches fabric's `item.icon_theme`.
  **Do not "simplify" it back to `super().do_update_properties()`.**
- **Bluetooth pairing is not in the control centre** — connecting to an
  already-paired device is one click, first-time pairing is `bluetoothctl`.

---

## The install script

`install.sh` replaced the old `installscript.sh`, which predated the shell
rewrite and still installed waybar, nwg-bar, yazi and **dunst**.

It runs from either direction — piped from curl on a bare install, or `./install.sh`
inside an existing clone. `find_repo_root()` tells the two apart by looking for
`.stow-local-ignore` **and** `.config/fabric_shell`, a pair that exists nowhere
else; when piped there is no `BASH_SOURCE` path to resolve, so it clones and
`exec`s the copy on disk with `ARCHDOTS_REEXEC=1` guarding against a loop.

Every step is idempotent, so a second run updates rather than duplicates.

### What it does beyond `stow .`

| Step | Why it cannot be a symlink |
|---|---|
| `git clone --recurse-submodules` | `.ohmyzsh_custom` carries the zsh plugins as submodules; a plain clone leaves those directories empty |
| Remove dunst / mako / swaync | they take `org.freedesktop.Notifications` at login and the shell's cards then never appear — see [above](#the-shell-is-the-notification-daemon) |
| Build `.venv` | Fabric is not packaged for Arch |
| oh-my-zsh | `.zshrc` sources it; installed with `--keep-zshrc` or the installer overwrites the symlink stow just made |
| Copy wallpapers to `~/Pictures/wallpapers` | that is where the picker looks |
| First `wal -i` run | otherwise the shell starts on its fallback palette |
| `gsettings` for blueman | dconf is a binary database — [see above](#settings-that-cannot-be-stowed) |
| Enable `sddm`, `NetworkManager`, `bluetooth` | systemd, not files |

The venv install uses the **absolute** path to `requirements.txt`. A bare
`-r requirements.txt` resolves against the working directory, which at that point
is the repo root, where no such file exists.

The script refuses to run as root. `stow`, the venv and every `gsettings` call
have to be the user's; it calls `sudo` only for pacman and `systemctl enable`.

### Machine-specific detection

Three things are detected, shown for review, and only then written:

| What | Detected from | Written to |
|---|---|---|
| GPU order (`AQ_DRM_DEVICES`) | `/sys/class/drm/card*/device/vendor` — anything that is not `0x10de` goes first, so Hyprland lands on the iGPU | `.config/uwsm/env-hyprland` |
| Monitor layout | `hyprctl monitors -j` when Hyprland is up, otherwise the connected connectors under `/sys/class/drm/card*-*` — the sysfs names are the same names Hyprland uses | `config/custom/monitor.lua` |
| Wallpaper paths | the first file in `~/Pictures/wallpapers` | `hyprpaper.conf`, `hyprlock.conf` |

Two traps found while writing it:

- **`hyprctl monitors -j` cannot be grepped for `"name"`.** Each monitor carries
  a nested `activeWorkspace` object with its own `name`, so a naive grep returns
  `eDP-1 2 HDMI-A-1 1` — workspace numbers interleaved with monitor names. It is
  parsed with `python3 -m json`, falling back to `^Monitor \K\S+` on the plain
  text output.
- **`sed -i` on a stowed file replaces the symlink with a regular file**, quietly
  ending the link to the repo. `--follow-symlinks` is required. Whole-file
  rewrites with `>` are safe — redirection follows the link and truncates the
  target.

Only `config/custom/monitor.lua` is gitignored. `env-hyprland`, `hyprpaper.conf`
and `hyprlock.conf` are **tracked**, so writing this machine's values into them
shows up as a dirty worktree. That is expected rather than a bug — it is the
same thing the wallpaper picker does to `hyprpaper.conf` every time you change
wallpaper — and the script says so in its closing summary. `git checkout --` on
the file undoes it.

The generated layout places monitors left to right at 1920 intervals, which is a
guess. It is `luac -p`-checked when luac is present, since a broken override is
[reported rather than fatal](#per-machine-config) and would otherwise only turn
up in `~/.cache/hypr-custom.log`.

### Still not handled

- `hl.device` blocks in `config/custom/input.lua` — they key off exact device
  names and there is no sensible default to generate.
- Monitor *positions* and refresh rates. The script writes `mode = "preferred"`
  and a left-to-right guess; anything else is a decision only the owner can make.

---

## Roadmap

- [x] Keybinds graphic — `SUPER` + `/`, generated from Hyprland rather than
      hand-maintained
- [x] Separate machine-specific Hyprland config
- [x] Drop the unused waybar / rofi / dunst leftovers
- [x] Shell: OSD, control centre, notification history, calendar, wallpaper
      picker, screenshot menu, media island, keybind cheatsheet
- [ ] Create a custom uniform theme
- [ ] Bluetooth pairing (needs a passkey dialog) in the control centre
- [x] Rewrite the install script — `install.sh` ([above](#the-install-script))
- [ ] Separate the remaining machine-specific bits (per-program configs)
