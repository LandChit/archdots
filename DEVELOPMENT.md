# Development notes

How this setup actually works, why a few things are the way they are, and what
is still on the list. [README.md](README.md) is the tour; this is the manual.

**Contents**

- [Repo layout](#repo-layout)
- [The shell](#the-shell)
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
home/                stowed into $HOME: `stow --dir=<repo> --target=$HOME home`
  .config/
    hypr/            Hyprland — hyprland.lua + config/*.lua, hypridle, hyprlock
      config/custom/   old per-machine overrides location, still loaded (untracked)
    quickshell/simplychit/   the desktop shell, QML (README inside)
    wal/templates/   pywal16 templates — the source of all theming
    alacritty/ eza/ fastfetch/ cliphist/ fontconfig/
    Kvantum/ qt6ct/ kdeglobals    Qt theming
    gtk-3.0/settings.ini          GTK theming — picks the theme in .themes/
    uwsm/            session env (forces Hyprland onto the iGPU)
  .themes/           GTK theme
  .ohmyzsh_custom/   zsh theme (the plugins come from pacman)
  .zshrc
.themes_sddm/        SDDM theme (install.sh copies it into /usr/share/sddm)
kvantum/             Kvantum theme sources
wallpapers/          copied to ~/Pictures/wallpapers
simplychit_docker/     container test harness
install.sh  README.md  DEVELOPMENT.md  CUSTOMIZING.md  TODO.md
```

Only `home/` is stowed. Everything else at the repo root stays in the repo, so
adding a file there needs no ignore list. The root `.stow-local-ignore` is not
read by install.sh: it ignores everything, so an installer from before the move
(which ran `stow .` at the root) links nothing.

User settings are not in the repo at all: they live in `~/.config/simplychit/`
(see [CUSTOMIZING.md](CUSTOMIZING.md)).

`wallpapers/` stays at the root because the picker reads `~/Pictures/wallpapers`
(`wallpaper.directory` in settings.json), not the repo — a `~/wallpapers`
symlink would just be dead weight. `install.sh` copies them across instead.

---

## The shell

A desktop shell written for this repo in [Quickshell](https://quickshell.org)
(QML), at `home/.config/quickshell/simplychit/`; its own
[README](home/.config/quickshell/simplychit/README.md) has the layout, the IPC
targets and how to test it next to a running session. Quickshell is packaged
(`quickshell` in extra), so there is nothing to build: no virtualenv, no pip.

It replaced `fabric_shell` (Python + GTK 3 layer-shell). Most of what that
shell shelled out for — PipeWire, MPRIS, notifications, the tray, UPower,
Hyprland IPC, Wi-Fi, Bluetooth, polkit, PAM — Quickshell has as services, so
the nmcli and bluetoothctl parsing (and the hangs it needed guarding against)
are gone.

**One process**, `qs -c simplychit`, started by `hypr/config/autorun.lua`
through `hypr/config/helpers/shell.lua`. It draws:

| Surface | What it is |
|---|---|
| bar | per monitor: workspaces, special workspaces, title, media, meters, clock; per-screen settings |
| wallpaper | the background layer, per monitor, crossfading; pywal16 re-run on change |
| `launcher` | apps by use; `=` calc, `/` files, `@` windows, `!` run, `?` web, `>` actions |
| `clipboard` | cliphist history, async image thumbnails of any size |
| `emoji` | grid with a group rail, most used first |
| `powermenu` | full-screen scrim: lock / suspend / logout / restart / shutdown |
| `control` | Wi-Fi (with passwords), Bluetooth (with pairing), audio devices and per-app volume, power profiles, tray |
| `notifications` | the daemon, popups, history with DND, the shell's own toasts |
| `calendar` | month grid from the clock island |
| `battery` | status card; low/critical warnings; suspend at `battery.actionPercent` |
| `screenshot` | region / window / screen / delayed, to file **and** clipboard |
| `keybinds` | cheatsheet of every bind, read live from Hyprland |
| OSD | volume, mic and brightness, shown on any change |
| polkit | the agent and its dialog (hyprpolkitagent is the fallback) |
| lock | ext-session-lock + PAM, opt-in (`lock.enabled`); hyprlock otherwise |

Panels open one at a time (`services/Panels.qml`); a keybind is one IPC call,
`qs -c simplychit ipc call panel toggle <name>`. Settings are
`~/.config/simplychit/settings.json` over the defaults in `config/Config.qml`,
reloaded live (keys: [CUSTOMIZING.md](CUSTOMIZING.md)), and edited by the
settings app (`modules/settings/`, SUPER + `,`).

**The Hyprland config reads the same file.** `config/helpers/json.lua` is a
small JSON decoder (Hyprland's Lua has none) and `config/helpers/settings.lua`
loads the file, reporting a broken one and falling back to the defaults.
`keybind.lua` is a table of binds with stable ids, changed by
`keybinds.remap` / `keybinds.disabled` and listed for the settings app in
`~/.cache/simplychit/keybinds.json`; `monitor.lua` applies the active display
profile (`displays`), `input.lua` the known `input` keys. One file, written as
data, so the settings app never generates code and hand edits keep working.

**Idle is the shell's too.** `services/IdleTimers.qml` dims, locks, turns the
screens off and suspends after `idle.ac` / `idle.battery`; hypridle only locks
before sleep and turns the screens on after. `simplychit doctor`
(`home/.local/bin/simplychit`) checks the whole setup; the About page shows it.

**Adding a setting:** declare it in `config/Config.qml` with its default and
a comment, then run `tools/gen-settings-schema.py` to regenerate
`config/settings.schema.json` (the docker checks fail when it is stale).
Allowed values and ranges go in the script's `EXTRA` table; keys only
Hyprland reads go in `HYPR_ONLY`. `simplychit check-settings` validates
against that schema, and `services/SettingsCheck.qml` runs it whenever the
file changes and toasts what it finds.

### The shell is the notification daemon

It owns `org.freedesktop.Notifications`, so anything calling `notify-send` draws
as a shell card and expires on the sender's timeout (5s default; critical waits
for you).

**Never install a second notification daemon.** dunst, mako and swaync each ship
a systemd user service that grabs that bus name at login. The shell cannot
take a name someone else already owns; Quickshell logs it and registers as soon
as the other daemon lets go, but until then its cards never appear. If
notifications go quiet, check the owner first:

```bash
busctl --user list | grep Notifications   # name, owning PID, and process
pgrep -f 'qs -c simplychit'                 # the two PIDs must match
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

### The greeter

`greeter.qml` (shell root) is the login screen for greetd: greetd runs
`env HOME=/var/lib/simplychit/greeter QT_WAYLAND_DISABLE_WINDOWDECORATION=1
cage -s -d -- qs -p /usr/share/simplychit/shell/greeter.qml` (no title bar) as the `greeter` user (whose own
home is `/` on Arch). cage has **no layer-shell**, so it is one `FloatingWindow`, which cage
shows fullscreen. It reuses `modules/lock/LockContent.qml` (`askUser`,
`actions`) and drives `Quickshell.Services.Greetd`: `createSession(user)`, a
`respond()` to each prompt; after a failure Quickshell sends `cancel_session`
itself and greetd answers "Connection refused" (that session is gone), so
`onError` drops the one error that follows an auth failure;
`launch()` with the session's
`Exec` from `/usr/share/wayland-sessions/` on `readyToLaunch`. Last user and
session: `/var/lib/simplychit/greeter/.local/state/simplychit/greeter.json`.

It cannot read the user's home, so `install.sh` (`greeter_copy_files`)
copies the shell to `/usr/share/simplychit/shell/` and the palette and the
wallpaper into `/var/lib/simplychit/greeter/`; `update` refreshes them.

Testing without greetd or a VM: without `GREETD_SOCK` it is a preview.
For the login flow, run it in a nested cage (extract `cage` and
`wlroots0.20` from the mirror into a scratch dir, `LD_LIBRARY_PATH`) with
`GREETD_SOCK` pointing at a fake greetd: greetd's IPC is a native-endian
u32 length and a JSON message each way (`create_session`,
`post_auth_message_response`, `start_session`, `cancel_session`). Type into
it with `wtype` from a script run *inside* cage, so the keys cannot reach
the real desktop. A real boot into it: VM only (TODO.md, phase 6).

## Theming pipeline

### The GTK theme has to be *selected*, not just present

`.themes/` ships the theme; `.config/gtk-3.0/settings.ini` is what chooses it:

```ini
gtk-theme-name=simplychit
gtk-icon-theme-name=breeze-dark
gtk-application-prefer-dark-theme=1
```

Without that file GTK falls back to **Adwaita light**, and the result is a shell
with white panels and grey-on-white text that looks broken rather than
misconfigured — the pywal16 palette is applied correctly on top of a light base.

### The GTK theme follows the wallpaper

`.themes/simplychit/` holds no colours of its own. The palette is pywal16 output:
`wal/templates/colors-gtk.css` renders to `~/.cache/wal/colors-gtk.css`, and
`simplychit sync-palette` (run by the picker) copies it in as `colors.css`
beside each sheet. The shell
itself needs no copy: it reads `~/.cache/wal/colors.json` directly.

It needs its own template because **GTK CSS has no `var()`** — named colours are
`@define-color` and `@name`.

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
  `~/.themes/simplychit/gtk-4.0/gtk.css` instead — which is why that one bundles
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



There is no hardcoded palette. **pywal16** generates colors from the current
wallpaper, and templates in `.config/wal/templates/` push them everywhere:

| Template | Feeds | How |
|---|---|---|
| `colors-hyprland.lua` | borders, shadows | `theme.lua` does `dofile` on `~/.cache/wal/colors-hyprland.lua` |
| *(none: `colors.json`)* | the whole shell | `config/Colours.qml` reads `~/.cache/wal/colors.json`, watched |
| `colors-gtk.css` | GTK 3 + GTK 4 apps | copied next to each `gtk.css` (GTK CSS has no `var()`) |
| `colors-alacritty.toml` | terminal | imported by the alacritty config |
| *(none: `colors.json`)* | hyprlock | `simplychit sync-palette` writes `~/.local/state/simplychit/hyprlock-colors.conf`, which `hyprlock.conf` sources after its own defaults |
| *(pywal16's own `btopwal.theme`)* | btop | copied to `~/.config/btop/themes/simplychit.theme`; install.sh seeds `color_theme` |
| *(none: `colors.json`)* | VS Code | the `dlasagno.wal-theme` extension (install.sh adds it), theme "Wal" |
| *(none: `colors.json`)* | browser | pywalfox (`pywalfox update` in `sync-palette`) and its add-on |
| *(none)* | fastfetch | its keys use ANSI colour 94, so it follows the terminal's palette |

`simplychit sync-palette` makes every copy in the table, and the shell runs it
after each `wal`. A copy is in the state or config folder, never in the
cache: hyprlock's has to exist even when `wal` has not run since an update.

`color4` is the accent throughout — workspace highlight, selected-row glow,
search caret, window border. Every config falls back to a dark neutral palette
when `~/.cache/wal/` is missing, so a fresh install works before the first `wal`
run.

**Hyprland is the one consumer that does not pick up a new palette on its own.**
The shell watches `colors.json` and alacritty re-reads its import on write, but `theme.lua` `dofile`s the palette at
*config-parse* time, so a freshly written one changes nothing until the config is
parsed again. The picker therefore runs `hyprctl reload` after syncing. That is
safe on every wallpaper change because everything in `autorun.lua` hangs off the
`hyprland.start` event, which a reload does not re-fire — nothing is respawned
and the shell is not restarted.

The picker also waits for `wal` to **exit** before syncing rather than sleeping a
fixed interval. A wallpaper pywal16 has no cached scheme for takes around three
seconds to analyse; the old 900 ms guess copied the *previous* palette to every
consumer, which looked exactly like the theming had failed to fire.

#### Why pywal16, and what the extra colours buy

`python-pywal` is unmaintained and was dropped from the Arch repos into the AUR.
The replacement is [`python-pywal16`](https://github.com/eylles/pywal16), which
keeps the `wal` command and the `~/.cache/wal/` layout, so the pipeline above is
unchanged. Two things about it are load-bearing here:

- **`--cols16 dual` is required.** Classic pywal generated 8 colours and copied
  them into slots 9-15, so `color9` was literally `color1`. pywal16 generates a
  distinct bright half instead, which is what `--accent-bright` and the
  `*-bright` status tokens spend. Both callers pass the flag and must stay in
  step: `WAL_ARGS` in `install.sh`, and the `wal` command in the shell's
  `services/Theme.qml`. A run without it rewrites the palette with a
  duplicated bright half and every state that relies on hue separation
  collapses. `wal -R` needs no flag — it restores a cached scheme that already
  carries its generation settings. Be aware that on a near-monochrome wallpaper
  the distinct bright half is a much louder look than classic pywal's; dropping
  the flag in both places goes back.
- **Templates can call functions on a colour**, e.g. `{color4.lighten(10)}`.
  Used for shades that should stay inside the wallpaper's own range — hover
  states and the surface ramp — rather than jumping to another hue.

Sheets should reach for the semantic names (`--accent`, `--accent-bright`,
`--surface`, `--text-muted`, …) rather than `--colorN`, so a palette change is
absorbed in one place. Two traps when editing a template:

- Percent arguments are **integers**. pywal16 strips `.` from the argument, so
  `darken(0.3)` silently means 3%, not 30%.
- `saturate()` **sets** saturation to the value given rather than adjusting it
  (`s = amount` in pywal16's `util.py`), which pins a colour independent of the
  wallpaper. Use `lighten`/`darken` instead.

Colours that must not follow the wallpaper stay hardcoded on purpose — the
critical-battery red `rgb(224, 96, 78)` in the battery card, the OSD and
critical notifications has to read as alarming on every palette, so it is
deliberately not a `colorN`.

The wallpaper picker (`SUPER` + `W`) sets the wallpaper on every monitor (or,
with Shift, the focused one), runs pywal16, copies the GTK palette, reloads
Hyprland, and re-points `~/.local/state/simplychit/wallpaper` so the choice
survives a reboot ([below](#the-wallpaper-is-a-pointer)). The shell draws the
wallpaper itself, crossfading, so hyprpaper is not used.

**The shell recolours in place** because `config/Colours.qml` reads
`colors.json` through a `FileView` with `watchChanges`. No restart, and no
copy of the palette into the shell.

---

## Per-machine config

`hyprland.lua` requires every module in `config/`, then loads the file of the
same name from each override folder, in order. Later calls win, so an override
only restates the part that differs:

```
config/monitor.lua                    committed default — the owner's layout
config/custom/monitor.lua             old location, still loaded (gitignored)
~/.config/simplychit/hypr/monitor.lua   loaded last, wins
```

`~/.config/simplychit/` is outside the repo entirely; `config/custom/` is kept
only so machines set up before the move keep working. User-facing docs:
[CUSTOMIZING.md](CUSTOMIZING.md).

Keybinds do not follow "later wins": binding a combo twice keeps both binds
and fires both. `config/helpers/bind.lua` wraps `hl.unbind` for that
(`bind.rebind`, `bind.remove`). What usually differs: monitor layout and the
workspace rules that name monitors, GPU env vars, `hl.device` blocks (they key
off exact device names), and hardware-bound autostarts like `solaar`.

### Programs that are not Hyprland

Three settings live outside Lua, so `~/.config/simplychit/hypr/` cannot hold them. Each one
uses the escape hatch its own program provides, and in every case the tracked
file stays machine-neutral and `install.sh` never edits it:

| Setting | Committed default | This machine |
|---|---|---|
| `AQ_DRM_DEVICES` (which GPU renders) | `uwsm/env-hyprland` — comments only | `uwsm/env-hyprland.d/10-gpu.sh` |
| Desktop wallpaper | the shell starts from the pointer | `~/.local/state/simplychit/wallpaper`, and `wallpapers.json` beside it for per-monitor ones |
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

`hyprlock.conf` names `~/.local/state/simplychit/wallpaper`, a symlink, rather
than a picture, and the shell starts from it. `install.sh` creates it and the
picker re-points it, so choosing a wallpaper touches nothing tracked — before
this, every wallpaper change rewrote a `path =` line in stowed files and turned
up in `git status`.

A missing pointer is harmless: the shell paints its background colour, and
hyprlock falls back to the `color =` in its `background` block. That is why this is a pointer rather than a
`source =` of a gitignored fragment — **hyprlang treats a missing `source` path
as a config error**, and it validates the path before expanding it, so a glob
over an empty directory fails too (tested with hyprlang 0.6.8). A fresh clone that had not run `install.sh` yet would have started with
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
luac -p ~/.config/simplychit/hypr/*.lua && hyprctl reload
```

---

## Naming keybinds

The cheatsheet (`SUPER` + `/`) is generated from `hyprctl binds -j` every time
it opens, so binds added in `~/.config/simplychit/hypr/keybind.lua` appear with no code
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
  wrong elsewhere until overridden in `~/.config/simplychit/hypr/`. `install.sh` writes a
  starter override from the detected outputs, but the positions in it are a
  left-to-right guess.
- **CPU temperature is detected, not hardcoded.** `thermal_zone0` is not the CPU
  on every machine — on this laptop it is `acpitz`, a chassis probe reading ~20°C
  below the package sensor at `thermal_zone3`, and on other hardware zone0 is
  `INT3400`, which reports a constant 20°C. The shell's `services/CpuTemp.qml` prefers the
  `coretemp`/`k10temp` hwmon and falls back to thermal zones by `type`, never by
  index. If the bar shows `--°C`, no known sensor matched.
- **Some tray icons fall back to a generic glyph.** Apps advertising an icon
  name breeze-dark does not carry get a placeholder in the control centre's
  tray tab; the item stays clickable. (The fabric shell needed a private icon
  theme here, because fabric's tray replaced the process-wide icon search path;
  Quickshell's does not.)
- **Bluetooth devices that need a passkey typed in** still need `bluetoothctl`;
  everything else pairs and connects from the control centre.

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
`install.sh` **and** `home/.config/quickshell/simplychit`, a pair that exists nowhere
else; when piped there is no `BASH_SOURCE` path to resolve, so it clones and
`exec`s the copy on disk with `SIMPLYCHIT_REEXEC=1` guarding against a loop.

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
checklist behind *Custom install* — is the consent: ticking `stow` already means
"yes, link the dotfiles", so asking again mid-run would be asking the same
question twice. `choose_mode()` sets `ASSUME_YES=1` on the way out, and everything after
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
SDDM theme and its `IgnorePkg` pin, the services, stow.

That is also what makes the progress bar honest. `gauge_open()` refuses to raise
unless the run is unattended, so a question can never end up hidden behind it —
`install.sh install` names its mode on the command line, never sees the menu,
and therefore gets dialogs and visible output instead of a bar.

**The output goes to a log, not the screen** — in dialog mode. `run_logged`
sends every command through `log_filter`, which writes each line to
`~/.local/state/simplychit/<mode>-<date>.log` and turns the interesting ones into
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

The helper opens `$SIMPLYCHIT_TTY` rather than `/dev/tty`, resolved once in the
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
- **The kill pattern is anchored to `$HOME`.** `pkill -f fabric_shell/...` (now
  only in `retire_fabric`, for the old shell) matches by path, not by user's
  session, so an installer run with `HOME` pointed somewhere else would happily
  kill the desktop that is running right now. Found the hard way, from a test.

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

### What it does beyond `stow home`

| Step | Why it cannot be a symlink |
|---|---|
| Remove dunst / mako / swaync | they take `org.freedesktop.Notifications` at login and the shell's cards then never appear — see [above](#the-shell-is-the-notification-daemon) |
| Retire the fabric shell | an update across the switch to Quickshell leaves its untracked venv and caches, and maybe its processes — `retire_fabric` removes them, only where git tracks nothing |
| Disable hyprpolkitagent's unit, offer `tlp-pd` | one polkit agent per session (the shell's); TLP's power-profiles service for the control centre |
| oh-my-zsh | `.zshrc` sources it; installed with `--keep-zshrc` or the installer overwrites the symlink stow just made |
| Copy wallpapers to `~/Pictures/wallpapers` | that is where the picker looks |
| First `wal -i` run | otherwise the shell starts on its fallback palette |
| `gsettings` for blueman | dconf is a binary database — [see above](#settings-that-cannot-be-stowed) |
| The greeter (default) or the SDDM theme (`--no-greeter`) | lives in `/usr/share`, `/var/lib` and `/etc` — [the greeter](#the-greeter), [the SDDM theme](#the-sddm-theme) |
| Enable `greetd` (or `sddm`), `NetworkManager`, `bluetooth` | systemd, not files |

`paru` is built **from source**, not `paru-bin`. The binary package is linked
against one libalpm soname; the moment pacman bumps it, paru dies with
`error while loading shared libraries: libalpm.so.N` and every AUR install in
the script fails with it. Compiling links against the pacman actually installed.
The script also treats an existing-but-broken paru as absent and rebuilds it.

The script refuses to run as root. `stow`, the shell and every `gsettings` call
have to be the user's; it calls `sudo` only for pacman and `systemctl enable`.

### Machine-specific detection

Three things are detected, shown for review, and only then written:

| What | Detected from | Written to |
|---|---|---|
| GPU order (`AQ_DRM_DEVICES`) | `/sys/class/drm/card*/device/vendor` — anything that is not `0x10de` goes first, so Hyprland lands on the iGPU | `.config/uwsm/env-hyprland.d/10-gpu.sh` |
| Monitor layout | `hyprctl monitors -j` when Hyprland is up, otherwise the connected connectors under `/sys/class/drm/card*-*` — the sysfs names are the same names Hyprland uses | `~/.config/simplychit/hypr/monitor.lua` |
| Wallpaper | the first file in `~/Pictures/wallpapers`, and only when no pointer exists yet | `~/.local/state/simplychit/wallpaper` |

None of those are tracked files, so a finished install leaves `git status` clean
([above](#programs-that-are-not-hyprland)).

The shell draws one wallpaper window per screen it finds, so a dock, a
different cable or a nested session still gets a wallpaper; a per-monitor
choice keyed by a connector name that no longer exists just falls back to the
main one.

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
`~/.config/simplychit/hypr/monitor.lua`, `env-hyprland.d/10-gpu.sh`, the wallpaper pointer —
so an install leaves the worktree clean and nothing detected here can be pushed
onto anybody else.

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
| the greeter | `/etc/sddm.conf.d/10-simplychit.conf` | selects the theme and sets `QML2_IMPORT_PATH` |

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
`update_repo` (which re-runs the new install.sh if the pull changed it),
`update_packages`, `stage_stow`, `stage_user_dir`, `retire_fabric`,
`stage_wallpapers` and `restart_shell`, and deliberately skips the machine
detection — the GPU, monitor and wallpaper answers were settled at install time,
and rewriting them on every update would keep asking about hardware that has not
changed. `./install.sh install --skip-packages` is the way to redo them after a
hardware change.

**The stash is the whole trick.** The machine-specific values are out of the
repo now, and the rendered palettes are gitignored, but an installed clone can
still be dirty for reasons its owner never chose — and `git pull --ff-only` refuses to run in a dirty tree. `update_repo` stashes with `-u`, pulls, then pops. If
the pop conflicts the stash is **kept**, the run continues, and the summary says
where to find it; losing a machine's GPU pin to a silent `stash drop` would be
much worse than a merge conflict.

`update_packages` is `pacman -S --needed` over the same package lists, which is
a no-op for everything already installed and picks up only what the repo has
gained since the last run. A full `-Syu` is asked separately and defaults to no:
upgrading the system is the user's decision, not a side effect of updating some
dotfiles.

`restart_shell` mirrors `hypr/config/helpers/shell.lua` — kill both long-lived
modules, re-sync the pywal16 colours, start them again, all in one shell so that
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
`simplychit_docker` symlink:

```bash
cd simplychit_docker
./runscript.sh --fast     # no packages, ~10s — structure, stow, detection
./runscript.sh --full     # every package, paru, the theme
./runscript.sh --hypr     # starts Hyprland and the shell for real, screenshots it
./runscript.sh --ui       # same, but leaves it up so you can click around
./runscript.sh            # interactive shell with the repo at ~/simplychit
./runscript.sh -- --yes --no-aur   # anything after -- goes to install.sh
```

The checks themselves live in `checks.sh`, mounted into the container rather
than inlined into `docker run bash -c '…'` — they need both quote characters,
and nesting those in one shell string truncates the script silently.

The repo is mounted **read-only** and copied to a writable path inside, so a
test cannot modify the working tree. The copy strips `config/custom/*.lua`
first — without that the test inherits the host's machine-specific
files and reports `monitor.lua already exists`, which is the opposite of what a
new machine sees.

### The container is not 1:1 with a real session — yet

Package resolution, stow folding, the AUR path and the
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
  `desc`, which is what the cheatsheet keys off), waits for `qs -c simplychit`,
  prints any errors from its log, lists its `simplychit-*` layers, checks that it
  owns `org.freedesktop.Notifications`, and screenshots the result to
  `artifacts/hyprland.png`. A re-theme through `ipc call wallpaper set` then
  checks the palette changes in place.

**`--ui` is the one to use for looking at the desktop.** It does the same thing
and then hands you a shell instead of tearing the session down, so the window
stays up and can be clicked through.

The keybinds are the catch. A nested compositor only receives what the host
does not claim first, and every real bind here is `SUPER`-based — so none of
them ever arrive. Every nested run writes a container-only
`~/.config/simplychit/hypr/input.lua` (from `ui-input.lua`) that maps **Caps Lock
to an extra Super** inside the container, so the real binds work when pressed
with Caps instead.

Three details that make nesting work:

- The container user is **uid 1000**, matching the usual first host user, or the
  bind-mounted Wayland socket is unreadable. `/run/user/1000` also has to exist
  and be owned by that user *before* docker mounts into it.
- The host socket is mounted as `wayland-host`, not under its real name. The
  nested Hyprland opens **its own** socket in that same directory, and a name
  collision there breaks one or the other. `grim` must then be pointed at the
  nested socket, or it screenshots the host's desktop instead.
- `dbus-run-session`, because the shell claims a bus name and a container has no
  session bus.

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
- **`hl.exec_cmd` swallows its children's stderr.** A shell that dies on
  startup leaves nothing in Hyprland's log, so `checks.sh` reads the shell's own
  log with `qs log -c simplychit`.
- **The notification bus name is acquired asynchronously**, so a single query
  right after the shell appears can report the bus as unowned on a perfectly
  healthy session. The check retries for 15s.

Bugs this harness caught that reading the script did not:

- `$USER` is unset in a bare container and when piped from curl. Under `set -u`
  that aborted on the banner line, before anything ran.
- The `simplychit_docker` symlink points outside the repo, and stow refuses to
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
  `/home/chit/simplychit/...` path, so it silently did nothing for anyone whose
  clone is elsewhere. It goes through `$HOME/.config/hypr/Scripts/` now, which
  resolves through the stow symlink wherever the repo lives.

### Still not handled

- `hl.device` blocks in `~/.config/simplychit/hypr/input.lua` — they key off exact device
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
- [x] Bluetooth pairing in the control centre (devices needing a typed passkey
      still need `bluetoothctl`)
- [x] The shell rewritten in Quickshell (TODO.md, phases 3 and 4)
- [x] Rewrite the install script — `install.sh` ([above](#the-install-script))
- [x] Detect the CPU temperature sensor instead of assuming `thermal_zone0`
- [x] Test the installer in a container ([above](#testing-it))
- [x] Separate the remaining machine-specific bits (per-program configs) —
      `uwsm/env-hyprland` keeps its values in `env-hyprland.d/`, and
      `hyprlock.conf` and the shell use a wallpaper pointer instead of a
      picture ([above](#programs-that-are-not-hyprland))
