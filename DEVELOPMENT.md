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
  - [The SDDM theme](#the-sddm-theme)
  - [Testing it](#testing-it)
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
  gtk-3.0/settings.ini          GTK theming — picks the theme in .themes/
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
system needs `cairo`, `gobject-introspection` and `pkgconf` present. They are
listed explicitly in the core package list rather than left to arrive as
somebody else's dependency.

**Fabric also has runtime dependencies pip cannot express.** They are GObject
typelibs, not wheels, so nothing in `requirements.txt` can pull them in:

| Namespace | Package | Reached via |
|---|---|---|
| `Gtk` | `gtk3` | everything |
| `GtkLayerShell` | `gtk-layer-shell` | every overlay |
| `DbusmenuGtk3` | `libdbusmenu-gtk3` | `fabric.system_tray`, imported by `tray.py` |

The last one is the trap. `fabric/system_tray/service.py` calls
`gi.require_version("DbusmenuGtk3", "0.4")` at **import** time, and `daemon.py`
imports it transitively through `controlcenter.py` → `tray.py`. Without the
package the daemon dies on startup and takes every overlay with it — launcher,
clipboard, emoji, powermenu, control centre, notifications, calendar, wallpaper,
screenshot, OSD, battery, cheatsheet — while `bar.py` keeps running happily. The
desktop looks half-alive rather than broken, and `hl.exec_cmd` swallows the
traceback, so nothing anywhere says why.

It was invisible for a long time because `libdbusmenu-gtk3` arrives as a
dependency of **waybar** and `libappindicator`. Dropping waybar for
`fabric_shell` removed the only reason it was installed — but not from any
machine that had already had waybar. Fabric's other namespaces (`Cvc`,
`GnomeBluetooth`, `WebKit2`) sit in modules this shell never imports; the audio
and bluetooth panels shell out to `wpctl` and `bluetoothctl` instead.

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
busctl --user list | grep Notifications   # name, owning PID, and process
pgrep -f fabric_shell/daemon.py           # the two PIDs must match
```

`busctl --user status org.freedesktop.Notifications` works too, but note it
prints `PID=1234` — **equals-separated, and followed by a `PIDFD=` line**. An
`awk '/^PID/{print $2}'` over that yields an empty string and reads as "nobody
owns the bus" on a perfectly healthy system. `awk -F= '/^PID=/{print $2}'`.

blueman is a related trap: it draws its *own* centred GTK window when no
notification daemon has claimed the bus yet — exactly the situation at boot,
when a headset auto-connects before the shell is up. See
[Settings that cannot be stowed](#settings-that-cannot-be-stowed).

---

## Theming pipeline

### The GTK theme has to be *selected*, not just present

`.themes/` ships the theme; `.config/gtk-3.0/settings.ini` is what chooses it:

```ini
gtk-theme-name=catppuccin-mocha-pink-standard+default
gtk-icon-theme-name=breeze-dark
gtk-application-prefer-dark-theme=1
```

Without that file GTK falls back to **Adwaita light**, and the result is a shell
with white panels and grey-on-white text that looks broken rather than
misconfigured — the pywal palette is applied correctly on top of a light base.
It is easy to miss because the file is not something you ever touch after
setting it once, so a machine that has had it for years looks fine while a
fresh install does not. `breeze-icons` and `adwaita-fonts` are in the core
package list for the same reason: `settings.ini` names both, and a named theme
that is not installed silently falls back.

`install.sh` also mirrors those two values into dconf. GTK3 reads
`settings.ini`, but XSettings, the portals and GTK4 ask dconf instead, and the
two disagreeing is what makes some windows light and others dark.



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

- **alacritty is the only terminal.** The launcher wraps `.desktop` entries
  marked `Terminal=true` in it via `launcher.TERMINAL`, which is the one place
  to change if that ever moves. `foot` used to fill that role and is no longer
  installed.
- `libnotify` provides `notify-send`; the card itself is drawn by the shell.
- `bluez-utils` provides `bluetoothctl`, which the control centre uses to power
  the adapter and connect paired devices. **Pairing a new device still has to be
  done from `bluetoothctl`** — it needs a passkey prompt the panel has nowhere
  to show.

  **`bluetoothctl` never gives up.** With `bluetoothd` unreachable it does not
  exit with an error — it prints *"Waiting to connect to bluetoothd..."* and
  waits indefinitely. The control centre's readers run on the GTK main loop, so
  a single such call froze the whole panel. That is why it only ever appeared on
  a machine with no Bluetooth hardware, where the service never starts. Every
  call is now gated on `rfkill list bluetooth`, which the kernel answers with no
  daemon involved, and bounded by `timeout` for the case where the radio exists
  but the daemon is wedged. Same failure mode as the `nmcli` note below, and the
  second time it has been paid for: any blocking command on the main loop is a
  freeze waiting to happen.
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
- **CPU temperature is detected, not hardcoded.** `thermal_zone0` is not the CPU
  on every machine — on this laptop it is `acpitz`, a chassis probe reading ~20°C
  below the package sensor at `thermal_zone3`, and on other hardware zone0 is
  `INT3400`, which reports a constant 20°C. `common.find_cpu_temp()` prefers the
  `coretemp`/`k10temp` hwmon and falls back to thermal zones by `type`, never by
  index. If the bar shows `--°C`, no known sensor matched.
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

> [!WARNING]
> **Not yet proven on real hardware.** Every stage has been exercised in a
> container and the whole thing runs green there, but no one has run it on a
> fresh machine and logged in. The parts most likely to bite are the ones a
> container cannot reach: SDDM actually starting the session, the GPU/DRM
> ordering in `env-hyprland`, real monitors, and anything touching dconf.
> Treat a first run as something to supervise, not fire and forget.

`install.sh` replaced the old `installscript.sh`, which predated the shell
rewrite and still installed waybar, nwg-bar, yazi and **dunst**.

It runs from either direction — piped from curl on a bare install, or `./install.sh`
inside an existing clone. `find_repo_root()` tells the two apart by looking for
`.stow-local-ignore` **and** `.config/fabric_shell`, a pair that exists nowhere
else; when piped there is no `BASH_SOURCE` path to resolve, so it clones and
`exec`s the copy on disk with `ARCHDOTS_REEXEC=1` guarding against a loop.

Every step is idempotent, so a second run updates rather than duplicates.

It has two modes — `install.sh install` (the default) and `install.sh update`,
[below](#update-mode).

### The prompts

Every question goes through one layer with two backends: `whiptail` boxes when
libnewt is installed and there is a terminal to draw on, plain text on stdout
otherwise. `ui_init()` picks between them, and plain wins for any of `--no-gui`,
`--yes`, no `/dev/tty`, no `whiptail`, or `TERM` unset or `dumb`. Plain is a
supported mode, not a degraded one — the curl one-liner and the container tests
both land there — and `libnewt` is in `PKG_CORE`, so the *second* run gets boxes
even when the first could not.

Only the questions are drawn. pacman, makepkg and pip keep printing to the
terminal: hiding a half-hour PyGObject compile behind a fake progress bar helps
nobody, and that output is the only thing that explains a failure.

Three details are load-bearing:

- **whiptail answers on stderr** and draws on stdout, hence `2>&1 1>/dev/tty`
  in `wt()`. Prompts read from `/dev/tty` for the same reason the plain ones do:
  piped from curl, stdin is the script itself.
- **Nothing uses `--scrolltext`.** A scrollable widget puts keyboard focus in
  the text pane, so <kbd>Enter</kbd> scrolls instead of pressing a button and
  the dialog looks frozen until you think to press <kbd>Tab</kbd>; given a box
  taller than its own text it also draws a broken scrollbar across the border.
  Long content is clipped to fit (`wt_clip()`) and printed in full to the
  terminal, which scrolls the way people expect. `review_confirm()` prints the
  whole generated file before showing its box, so the clip loses nothing.
- **`choose()` prints its plain-mode menu to stderr.** The caller reads the
  function through `$(…)`, and anything on stdout is swallowed into the answer.

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
| The SDDM theme | lives in `/usr/share` and `/etc` — [below](#the-sddm-theme) |
| Enable `sddm`, `NetworkManager`, `bluetooth` | systemd, not files |

`paru` is built **from source**, not `paru-bin`. The binary package is linked
against one libalpm soname; the moment pacman bumps it, paru dies with
`error while loading shared libraries: libalpm.so.N` and every AUR install in
the script fails with it. Compiling links against the pacman actually installed.
The script also treats an existing-but-broken paru as absent and rebuilds it.

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

`hyprpaper.conf` is written with an **empty** `monitor =`, which means *every
output*. Naming the detected monitors instead reads better and is a trap: the
moment an output is named differently than it was at install time — a dock, a
different cable, a nested session — hyprpaper matches nothing and paints
nothing, with no error anywhere. A black desktop is the only symptom. The same
catch-all is what the picker sends at runtime (`hyprctl hyprpaper wallpaper
",path"`).

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

### The SDDM theme

Three separate pieces, none of them stowable because none of them live in
`$HOME`:

| Piece | Where | Why the script has to do it |
|---|---|---|
| the package | `sddm-silent-theme` (AUR) | pinned to a version, see below |
| the config | `/usr/share/sddm/themes/silent/configs/default.conf` | root-owned; the repo keeps an edited copy in `.themes_sddm/` |
| the greeter | `/etc/sddm.conf.d/10-archdots.conf` | selects the theme and sets `QML2_IMPORT_PATH` |

**The version is pinned on purpose.** The theme's `default.conf` schema changes
between releases, and an upgrade overwrites that file outright — so an upgrade
silently replaces the edited login screen with the stock one, and can leave
options behind that the new version no longer understands. `install.sh` builds
`SDDM_THEME_VERSION` specifically and adds the package to `IgnorePkg` in
`/etc/pacman.conf`.

The AUR carries no version tags, so the pin works by walking `PKGBUILD` history
for the newest commit that declares the wanted `pkgver`, then building from
that commit:

```bash
git log --format=%H -- PKGBUILD    # newest first
git show "$commit:PKGBUILD" | grep -qx "pkgver=1.3.5"
```

**The theme cannot be built with `makepkg -si` alone.** Its `depends` include
`redhat-fonts`, which is itself an AUR package, and makepkg resolves
dependencies through pacman only — so the build dies on
`error: target not found: redhat-fonts` every time. The script sources the
checked-out `PKGBUILD` to read `depends`, installs those through paru, and only
then runs makepkg. Reading the list rather than hardcoding it means a version
bump cannot silently drift from what the script installs.

`QML2_IMPORT_PATH` in the greeter config is **not** optional. Without it the
greeter loads with none of the theme's components and SDDM falls back to a blank
screen — which looks like a broken display rather than a missing setting.

The edited `default.conf` is copied over the theme's own, and the original is
kept beside it as `default.conf.orig`. Because the destination is root-owned,
editing `.themes_sddm/…/default.conf` is not enough on its own — re-run
`install.sh` (or copy it across by hand) to apply the change.

### Update mode

`install.sh update` is the "I already have this installed" path. It runs
`update_repo`, `update_packages`, `stage_stow`, `stage_venv upgrade`,
`stage_wallpapers` and `restart_shell`, and deliberately skips the machine
detection — the GPU, monitor and wallpaper answers were settled at install time,
and rewriting them on every update would keep asking about hardware that has not
changed. `./install.sh install --skip-packages` is the way to redo them after a
hardware change.

**The stash is the whole trick.** `install.sh` edits *tracked* files on purpose —
`env-hyprland`, `hyprpaper.conf`, `hyprlock.conf`, `colors-fabric.css` — so a
dirty tree is the normal state of an installed clone, and `git pull --ff-only`
would refuse to run in it. `update_repo` stashes with `-u`, pulls, then pops. If
the pop conflicts the stash is **kept**, the run continues, and the summary says
where to find it; losing a machine's GPU pin to a silent `stash drop` would be
much worse than a merge conflict.

`update_packages` is `pacman -S --needed` over the same package lists, which is
a no-op for everything already installed and picks up only what the repo has
gained since the last run. A full `-Syu` is asked separately and defaults to no:
upgrading the system is the user's decision, not a side effect of updating some
dotfiles.

`restart_shell` mirrors `hypr/config/helpers/shell.lua` — kill both long-lived
modules, re-sync the pywal colours, start them again, all in one shell so that
shell's own command line is what its own `pkill` sees. It runs under `setsid`,
or the new daemon would be a child of the installer and die with it. It only
offers when a shell is actually running, and skipping it is fine: the keybind
does the same thing later.

### Testing it

> [!WARNING]
> **The harness is not a substitute for a real install yet.** It proves the
> script *runs* — packages resolve, stow links, the shell builds and starts —
> but it renders the desktop in a nested window on borrowed hardware, and
> several things diverge from a real session. The known list is
> [below](#the-container-is-not-11-with-a-real-session--yet); most importantly,
> **theming cannot be judged from a container screenshot.** A green run here
> does not mean the install is correct on metal.

`install.sh` is testable in a container without touching the machine it is run
from. The harness lives outside the repo and is reached through the gitignored
`archdots_docker` symlink:

```bash
cd archdots_docker
./runscript.sh --fast     # no packages, ~10s — structure, stow, detection
./runscript.sh --full     # every package, the venv build, paru, the theme
./runscript.sh --hypr     # starts Hyprland and the shell for real, screenshots it
./runscript.sh --ui       # same, but leaves it up so you can click around
./runscript.sh            # interactive shell with the repo at ~/archdots
./runscript.sh -- --yes --no-aur   # anything after -- goes to install.sh
```

The checks themselves live in `checks.sh`, mounted into the container rather
than inlined into `docker run bash -c '…'` — they need both quote characters,
and nesting those in one shell string truncates the script silently.

The repo is mounted **read-only** and copied to a writable path inside, so a
test cannot modify the working tree. The copy strips `config/custom/*.lua` and
`.venv` first — without that the test inherits the host's machine-specific
files and reports `monitor.lua already exists`, which is the opposite of what a
new machine sees.

### The container is not 1:1 with a real session — yet

Package resolution, stow folding, the fabric build, the AUR path and the
config parse are all real. The *rendered desktop* is not, and these differences
are known:

| Divergence | Why | Handled? |
|---|---|---|
| `/sys` is the **host's** | containers share the kernel, so GPU and monitor detection read this machine's hardware, not a fresh one | no — read those results as "the host's", not "a new install's" |
| No dbus machine-id | `gsettings` writes fail, so the GTK theme is set only by the stowed `settings.ini` and never mirrored into dconf | no — the dconf half of the theming is therefore untested |
| No systemd | `systemctl enable` fails | harmless, reported as a warning |
| Nested output defaults to **scale 2** | Hyprland's Wayland backend; every CSS pixel drawn as two, so the shell comes out twice its real size | yes — the harness pins `WAYLAND-1` to `scale = 1.0` |
| `SUPER` never arrives | the host compositor claims it first | yes — Caps is remapped to an additional Super inside the container |
| The working tree is copied, not cloned | files flagged `assume-unchanged` (`.zsh_custom`) would otherwise leak personal config in | yes — those are reset to their committed state |
| **Bar islands do not follow the palette** | unexplained | **no — see below** |

That last one is the reason this section exists. In the container the bar
islands render a flat neutral grey (~`#333`) and stay there across a palette
change, while the same CSS on a real session resolves to a different colour per
palette — verified by asking GTK to compute it:

| palette | `.island` background GTK resolves |
|---|---|
| green wallpaper | `rgba(56,69,57,0.88)` |
| grey wallpaper | `rgba(33,35,37,0.88)` |
| red wallpaper | `rgba(100,27,27,0.88)` |

So the pipeline itself is fine: the palette file regenerates, `compile_css`
transpiles `var(--x)` to `@x` correctly, the stylesheet loads with zero parse
errors, and the text colours *do* shift between runs. Only the island
backgrounds are stuck, and `#333` is suspiciously close to Adwaita-dark's
`#353535` — which would mean GTK is falling back to its own theme and painting
an opaque background behind the semi-transparent islands. Unconfirmed.

**Practical consequence: do not judge the theming from a container screenshot.**
Colours in `--hypr` / `--ui` shots are indicative at best. Everything else the
harness reports is trustworthy.

### Running the session, not just installing it

`--hypr` goes further and starts the desktop. Two levels:

- **`Hyprland --verify-config`** parses `hyprland.lua` and every `config/*.lua`
  it requires, with no compositor and no display. It runs in every mode that
  has Hyprland installed. This is the cheapest possible guard against the
  failure that otherwise only appears as a dead session at the login screen.
- **A nested session.** Hyprland runs as a Wayland *client* of the host
  compositor, so the whole desktop appears in a window. `checks.sh` then waits
  for `hyprctl` to answer, counts the registered binds (and how many lack a
  `desc`, which is what the cheatsheet keys off), waits for `bar.py` and
  `daemon.py`, checks who owns `org.freedesktop.Notifications`, and screenshots
  the result to `artifacts/hyprland.png`.

**`--ui` is the one to use for looking at the desktop.** It does the same thing
and then hands you a shell instead of tearing the session down, so the window
stays up and can be clicked through.

The keybinds are the catch. A nested compositor only receives what the host
does not claim first, and every real bind here is `SUPER`-based — so none of
them ever arrive. `--ui` writes a container-only `config/custom/keybind.lua`
adding **`INSERT` as a leader**: press `INSERT`, then a key.

`INSERT` cannot be a modifier, though `"INSERT + SPACE"` *does* pass
`--verify-config`. Hyprland resolves the unrecognised token to modmask 0, so
that bind ends up firing on bare `SPACE` — a silent mis-bind rather than an
error. It works as a leader via `hl.define_submap` instead, and every bind in
the submap resets it as it fires; a sticky submap swallows all typing, so the
launcher would open and then ignore the keyboard.

Three details that make nesting work:

- The container user is **uid 1000**, matching the usual first host user, or the
  bind-mounted Wayland socket is unreadable. `/run/user/1000` also has to exist
  and be owned by that user *before* docker mounts into it.
- The host socket is mounted as `wayland-host`, not under its real name. The
  nested Hyprland opens **its own** socket in that same directory, and a name
  collision there breaks one or the other. `grim` must then be pointed at the
  nested socket, or it screenshots the host's desktop instead.
- `dbus-run-session`, because the shell daemon claims a bus name and a container
  has no session bus.

`--hypr` passes `--no-aur`: the browser, editor, LSP and SDDM theme have no
bearing on whether the session comes up, and paru's source build alone costs
~3 minutes. `--full` remains the package-fidelity test.

Two traps found building this:

- **`hyprctl` does not discover a running instance.** Without
  `HYPRLAND_INSTANCE_SIGNATURE` it prints *"is hyprland running?"* and exits
  **0** — so a naive check reads as "compositor never started" while the
  compositor is perfectly healthy. Hyprland exports that variable only to its
  own children, so a sibling process has to read the signature back out of
  `$XDG_RUNTIME_DIR/hypr/`.
- **`hl.exec_cmd` swallows its children's stderr.** A shell process that dies
  on startup leaves nothing in Hyprland's log, so `checks.sh` re-runs
  `daemon.py` in the foreground when it is missing, purely to see the error.
- **The notification bus name is acquired asynchronously.** `Gio.bus_own_name`
  returns immediately and the name lands later on the main loop, so a single
  query right after the daemon appears reports the bus as unowned on a perfectly
  healthy session. The check retries for 15s.

Bugs this harness caught that reading the script did not:

- `$USER` is unset in a bare container and when piped from curl. Under `set -u`
  that aborted on the banner line, before anything ran.
- The `archdots_docker` symlink points outside the repo, and stow refuses to
  follow an absolute symlink — it aborted the **entire** stow with a message
  the conflict parser did not recognise, so the script sailed past it into a
  hard failure. Both the ignore entry and a catch-all for unrecognised conflicts
  came out of that.
- `chsh` prompts for a password of its own, stalling an unattended run. It now
  goes through the already-authenticated `sudo`.
- The SDDM theme never built, because `makepkg` cannot install its AUR-only
  `redhat-fonts` dependency. On a machine that already has it installed — every
  machine this was written on — the failure is invisible.
- `config/autorun.lua` ran `fix_dolphin.sh` through a hardcoded
  `/home/chit/archdots/...` path, so it silently did nothing for anyone whose
  clone is elsewhere. It goes through `$HOME/.config/hypr/Scripts/` now, which
  resolves through the stow symlink wherever the repo lives.

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
- [x] Detect the CPU temperature sensor instead of assuming `thermal_zone0`
- [x] Test the installer in a container ([above](#testing-it))
- [ ] Separate the remaining machine-specific bits (per-program configs) —
      `uwsm/env-hyprland`, `hyprpaper.conf` and `hyprlock.conf` are still
      tracked files the installer edits in place
