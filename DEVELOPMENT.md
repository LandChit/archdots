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
gtk-theme-name=archdots
gtk-icon-theme-name=breeze-dark
gtk-application-prefer-dark-theme=1
```

Without that file GTK falls back to **Adwaita light**, and the result is a shell
with white panels and grey-on-white text that looks broken rather than
misconfigured — the pywal palette is applied correctly on top of a light base.

### The GTK theme follows the wallpaper

`.themes/archdots/` holds no colours of its own. The palette is pywal output:
`wal/templates/colors-gtk.css` renders to `~/.cache/wal/colors-gtk.css`, and the
wallpaper picker copies it in as `colors.css` beside each sheet, the same way it
copies `colors-fabric.css` into the shell's `css/`.

It needs its own template because **GTK CSS has no `var()`** — named colours are
`@define-color` and `@name`, so the shell's `colors-fabric.css` cannot be reused.

The two halves are built on opposite principles, and the reason matters:

- **GTK 3** (`gtk-3.0/gtk.css`) is hand-written. There is no libadwaita
  underneath, so a theme is expected to specify everything.
- **GTK 4** (`gtk-4.0/`) vendors libadwaita's own stylesheet as `adw-base.css`
  and only recolours it. GTK 4 loads exactly *one* theme stylesheet, so a
  partial one does not add to libadwaita's — it **replaces** it, taking every
  metric with it. A hand-written sheet here collapsed AdwActionRow from 50px to
  36px, flattened boxed-list cards and left tooltips rendering light-on-white.
  Refresh `adw-base.css` and `assets/` after a libadwaita update; the commands
  are in the header of `gtk-4.0/gtk.css`.

`gtk-4.0/overrides.css` is the actual theme: it sets the ~40 CSS custom
properties libadwaita paints from (`--window-bg-color`, `--accent-bg-color`, …).
Overriding those variables rather than the rules that use them is the seam
libadwaita supports. **Nothing structural belongs there** — libadwaita's metrics
are load-bearing.

Which file an app reads depends on where it runs, and there are two paths:

- **Host apps** load `~/.config/gtk-4.0/gtk.css`, which imports `overrides.css`
  alone. libadwaita has already given them the rules — on this machine it even
  forces `gtk-theme-name` to `Adwaita-empty` so a custom theme cannot displace
  it — so only the colour is missing.
- **Flatpaks** get nothing from `~/.config` by default, and read
  `~/.themes/archdots/gtk-4.0/gtk.css` instead — which is why that one bundles
  libadwaita's whole sheet. `~/.themes` reaches them because the global flatpak
  override grants it (`flatpak override --user --show`) and because most app
  manifests request it themselves.

`xdg-config/gtk-4.0` *can* be granted too, and the global override does grant
it — flatpak resolves the stow symlink and mounts the real directory. But it
mounts it inside the app's **per-app home**, and that has a sharp edge:

```
~/.var/app/<app-id>/.config/gtk-4.0/gtk.css      ← where the sandbox sees it
```

so a relative `../../.themes/…` import from that file climbs to
`~/.var/app/<app-id>/` and fails. GTK reports it as a warning on stderr and
carries on, loading the sheet **with no colours at all** — which looks exactly
like "the theme did not apply to flatpaks", while the host stays perfect.
Everything `.config/gtk-4.0/gtk.css` imports therefore lives beside it, copied
in by `install.sh`; nothing there may reach across to `~/.themes`.

`flatpak run --command=gjs --filesystem=home <app-id> probe.js` is the way to
see this — the sandbox prints the failing import path, which no amount of
looking at the host filesystem will reveal.

Two traps worth remembering:

- **Nested `@import` resolves against the entry file's directory**, not the
  importing file's. That is why the picker syncs the palette to *three* places,
  and why `overrides.css` contains no imports of its own — so it resolves the
  same whichever entry point pulls it in.
- **`alpha()` multiplies an existing alpha, it does not replace it.** Wrapping
  an already-translucent surface in another `alpha()` quietly compounds.

Icon names are worth checking rather than assuming — a lesson from the GTK 3
sheet. GTK asks for `check-symbolic`, which breeze-dark does not ship, so a
checked box rendered as a blank square until it named `object-select-symbolic`
instead. And breeze-dark's `radio-symbolic` is a picture of a radio *receiver*,
so the radio dot is drawn with a gradient rather than looked up at all.
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
pywal, copies the palette into `fabric_shell/css/`, and re-points
`~/.local/state/archdots/wallpaper` so the choice survives a reboot
([below](#the-wallpaper-is-a-pointer)).

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

### Programs that are not Hyprland

Three settings live outside Lua, so `config/custom/` cannot hold them. Each one
uses the escape hatch its own program provides, and in every case the tracked
file stays machine-neutral and `install.sh` never edits it:

| Setting | Committed default | This machine |
|---|---|---|
| `AQ_DRM_DEVICES` (which GPU renders) | `uwsm/env-hyprland` — comments only | `uwsm/env-hyprland.d/10-gpu.sh` |
| Desktop wallpaper | `hypr/hyprpaper.conf` — names the pointer | `~/.local/state/archdots/wallpaper` |
| Lock screen wallpaper | `hypr/hyprlock.conf` — names the same pointer | the same symlink |

**uwsm sources a directory.** `/usr/lib/uwsm/prepare-env.sh` calls `source_file`
on `env-hyprland` and then `source_dir` on `env-hyprland.d`, sourcing every file
in it in `ls` order. That is a supported drop-in, not a trick: a missing
directory is skipped silently, so a machine that needs no GPU pin has no file.
`install.sh` writes `10-gpu.sh` there only when it finds more than one GPU, and
*removes* a stale one when it finds a single GPU — a pin left over from other
hardware names a card that may no longer exist.

Do not put a `README.md` in that directory the way `config/custom/` has one:
`source_dir` sources everything, and shell would choke on the markdown.

### The wallpaper is a pointer

`hyprpaper.conf` and `hyprlock.conf` name `~/.local/state/archdots/wallpaper`,
a symlink, rather than a picture. `install.sh` creates it and the picker
re-points it, so choosing a wallpaper touches nothing tracked — before this,
every wallpaper change rewrote a `path =` line in two stowed files and turned up
in `git status`.

Both programs also degrade well if the pointer is missing: hyprpaper logs
`Failed to resolve path` and carries on, and hyprlock falls back to the `color =`
in its `background` block. That is why this is a pointer rather than a
`source =` of a gitignored fragment — **hyprlang treats a missing `source` path
as a config error**, and it validates the path before expanding it, so a glob
over an empty directory fails too (tested with hyprpaper 0.8.4 / hyprlang
0.6.8). A fresh clone that had not run `install.sh` yet would have started with
a broken config.

`install.sh` only ever creates a *missing* pointer. An existing one is the
choice made since the install, and an update quietly resetting it to whatever
sorts first would undo it.

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

- **GTK transparency is not uniform.** The theme makes popovers, menus, tooltips
  and OSD surfaces translucent but leaves app windows opaque, so an app that
  paints its own chrome can still end up with an opaque panel next to a
  translucent one.
- **Dolphin's list view is broken** under Kvantum `KvGlass`. Use icon view.
- **The GPU pin names DRM device paths, and those are not stable.**
  `env-hyprland.d/10-gpu.sh` forces Hyprland onto the iGPU by listing
  `/dev/dri/cardN` in order, and card numbering can change between boots. If a
  session ever comes up on the wrong GPU, re-run `install.sh` or replace the
  paths with stable ones from `/dev/dri/by-path/`
  ([above](#programs-that-are-not-hyprland)).
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

**A dialog run asks once and then gets on with it.** The menu — and the
checklist behind *Custom install* — is the consent: ticking `venv` already means
"yes, build the venv", so asking again mid-run would be asking the same question
twice. `choose_mode()` sets `ASSUME_YES=1` on the way out, and everything after
that takes the answer it was given. `--no-gui` is the mode that stops at each
step.

Seven questions are exempt, because a default would be answering for you:

| Still asked | Why |
|---|---|
| Which monitor is primary, and `monitor.lua` | only you know which screen you look at, and the generated positions are a guess. Drawn as a `--radiolist` of every detected output, including when there is only one — seeing what the installer found, and what it calls it, is the point |
| blueman's plugins | a preference with no safe default — one of the answers costs auto-reconnect |
| Restart the shell now (update) | it interrupts the session you are using |
| Move clashing dotfiles to a backup | they are files you already had |
| Remove dunst / mako / swaync | it uninstalls something you chose |
| The GPU pin, before it is written | hardware-specific and easy to get wrong |
| `pacman -Syu` during an update | upgrading the system is not part of updating dotfiles |

They go through `interactive`, which lowers the bar, restores `ASSUME_YES` to
what the *command line* asked for, puts the question up, and raises the bar
again where it left off. Prompts that answer on stdout run inside `$( )` — a
subshell, where pausing the gauge would pause a copy while the real one keeps
drawing — so those bracket the substitution with `prompt_begin`/`prompt_end`
instead. With a real `--yes`, nothing asks anything.

Everything else is foregone once the run has started: the utilities, the AUR
packages, the flatpaks (on by default), oh-my-zsh, zsh as the login shell, the
SDDM theme and its `IgnorePkg` pin, the services, stow, the venv.

That is also what makes the progress bar honest. `gauge_open()` refuses to raise
unless the run is unattended, so a question can never end up hidden behind it —
`install.sh install` names its mode on the command line, never sees the menu,
and therefore gets dialogs and visible output instead of a bar.

**The output goes to a log, not the screen** — in dialog mode. `run_logged`
sends every command through `log_filter`, which writes each line to
`~/.local/state/archdots/<mode>-<date>.log` and turns the interesting ones into
gauge text; the last nine logs are kept. In `--no-gui` mode the same function
`tee`s to the terminal instead, because there the output *is* the interface.
Either way the log is written, and the path is printed at the end and on any
fatal error.

**sudo never prompts on the terminal while the bar is up.** It did once, and it
is worth describing, because it looks like a hang rather than a question:
`makepkg -si` ran `sudo pacman -U` after a long paru build, sudo drew
`[sudo] password for you:` straight over the gauge, and the keystrokes went to
whiptail — which owns the terminal in raw mode — so sudo read nothing and
answered *Sorry, try again*.

Two things stop it now. The timestamp is authenticated up front and kept warm
by a loop every 45 seconds, so the question usually never arises; and if it
does, `sudo_askpass_setup` has pointed `SUDO_ASKPASS` at a helper that

1. `SIGSTOP`s the gauge — stopped, not killed, so it can be resumed and cannot
   repaint over the box while the box is up,
2. shows a proper `--passwordbox`,
3. `SIGCONT`s the gauge and leaves a flag file behind.

`run_logged` sees that flag when the command returns and redraws the bar from
scratch, because a resumed newt does not repaint its own frame — it would carry
on writing text into a box that is no longer there.

The helper opens `$ARCHDOTS_TTY` rather than `/dev/tty`, resolved once in the
parent by `current_tty()` (`tty`, else `/proc/$$/fd/{1,2}`, else `ps -o tty=`,
which between them cover being piped from curl). `/dev/tty` is by definition the
*controlling* terminal, and a child detached from one cannot open it at all —
`No such device or address`. A helper that cannot find a terminal exits non-zero
rather than handing sudo an empty password, so sudo fails once and says why
instead of retrying three times in silence.

### makepkg escalates with `sudo -k`

This one survived two attempted fixes, because every symptom pointed somewhere
else:

```
Building paru from source — ==> ERROR: Could not resolve all dependencies
```

No password prompt, no sudo error, just makepkg apparently unable to find
`cargo` — on a fresh install, where `rust` is genuinely absent. The same build
in `--no-gui` mode worked, and asked for the password on the way. That was the
tell.

`run_pacman` in `/usr/bin/makepkg` builds its command as `sudo -k pacman …`.
The `-k` is deliberate: it discards the cached credentials, so **every** pacman
call makepkg makes demands a freshly typed password, however recently you
authenticated. Nothing the installer does with timestamps or keepalive loops can
change that. On a terminal you type it and move on; behind a progress bar the
ask lands somewhere invisible, sudo fails, and makepkg reports the *consequence*
— a dependency it could not install — rather than the cause.

So makepkg is no longer given anything to escalate for:

| Step | Who runs it |
|---|---|
| build dependencies (`cargo`, `git`, …) | us, `pacman -S --needed`, before makepkg starts |
| the build | `makepkg -s --noconfirm` — note the absent `-i` |
| installing the built package | us, `pacman -U` |

`pkgbuild_deps()` reads `depends` and `makedepends` out of the PKGBUILD and
trims version constraints, because pacman wants `rust`, not `rust>=1.70`. It
drops soname entries such as `libalpm.so=15-64`: those are not package names,
and a single unknown target makes pacman abort the whole transaction, taking the
real dependencies down with it. `-s` stays on the build as a safety net for
anything the list misses. The SDDM theme, the other thing built from an AUR
PKGBUILD here, gets the same treatment.

**A `sudo` shim covers whatever still escalates.** paru runs pacman itself, and
there is no `-A` to add to a call this script does not make. `sudo_askpass_setup`
writes a `sudo` into a temp directory at the front of `PATH`: it drops a leading
`-k`, adds `-A` if it is not already there, and passes everything from the first
non-option onwards through untouched, so `sudo grep -k foo` keeps its `-k`.
Dropping `-k` is what lets the session we already authenticated stay usable;
adding `-A` is what sends any password that genuinely is needed to the dialog
rather than to a terminal the bar owns. The script's own calls go through
`"${SUDO[@]}"`, which is plain `sudo` — the shim supplies the rest.

In `--no-gui` mode none of this exists: no helper, no shim, `SUDO` stays
`(sudo)`, and sudo prompts on the terminal, which is exactly where you are
looking.

Five details are load-bearing:

- **whiptail's gauge renders only the first line** of an update and does no
  escape processing — a three-line update shows line one and silently drops the
  rest (tested). So `gauge_body()` composes one line, `step — detail`, trimmed
  to 68 columns, and the package counter is parsed out of pacman's own
  `( 12/692) installing glibc-common` to fill it.
- **The kill pattern is anchored to `$HOME`.** `pkill -f fabric_shell/...` matches
  by path, not by user's session, so an installer run with `HOME` pointed
  somewhere else will happily kill the desktop that is running right now. Found
  the hard way, from a test.

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
- **The key hints are part of the text.** newt has a help line along the bottom
  of the screen for exactly this — the `<Tab>/<Alt-Tab> between elements` bar
  you have seen in Anaconda — and whiptail does not expose it. Writing it to the
  last terminal row by hand scrolls newt's screen and breaks the box, so the
  `KEYS_*` strings go inside each dialog as its last line instead.

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
| GPU order (`AQ_DRM_DEVICES`) | `/sys/class/drm/card*/device/vendor` — anything that is not `0x10de` goes first, so Hyprland lands on the iGPU | `.config/uwsm/env-hyprland.d/10-gpu.sh` |
| Monitor layout | `hyprctl monitors -j` when Hyprland is up, otherwise the connected connectors under `/sys/class/drm/card*-*` — the sysfs names are the same names Hyprland uses | `config/custom/monitor.lua` |
| Wallpaper | the first file in `~/Pictures/wallpapers`, and only when no pointer exists yet | `~/.local/state/archdots/wallpaper` |

None of those are tracked files, so a finished install leaves `git status` clean
([above](#programs-that-are-not-hyprland)).

`hyprpaper.conf` ships with an **empty** `monitor =`, which means *every
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

Everything the script generates is gitignored or outside the repo altogether —
`config/custom/monitor.lua`, `env-hyprland.d/10-gpu.sh`, the wallpaper pointer —
so an install leaves the worktree clean and nothing detected here can be pushed
onto anybody else. The one tracked file still written is
`fabric_shell/css/colors-fabric.css`, the pywal palette, which the picker
rewrites too.

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

**The stash is the whole trick.** The machine-specific values are out of the
repo now, but `colors-fabric.css` is still a tracked file that pywal rewrites
on every wallpaper change, so an installed clone can be dirty for reasons its
owner never chose — and `git pull --ff-only` refuses to run in a dirty tree. `update_repo` stashes with `-u`, pulls, then pops. If
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
- [x] Separate the remaining machine-specific bits (per-program configs) —
      `uwsm/env-hyprland` keeps its values in `env-hyprland.d/`, and
      `hyprpaper.conf` / `hyprlock.conf` name a wallpaper pointer instead of a
      picture ([above](#programs-that-are-not-hyprland))
