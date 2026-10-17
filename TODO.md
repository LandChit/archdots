# To do

Feature numbers (1, C1, …) refer to the sections in [MISSING.md](MISSING.md).
MISSING.md now holds only what is not built, all marked currently undesired;
move an item here before starting it.

Work through the phases in order. Each phase builds on the one before it.

## Phase 1: current dots, low risk

Changes that work in the current dots, before any of the rewrite.

- [x] **Drop the git submodules** (done)
  - `zsh-syntax-highlighting` and `zsh-autosuggestions` are packages in the
    official Arch repos. Install them with pacman, source them from
    `/usr/share/zsh/plugins/`, and remove `.gitmodules`.
  - This also removes the need for `git clone --recursive`. Neither
    submodule is downloaded in the current checkout.
  - [.zshrc:25](home/.zshrc#L25) loads both through oh-my-zsh's `plugins=(...)`.
    Remove them from that list and source the packaged files instead, with
    syntax highlighting last (it has to wrap every widget defined before it):
    ```zsh
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    ```
- [x] **2. Polkit agent** (done): install.sh enables the `hyprpolkitagent`
  user unit and autorun.lua starts it. The themed dialog moved to phase 4.
- [x] **1. Idle management and auto-lock** (done): hypridle (or Quickshell's idle
  monitor), lock → DPMS off → suspend, separate AC/battery timeouts, idle
  inhibit toggle
  - [hypridle.conf](home/.config/hypr/hypridle.conf): dim/lock/screens off/suspend
    at 2.5/5/5.5/30 min on AC, 1/2/2.5/10 min on battery, lock before sleep.
    Moved into the shell in phase 5
    ([IdleTimers.qml](home/.config/quickshell/simplychit/services/IdleTimers.qml),
    `idle.ac` / `idle.battery` in settings.json, set from the Idle page);
    hypridle now only locks before sleep. power-source.sh is gone.
  - Inhibit toggle: SUPER+SHIFT+I,
    [idle-inhibit.sh](home/.config/hypr/Scripts/idle-inhibit.sh) (a systemd idle
    inhibitor). A bar indicator for it comes with the new bar (phase 4).
- [x] **Defaults layer + user layer for every config** (done for the current dots)
  - Hyprland: already done ([config/custom/](home/.config/hypr/config/custom/README.md))
  - alacritty: done. `~/.config/simplychit/local/alacritty.toml`, imported last.
    Alacritty loads the importing file last, so the defaults moved to
    `simplychit.toml` and `alacritty.toml` is only the import list.
  - zsh: done. `~/.config/simplychit/local/zshrc` (`~/.custom.zsh` still read),
    sourced before the plugins so syntax highlighting wraps its widgets.
  - GTK 4: done. `@import "user.css";` at the end of `gtk.css`
  - GTK 3: done. `~/.config/gtk-3.0/gtk.css` is the user file (GTK 3 loads it
    over the theme by itself, no import needed)
  - install.sh `stage_user_dir` writes a commented stub for each, only if missing
  - Shell: moved to phase 3 (`Config.qml`)

## Phase 2: repo and config layout

Goal: a user can change anything without editing a tracked file, and
updates never overwrite their changes.

- [x] **One user folder for everything editable: `~/.config/simplychit/`** (done)
  - `settings.json` (shell), `monitors.lua`, `keybinds.lua`, `env.lua`,
    `local/` for alacritty/zsh/gtk user files
  - Never tracked, never written by the installer or updates (create
    commented stubs once if missing, then leave them alone)
  - As built: Hyprland overrides are `hypr/<module>.lua`, named like the
    defaults in `config/` (`hypr/monitor.lua`, `hypr/keybind.lua`,
    `hypr/environment.lua`, …). `config/custom/` is still read first, for
    machines set up before the move. install.sh writes `hypr/monitor.lua`
    and a `hypr/keybind.lua` stub. `local/` holds zshrc and alacritty.toml.
    GTK files stay in `~/.config/gtk-{3,4}.0/` (GTK only reads them there).
  - `settings.json`: comes with the shell (phase 3), nothing reads it yet
- [x] **Overrides can remove defaults, not just add** (done)
  - Keep defaults such as keybinds as a data table. The user file gets the
    table to edit before anything is applied, so it can delete or rebind a
    default (today's `custom/` overrides can only add or replace).
  - As built: no table needed. `hl.unbind(combo)` works under the Lua config,
    so [helpers/bind.lua](home/.config/hypr/config/helpers/bind.lua) has
    `bind.remove(combo)` and `bind.rebind(combo, action, opts)`. Plain
    re-binding was never "replace": Hyprland keeps both binds and fires both.
  - The keybinds data table is still wanted for the settings app's Keybinds
    page (phase 5).
- [x] **Separate stowed files from repo-only files** (done)
  - Move the stowable tree into `home/` and deploy with `stow -d . -t ~ home`
  - Installer, docs, Docker tests, wallpapers stay at the repo root
  - `.stow-local-ignore` is then no longer needed
  - As built: `.config`, `.themes`, `.ohmyzsh_custom`, `.zshrc` are in `home/`;
    `kvantum/` and `.themes_sddm/` stay at the root (`stow .` had been linking
    them, and CLAUDE.md/TODO.md, into `$HOME`). The root `.stow-local-ignore`
    is kept as a guard that ignores everything, so an old installer's `stow .`
    is a no-op. install.sh moves untracked leftovers into `home/`, removes old
    links, and `update` re-runs itself when the pull changed install.sh.
  - Existing install (`~/archdots`): after pulling across the move, run the
    new `./install.sh update` before logging out (README.md).
- [x] **Mark generated files** (done)
  - Header on every rendered pywal16 template: `GENERATED from
    wal/templates/<name>, edit the template, not this file`
  - Generated output only in cache/state folders, never next to user files
  - As built: all four templates carry the header, and the copies inherit it.
    Output is in `~/.cache/wal/`, except copies GTK needs in its own folders
    (`~/.themes/simplychit/gtk-*/colors.css`, `~/.config/gtk-4.0/colors.css`:
    GTK cannot import from the cache, and flatpaks only see that folder) and
    fabric's `css/colors-fabric.css`, which goes with the fabric shell (phase 4).
    All copies are gitignored.
- [x] **Write CUSTOMIZING.md** (done)
  - A "to change X → edit Y" table: terminal → `keybinds.lua`, monitor layout →
    `monitors.lua`, hide the battery widget → `settings.json`, …
  - As built: [CUSTOMIZING.md](CUSTOMIZING.md). Shell settings (bar widgets)
    and idle timeouts are listed as "not yet": they come with `settings.json`
    and the settings app (phases 3–5).

## Phase 3: Quickshell skeleton

These shape everything below. The feature items should be built in the new
shell, not added to `fabric_shell` first.

- [x] **Port the shell from fabric to Quickshell (QML)** (done)
  - Quickshell has built-in services for most of what `fabric_shell` shells
    out for: PipeWire, MPRIS, notifications, system tray, UPower, Hyprland
    IPC, a session lock (`WlSessionLock` + PAM) and greetd.
  - Keep the overlay → IPC model: `ctl.py` over a socket becomes
    `qs ipc call <target> <action>`.
  - As built: every fabric surface ported (phase 4), `fabric_shell` removed,
    `hypr/config/helpers/shell.lua` drives `qs -c simplychit`. install.sh drops
    the venv and fabric's packages and cleans up after the old shell on update
    (`retire_fabric`). `qs -c simplychit ipc show` lists every IPC target.
- [x] **Shell defaults + user layer** (moved from phase 1, done): defaults shipped
  inside the shell, user `settings.json` merged over them
  - `config/Config.qml`. Live reload on save. `Config.set()` writes only the
    changed key and keeps unknown keys; `writeAdapter()` must not be used
    (it drops unknown keys and writes every default, on quickshell 0.3.2).
    An unparsable file is left alone. Keys documented in CUSTOMIZING.md.
- [x] **Lay out the new shell as folders in this repo, not submodules** (done)
  - As built: in `home/.config/quickshell/simplychit/` rather than `shell/`, so
    stow deploys it where `qs -c simplychit` looks. `services/hyprland` is
    `services/Hypr.qml`; Wi-Fi and Bluetooth use Quickshell's own services
    directly. See its README.md.
  - `shell/services/`: audio, network, bluetooth, battery, mpris,
    notifications, hyprland (state and signals, no UI)
  - `shell/modules/`: bar, launcher, control centre, notifications, OSD,
    lock screen, greeter, power menu (one folder per surface)
  - `shell/widgets/`: shared building blocks (panel, list row, slider, toggle)
  - `shell/config/`: defaults, settings loading, colours
  - The components share code and the colour file, so separate repos would
    turn most changes into multi-repo commits. Split out the shell only if it
    should be usable without these dots, and then ship it as a package
    (AUR), not a submodule.

## Phase 4: port surfaces and their features

Each surface is ported to the new shell together with the features that
belong to it. Done, apart from checking it all on a real session (last item).

- [x] **2. Themed polkit dialog** (moved from phase 1, done): replace
  `hyprpolkitagent` with a Quickshell polkit dialog in the shell's theme
  - `modules/polkit/PolkitDialog.qml`. install.sh disables hyprpolkitagent's
    unit; autorun.lua starts it only if the shell's agent has not registered.
- [x] **6. Launcher modes** (done): calculator, file search, open windows, run command
  - `=` calc (also plain arithmetic), `/` files (fd), `@` windows, `!` run,
    `?` web. `qs -c simplychit ipc call launcher open "@"` opens straight into one.
- [x] Launcher highlights the result Enter opens as soon as you type
  (SOMETING_OFF.md): `selectOnSearch` on ListPanel. Fixed on the way:
  the ListView reset `currentIndex` to 0 after each rebuild, so with the
  web row on top Enter searched the web instead of opening the best app.
- [x] The first arrow press in a list panel highlights the current pick
  instead of stepping past it (Down with no query went to row 2).
- [x] Restart-shell bind works in one press: `shell.restart()` waits for the
  old instance to exit; `qs kill` returns early and `-n` silently refused.
- [x] Region recording (SUPER+SHIFT+R, menu) shows slurp again: a Process
  kept slurp's stdin open and slurp waited on it for preset boxes.
- [x] A panel closes when a window opens, so nm-applet's Wi-Fi password
  (or blueman's PIN) can take the keyboard; the Wi-Fi page asks for a
  missing password itself when there is no agent (NoSecrets).
- [x] Stay awake on/off is a toast, not a notification (Events.qml).
- [x] Idle dim dims external monitors too (DDC/CI via ddcutil), saving
  each level in `$XDG_RUNTIME_DIR/simplychit-dim` and restoring it.
- [x] `simplychit` is found on a fresh install: `~/.local/bin` is on PATH
  from uwsm's `env-hyprland` (the session) and `.zshrc` (TTY, ssh). It had
  only been in the owner's own local/zshrc, carried over from an old .zshrc.
- [x] The launcher (and the clipboard, emoji and wallpaper panels, all
  `SearchPanel`) hangs level with the control centre, 46 px from the top,
  instead of 18 px.
- [x] Brightness is per screen: each screen keeps its own level, so
  changing the external one no longer starts from the laptop panel's.
  `brightness.linked` (Settings → Displays, default off) sets every screen
  together. The control centre has a slider per screen (one when linked);
  writes are queued per screen so a drag's last value lands. Fixed on the
  way: an "Invalid display" in `ddcutil detect` took the previous display's
  number, and a read during the idle dim's restore took the dimmed level
  (reads now wait on the dim's lock). The idle dim itself is unchanged.
- [x] Picking a wallpaper always changes the picture, not only the colours:
  Background.qml's back slot could still hold the picked picture (A, B,
  then A again), and setting the same source loads nothing, so it never
  came to the front. A faded-out picture now lets go of its image, and one
  still held is brought forward directly. `qt6-imageformats` is a core
  package, for .webp wallpapers (Qt cannot read them without it).
- [x] htop dropped from the utilities: btop does the same job and follows
  the wallpaper. Installs that have it keep it (nothing is uninstalled).
- [x] **C1. Launcher actions** (done): `>` prefix for scheme, wallpaper, light/dark,
  power actions; favourite and hidden apps
  - `>` power actions, panels, light/dark (`theme.mode`), random wallpaper,
    `Scheme: <backend>` (`theme.backend`); Ctrl+P favourites, Ctrl+H hidden
    (`> unhide …`), all in settings.json.
- [x] **10. Audio device switching and per-app volume** (done): control centre →
  Audio tab (`qs -c simplychit ipc call control open audio`)
- [x] **12. Power profiles** (done): power-saver / balanced / performance toggle
  - Control centre toggle (`services/PowerProfile.qml`), hidden when no
    profile daemon runs. install.sh offers `tlp-pd` when TLP is installed.
  - *Using TLP:* TLP conflicts with `power-profiles-daemon`, so don't install
    both. TLP 1.9+ has its own profiles (`tlp power-saver|balanced|performance`)
    and ships `tlp-pd`, which provides the same D-Bus interface as
    power-profiles-daemon. With `tlp-pd` running, a toggle written against
    the standard PPD interface works unchanged. Check your TLP version
    (`tlp-stat -s`).
- [x] **19. External monitor brightness** (done): `ddcutil` (DDC/CI)
  - `services/Brightness.qml` uses ddcutil for a non-laptop focused monitor;
    the brightness keys call `qs -c simplychit ipc call brightness up|down`.
    `ddcutil` is in the optional utilities (needs `i2c-dev` and the i2c group).
- [x] **16. Wallpaper extras** (done): per-monitor wallpapers, animated transitions,
  timed cycling
  - The shell draws the wallpaper (`modules/wallpaper/Background.qml`).
    Shift+Enter in the picker = this screen only; crossfade
    (`wallpaper.transitionMs`); `wallpaper.cycleMinutes`.
  - hyprpaper is gone (not started, not installed).
- [x] **C7. Special-workspace indicators in the bar** (done; not exercised live: no special workspace in use here)
- [x] **C7. Per-monitor bar config** (done): different widgets per screen, excluded
  screens (`bar.monitors`, `bar.excluded` in settings.json)
- [x] Toasts: general mechanism, shared with C9 below (done: `Notifs.toast()`, `ipc call notifications toast`)
  - [x] A pill at the bottom middle, under the OSD, not a notification card
    (SOMETING_OFF.md): `modules/notifications/Toasts.qml`, `Notifs.toasts`.
    A toast with the same title replaces the old one; three at most.
- [x] **C9. Event toasts** (done): charging, Caps/Num Lock, keyboard layout,
  audio device change, VPN, now playing, DND
  - `services/Events.qml`; each one switchable under `toasts` in settings.json
    (now playing is off by default). Lock keys and VPN not exercised live.
- [x] **C13. Critical-battery action** (done): suspend/hibernate at ~5%
  - `modules/battery/BatteryCard.qml`, settings `battery.actionPercent` (5)
    and `battery.criticalAction` (suspend). 30 s countdown with Cancel.
- [x] Clipboard image previews (done in the Quickshell clipboard panel: async
  thumbnails of any size, large preview of the selected image; fabric's
  skipped images over 300 KB)
- [x] Lock screen (done, opt-in): `modules/lock`, `lock.enabled` in
  settings.json. hypridle's `lock_cmd` is `hypr/Scripts/lock.sh`, which falls
  back to hyprlock unless the shell confirms it locked.
- [ ] **Check on a real session** — built and tested here as far as possible
  without replacing the running desktop; these need the deployed shell:
  - [ ] Deploy: `git -C ~/archdots pull && ~/archdots/install.sh update`
        (after `rewrite` is merged), log out and back in
  - [ ] `pkexec true` shows the shell's polkit dialog (registered: `qs -c
        simplychit ipc call polkit registered` prints `true`)
  - [ ] `notify-send hi` shows a shell card (fabric's daemon is gone)
  - [ ] Volume keys show the OSD; brightness keys change brightness
  - [ ] Power profiles: `sudo systemctl enable --now tlp-pd`, then the
        control centre toggle
  - [ ] On battery: lower `battery.lowPercent` to see a warning; the
        critical action at `battery.actionPercent`
  - [ ] An external DDC monitor, with `ddcutil` installed
  - [ ] Caps/Num Lock and a VPN coming up show toasts
  - [ ] A special workspace shows its chip in the bar
  - [ ] `qs -c simplychit ipc call lock preview`, then try `lock.enabled: true`
        with a TTY ready (recovery steps in `modules/lock/Lock.qml`)

## Phase 5: Settings app

A Quickshell window (`qs ipc call settings open [page]`) that edits the
files in `~/.config/simplychit/`. This is DMS section 4, and the main reason
for the config layout above. Every setting the app changes is **data**
(JSON or a Lua `return { … }` table), never generated code. The app can
then rewrite a file safely, and hand edits still work.

- [x] **Settings framework: built in Quickshell, inside the shell** (done)
  - As built: [SettingsWindow.qml](home/.config/quickshell/simplychit/modules/settings/SettingsWindow.qml),
    pages in `modules/settings/pages/`, form controls in `widgets/`.
    Opens with SUPER+COMMA, `qs -c simplychit ipc call settings open [page]`,
    the launcher's `>` Settings action and the gear in the control centre.
    Standalone: `qs -p …/simplychit/settings.qml`.
  - Everything lives in `settings.json` (no separate monitors.json).
    Hyprland reads it with [helpers/json.lua](home/.config/hypr/config/helpers/json.lua)
    and [helpers/settings.lua](home/.config/hypr/config/helpers/settings.lua);
    a broken file is reported and the defaults stay.
  - Writes go through `Config.set()`, which changes one key and keeps
    unknown keys and hand edits.
  - Not a separate GTK/PySide/Tauri app: one toolkit and one theme, the
    shell's existing services (Hyprland, PipeWire, theme), changes show
    up in the bar instantly, no new dependencies
  - Structure:
    ```
    ~/.config/simplychit/settings.json ─┐        ┌─ bar, launcher, OSD, …   (read Config)
                                      ├─ Config.qml (singleton)
           defaults in QML ───────────┘        └─ SettingsWindow pages    (read + write Config)

    ~/.config/simplychit/monitors.json ── Displays page writes ── hyprland Lua reads it
    ```
  - `shell/config/Config.qml`: singleton on `FileView` + `JsonAdapter`.
    Defaults are declared in QML and `settings.json` overrides them. Page
    changes are written back; hand edits are picked up live (`watchChanges`).
  - `shell/modules/settings/SettingsWindow.qml`: `FloatingWindow` with a
    sidebar of pages, each loaded only when opened (no memory cost until
    used). Opened with `qs ipc call settings open [page]`, a keybind, the
    control centre, or the launcher (`>settings`).
  - Hyprland reads its data files (`monitors.json`, later `input.json`, …)
    from Lua. Hyprland's Lua has no JSON parser: ship a single-file decoder
    (`rxi/json.lua`), or have the app write data-only `return { … }` tables
    instead. Either way the app writes data, never code.
  - Atomic writes (`FileView` `atomicWrites`, confirm it in the Quickshell
    docs) so a crash mid-save can't leave a half-written file
  - Hand-edited values are kept: rewrite only the keys that changed, keep
    unknown keys, warn instead of crashing on a bad value
  - Also runnable on its own (`qs -p shell/modules/settings`, same
    `Config.qml`), so settings still open if the shell has crashed
  - Known cost: Quickshell isn't a full app toolkit, so file pickers and
    complex forms take more hand-building. Fine for toggles, sliders,
    dropdowns and lists.
- [x] **Displays page (Windows-style monitor manager)** (done)
  - As built: [DisplaysPage.qml](home/.config/quickshell/simplychit/modules/settings/pages/DisplaysPage.qml),
    [Displays.qml](home/.config/quickshell/simplychit/services/Displays.qml),
    the keep/revert card in [DisplayOverlays.qml](home/.config/quickshell/simplychit/modules/settings/DisplayOverlays.qml).
    Changes apply live with `hyprctl eval 'hl.monitor{…}'` (checked: works
    under the Lua config, by `desc:`). Profiles are saved on Keep under
    `displays.profiles`, keyed by the connected descriptions; monitor.lua
    applies the matching one at startup, the shell on hotplug. Hyprland
    has no "primary"; the shell's own `displays.primary` (a picker on the
    page, `services/Screens.qml`) places the login screen.
  - Canvas of monitor rectangles at their logical size (resolution ÷
    scale, swapped when rotated), drawn from `hyprctl monitors all -j`
  - Drag to arrange, snapping to the other monitors' edges and preventing
    overlap. Convert back to pixel positions on release. Normalise so the
    top-left monitor is at `0x0`.
  - Per monitor: enable/disable, resolution + refresh (from
    `availableModes`), scale, rotation, VRR, mirror, primary
  - "Identify" button that briefly shows each monitor's name on that screen
  - **Apply → "Keep these settings?" with a 15 s countdown that reverts
    automatically**, so a bad mode can't leave you with a black screen
  - Saves to `~/.config/simplychit/monitors.json`. `monitor.lua` reads it
    and stops hard-coding names (replaces the current `config/monitor.lua`
    and `custom/monitor.lua` split)
  - Workspace → monitor assignment on the same page
  - **Profiles:** store one layout per set of connected monitors, keyed by
    each monitor's `description` (make/model/serial), not the port name
    (`DP-1` changes between docks and cables). Apply the matching profile
    automatically on Hyprland `monitoradded`/`monitorremoved`. This covers
    DMS 18 below.
  - Check first: how the Lua config provider applies a monitor change at
    runtime (`hyprctl keyword monitor` may not apply under Lua). Fallback:
    write the file, then `hyprctl reload`.
- [x] **18. Multi-monitor awareness**: bars on hotplug, output profiles
  instead of hard-coded names in `monitor.lua` (done: bars follow
  `Quickshell.screens`; profiles as above. The owner's hard-coded layout in
  monitor.lua stays as the fallback when no profile matches)
- [x] **Other pages, in rough order of value** (done: all eight, plus
  island order (`bar.left`/`bar.right`) and `appearance.opacity`. Not done:
  scaling (the Displays page has per-screen scale) and scheme/variant
  beyond pywal16's backend and light/dark)
  - Appearance: wallpaper, scheme/variant, light/dark, transparency, scaling
  - Bar: which widgets, their order, per-monitor bar config (C7)
  - Idle & power: lock/DPMS/suspend timeouts (AC and battery), critical
    battery action (C13), power profile (12)
  - Default apps: terminal, browser, file manager (used by keybinds)
  - Notifications: timeout, DND schedule, which event toasts to show (C9)
  - Input: keyboard layouts, touchpad options (from `input.lua`)
  - Keybinds: view and rebind. Do this last, since it depends on keybinds
    being a data table (see Config layout).
  - About / doctor: versions, dependency checks, open config folder

## Phase 6: installer, validation, greeter

- [x] **Rename to SimplyChit** (done, asked for before phase 6): every path
  and id is `simplychit` now; `retire_old_name` in install.sh moves an
  existing install's user folder and state, prunes dead links, renames the
  GTK theme and the SDDM conf, and restarts the shell under the new name.
  Left: the GitHub repo name (owner's call; DO_THIS.md 1b).

- [x] **Installer that works on most Arch systems** (done)
  - As built: `detect_system` in install.sh, run before either mode. Reads
    os-release (Arch-based or not; a Manjaro warning), the repo versions
    of Hyprland/Quickshell against `MIN_HYPRLAND`/`MIN_QUICKSHELL`, uses
    an existing paru or yay (`$AUR_HELPER`; paru is built otherwise), GPU
    vendors (warns on NVIDIA without a driver), laptop vs desktop (TLP
    only on laptops, power-profiles-daemon on desktops), PulseAudio (asks,
    default yes, to swap for pipewire-pulse), another login screen and
    another network manager (both asked, default **no**, disabled only,
    at the next boot, rollback printed). Tested on this machine and in a
    simulated EndeavourOS desktop (GDM, iwd, PulseAudio, NVIDIA, yay); not
    yet on a real derivative.
  - Plain Arch and the common derivatives (EndeavourOS, CachyOS, Garuda,
    Manjaro). Detect the AUR helper (`paru`/`yay`, or bootstrap one), the
    existing display manager, the GPU vendor, laptop vs desktop, and
    whether `pipewire`/`NetworkManager` are already set up.
  - Must be safe to re-run, with a `--update` mode (Caelestia C15).
- [x] **Validate settings and report errors** (done)
  - JSON schema for `settings.json` (editor autocompletion): generated from
    Config.qml by `tools/gen-settings-schema.py` into
    `config/settings.schema.json`; `"$schema"` in settings.json (CUSTOMIZING)
  - Warn on unknown keys or bad values at startup, like the Hyprland override loader:
    `simplychit check-settings`, run by `services/SettingsCheck.qml` at start and
    on every save; a toast names the first problem, with "did you mean" for typos
  - `simplychit doctor`: check dependencies, services, running daemons, config errors
    (done in phase 5: [simplychit](home/.local/bin/simplychit) `doctor [--json]`,
    shown on the settings app's About page)
- [x] **Replace SDDM with a greeter that shares the shell's theme**
  (done: the greeter is the default login screen. `install.sh` sets it up
  unless `--no-greeter` (then the themed SDDM, as before). It asks before
  switching: default yes with no login screen or SDDM, no for any other.
  SDDM stays installed, unthemed, and `greeter_fallback` enables it when
  the greeter cannot be set up, so a machine never boots without one.
  `update` does not switch an existing install; it refreshes a greeter
  that is there. Built and VM-tested: [greeter.qml](home/.config/quickshell/simplychit/greeter.qml),
  `install.sh install --greeter`. In a fresh Arch VM
  (`~/.cache/simplychit-greeter-vm`): the full install, greetd booting the
  greeter, wrong password, faillock's lockout notice, login into Hyprland
  and the shell, the remembered user, rollback to SDDM. Four bugs found
  and fixed on the way (paru OOM in tmpfs, greeter user has no home, PAM
  info lines, Quickshell's own cancel). Not tested: clicking the session /
  Restart / Shut down buttons, and real hardware.)
  - greetd + a Quickshell greeter (`Quickshell.Services.Greetd`), so the
    login screen is the same QML and colours as the lock screen.
  - Fallback if that's too much at first: greetd + `tuigreet` or ReGreet.
  - [x] Several monitors (SOMETING_OFF.md): cage stretches the window
    across all of them, so the login box sat on the seam. The greeter now
    switches every monitor but the primary one off with wlr-randr (again
    on hotplug); Hyprland turns them back on after login. The primary is
    `displays.primary`, settings.json copied into the greeter's HOME by
    `greeter_copy_files`. Without wlr-randr the box is placed on the
    primary screen and the rest stay dark. Tested in a nested cage with
    two outputs (primary first, second, unset); not on real hardware.
  - [x] Keypad digits with Num Lock off on the lock and login screens
    (`lock.numlock`, default on, switch on the Idle page). Done in the
    fields, since neither cage nor a Hyprland client can set Num Lock.
    Tested with wtype in a nested cage.
  - ⚠️ **Test the greeter in a virtual machine only.** A broken greeter can
    leave the machine unable to log in. Do not test on a live/daily system
    unless it is known safe: it already works in the VM, and the recovery
    steps below have been tried.
  - Safety rules for when it does reach real hardware:
    - Take a VM snapshot (or a btrfs/timeshift snapshot on hardware) before
      switching display managers
    - Keep SDDM installed and only *disable* it, so rolling back is two
      commands
    - Confirm a TTY login works first (`Ctrl+Alt+F2`), so there is always
      a way in
    - Rollback from a TTY:
      ```bash
      sudo systemctl disable greetd && sudo systemctl enable sddm && sudo reboot
      ```
    - The installer must never switch the display manager without asking,
      and should print these rollback steps when it does
  - [x] GTK theme missing on a fresh install, host and flatpak apps alike
    (worked on the live machine only). Host GTK 4: `stage_gtk4_base`
    returned before copying `overrides.css` into `~/.config/gtk-4.0/` when
    gresource/libadwaita were absent, which is every fresh Arch; the copy
    now comes first. Flatpaks: install.sh never granted them the theme (the
    live machine had a hand-made override); `stage_flatpak_theming` sets a
    per-user override (gtk-3.0/gtk-4.0 config and `~/.themes` read-only,
    `GTK_THEME`) on install and update. Tested both stages in a scratch
    HOME, and on a fresh VM install (by the owner).
  - [x] Flatpak apps moved to pacman where the official repos carry them
    (`PKG_APPS`, `--no-apps`): Flathub's bandwidth made a first install
    take up to an hour. Packet was dropped too, so `PKG_FLATPAK` is empty
    and the step skips itself until an app id is added. Fresh installs only,
    so an update does not duplicate an existing install's flatpaks. The
    process manager default is `missioncenter || flatpak run …`, which
    covers both. Tested on a fresh VM install (by the owner).
  - [x] VS Code theme readable on any wallpaper. wal-theme put the dark half
    of the `--cols16 dual` palette on keywords and constants (1.5:1). Now
    our own theme extension (`vscode-theme/`), packed and installed by
    install.sh, rewritten by `simplychit sync-palette`: every syntax colour
    keeps its hue and is lightened to a contrast floor (code 5.5:1,
    comments 4.2:1), roles also split by lightness so a one-hue palette
    stays distinguishable. A "Wal" selection is moved to "SimplyChit".
    Tested install + sync in a scratch VS Code profile. The theme file is
    rewritten in place, and the theme entry carries `"_watch": true`: VS
    Code watches a theme file only with that flag (or in extension
    development), and reloads only on an update event, not a rename.

## Phase 7: remaining features

- [x] **9. Calendar events**: khal + vdirsyncer (Google/CalDAV), today's
  events under the month grid (done: `services/CalendarEvents.qml` via
  `simplychit events <date>`, which formats the date in khal's own
  dateformat; clicking a day lists that day. Setup in CUSTOMIZING.md,
  Calendar. Tested with khal 0.14 in a scratch venv and local calendars;
  not tested against a real vdirsyncer/Google sync)
- [x] **17. Editor and app theming**: VS Code, browser, btop, fastfetch,
  hyprlock templates (done: `simplychit sync-palette` makes every copy,
  run by Theme.qml after wal and by install.sh's `stage_app_theming` on
  install and update. hyprlock sources colours from
  `~/.local/state/simplychit/hyprlock-colors.conf`; btop gets pywal16's
  btopwal.theme; VS Code the wal-theme extension; the browser pywalfox;
  fastfetch already follows the terminal palette. Not tested on screen:
  hyprlock itself (only its parser's source/override behaviour, with
  hyprlang), the VS Code extension, pywalfox in Zen. DO_THIS: pick theme
  "Wal" in VS Code, add the Pywalfox add-on)

### Nice to have

- [x] Notepad / scratchpad (done: `modules/notepad/Notepad.qml`,
  SUPER+SHIFT+N, saves to `~/.local/share/simplychit/notepad.md`;
  `ipc call notepad append "…"`. Not tested: typing into it, since wtype
  is only safe in a nested compositor; saving tested through `append`)
- [x] Screen recording (+ recording indicator in the bar) (done:
  `services/Recorder.qml` with wf-recorder; screenshot menu cards,
  SUPER+SHIFT+R, red dot + time in the resources island, `ipc call
  recording region|screen|stop|toggle|status`, `recording.audio`.
  Tested: screen, region (slurp shimmed), cancel, desktop audio)
- [x] QR codes: copy as QR, scan a region (done: `modules/qr/Qr.qml`
  and `services/QrScan.qml`; launcher `>` actions and `ipc call qr
  open|scan`. Tested with shimmed wl-paste/grim/wl-copy: the panel's
  code decodes back to the text, and a scan copies exact UTF-8)
- [x] System sounds: volume change, notification (done:
  `services/Sounds.qml`, pw-play + sound-theme-freedesktop; switches on
  the Notifications page. Tested with pw-play shimmed: normal, critical,
  suppress-sound, DND, a burst of volume steps → one tick. Not heard on
  real speakers yet)

### Picked from MISSING.md and the new ideas (2026-10-15)

- [x] **C11. Scratchpad binds** (done): `hypr/config/helpers/scratchpad.lua`;
  SUPER+` drop-down terminal (started the first time), SUPER+- the
  scratchpad, SUPER+SHIFT+- sends the focused window there and back. More in
  `keybinds.scratchpads` (name -> keys, command), ids `scratchpad-<name>` so
  remap/disabled work. Tested live with a throwaway special workspace
  (launch, hide, show without relaunch, send out and back) and the loader
  offline with a fake settings.json
- [x] **Shell watchdog** (done): `hypr/Scripts/shell-watchdog.sh` runs
  `qs -c simplychit` and starts it again after a crash (exit 255 from
  Quickshell's crash handler); `qs kill` (0) and the end of the session
  (SIGTERM, 143) stop it. The new shell toasts "The shell restarted"
  (`services/Events.qml`); three crashes in a minute and it gives up with a
  Hyprland notification. `shell.restart()` and install.sh's update restart
  go through it; `simplychit doctor` checks its lock. Tested with a scratch
  config and shimmed qs/hyprctl: crash, kill, give-up, restart handover,
  SIGTERM; the toast in a scratch shell copy. Not yet run as the live shell
- [x] **Welcome screen on first run** (done): `modules/welcome/WelcomeWindow.qml`
  and `services/FirstRun.qml`. Five steps: welcome, wallpaper and
  light/dark, keyboard layout and touchpad, default apps, the keys worth
  knowing (read from keybinds.json, so remaps show). Finish reloads
  Hyprland if a keyboard or app setting changed. Shown when
  `~/.local/state/simplychit/welcomed` is missing; any close writes it, and
  install.sh's update writes it for existing installs. Again with the
  launcher's `> Welcome` or `ipc call welcome open`. Tested in a scratch
  shell copy: every step on screen, done writes the marker, no second show,
  IPC reopens. Not tested: typing into its fields (wtype is unsafe here)
- [x] **Videos in browsers stop the dim** (SOMETHING_OFF.md): browsers ask over
  D-Bus (`org.freedesktop.ScreenSaver`, directly or through the portal), which
  hypridle owned and ignored, so only Wayland inhibitors reached the shell.
  `simplychit inhibitors` now owns the name (D-Bus activation file, and
  autorun.lua), also lists logind idle inhibitors, and writes
  `$XDG_RUNTIME_DIR/simplychit-inhibitors.json`; `Idle.appInhibited` pauses
  every idle step. The bar's stay-awake glyph shows dimmer and the Awake
  toggle names the app. hypridle has `ignore_dbus_inhibit`; install.sh's
  update reloads the bus and restarts hypridle; doctor names the owner.
  Tested: the service on a private bus (cookies, a client dying, logind,
  one instance, SIGTERM), hypridle leaving the name, a scratch shell
  (dim disabled with the file, back without it, bad JSON ignored).
  Not yet tested live with Zen
- [x] **Bar layout per screen** (SOMETHING_OFF.md): one default layout
  (`bar.left` / `bar.center` / `bar.right`, a centre section is new) and, per
  screen, the default or its own (`bar.monitors`, keyed by the monitor's
  description so it follows the monitor across ports; port names still
  work). The status island is split into `indicators`, `volume`, `cpu` and
  `battery`, drawn as one island when next to each other (`modules/bar/Status.qml`);
  `resources` still means all four. Rules in `services/BarLayout.qml`; the Bar
  page picks Default or a screen, with "Use the default layout" and
  move/remove/add per section. Tested in a scratch shell: both bars drawn
  from a per-screen layout and the old `resources` default, the page in
  both views, and its save logic driven offscreen (move across sections,
  own layout on/off, add, remove, bar on/off)


## Phase 8: uniform theme

The DEVELOPMENT.md roadmap's last open item, "Create a custom uniform
theme": every toolkit following the wallpaper palette, with the shell's look.
Steps in order; the first is the quick win.

- [x] **Qt palette from wal** (done): Kvantum ignores qt6ct's palette
  (checked: a red qt6ct scheme shows under Fusion, not under Kvantum), so
  `sync-palette` generates a Kvantum theme, `~/.config/Kvantum/SimplyChit/`:
  KvGlass's kvconfig with the GTK theme's derived roles (text at a contrast
  floor) and its SVG with the blues turned to the accent and the greys moved
  onto the background-to-text line, so a light palette gives a light theme.
  KDE colours go into `~/.config/kdeglobals` (`[Colors:*]`, `[WM]`; a real
  file now, no longer stowed, seeded with the old terminal and icon keys)
  and `~/.local/share/color-schemes/SimplyChit.colors`. install.sh unfolds
  `~/.config/Kvantum` (Kvantum reads themes from nowhere else) and removes
  links to files the repo dropped; sync-palette refuses to write while it is
  folded. Tested in scratch homes: rendered Qt widgets offscreen (PySide6)
  for the current, default and a light palette; the folded guard; a
  dangling kdeglobals link; the container run (5 palette copies, repo
  clean). Apps pick the colours up on restart only. Not
  yet seen in a real Qt app on screen (needs an install.sh update to unfold
  the live `~/.config/Kvantum`)
- [x] **Clean up the Kvantum leftovers** (done): `kvantum.kvconfig` is just
  `theme=SimplyChit` (its `[Applications]` pinned Dolphin to KvGlass);
  `KvGnomeDark#` and the root `kvantum/` (an older KvGlass plus
  `kvGlass.colors`) are gone. The stowed `KvGlass/` stays as the generator's
  base. qt6ct's own palette settings are left as they are: Kvantum ignores
  them
- [x] **One font across toolkits** (done): Roboto 12 in both GTK
  `settings.ini` files and qt6ct (as before); qt6ct's fixed font, which was
  Roboto, is JetBrainsMono Nerd Font 12. `stage_fonts` (install and update)
  copies both into dconf, which GTK on Wayland and the portal read. Tested
  with a gsettings shim
- [x] **SimplyChit Kvantum theme** (done): drawn in code, `kvantum_svg` and
  `kvantum_config` in `simplychit`, rerun by `sync-palette` on every
  wallpaper change. Flat rounded frames (buttons, fields, menus, tabs,
  lists, tooltips, group/tab frames) with accent borders at the GTK theme's
  strength; check boxes, radios, chevrons (arrows, combo, tree), slider
  handle, scrollbar pill, grips, tab close. Layout after KvSimplicity
  (inline spin arrows, thin progress bars). Text on the accent is chosen
  from light and dark candidates (a mid-tone accent needs dark text), the
  pressed shade moves away from it, focus borders are the accent at 3:1.
  Nearly everything translucent (`translucent_windows`, window 0.80, views
  0.30 on top, buttons 0.75, popups 0.85, Dolphin's view through
  `transparent_dolphin_view`): GTK's choice of glass content was tried
  first, but in Qt apps the views came out solid. Measured on Wayland with
  a polished, never-shown window: background 80%, a list 86%, text opaque. KvGlass is gone from the repo. Tested in scratch homes: a widget gallery
  rendered offscreen with the current, default, a light and a vivid
  palette; every element and state drawn the way Kvantum draws it; text
  contrast at 4.5:1 or more on every fill in all four; the container run.
  Hover and keyboard-focus states could only be checked element by element
  (an offscreen window never hovers or focuses)
- [x] **Check the theme in real apps** (done, by the owner): Dolphin, Ark
  and others on screen, after the glass change. Not looked at on purpose:
  Dolphin's list view (broken under KvGlass)
- [x] **Cursor theme** (done): Bibata Modern Classic (AUR
  `bibata-cursor-theme-bin`), picked by the owner from a rendered preview of
  Breeze, Capitaine, Vimix and both Bibatas. Named in both GTK
  `settings.ini`, the theme's `index.theme`, Hyprland's `XCURSOR_THEME` (no
  hyprcursor theme, so Hyprland draws the XCursor one, also for cursor-shape
  clients) and the greeter's cage env; `stage_interface` (was `stage_fonts`)
  puts it in dconf, skipped with a warning when not installed. Tested with a
  gsettings shim (installed and not); the container run (stops at its
  gtk-theme limit before this stage, so structure only). Not covered:
  GTK 3 flatpaks, which cannot see `/usr/share/icons` and draw their own
  cursor; GTK 4 ones hand it to Hyprland
- [x] **Qt5 apps** (done): `QT_QPA_PLATFORMTHEME=qt5ct`. Qt 5 and 6 read
  the same variable, and qt6ct's plugin lists both "qt6ct" and "qt5ct" as
  keys, so Qt 6 apps keep qt6ct and Qt 5 ones (VLC, sqlitebrowser) get
  qt5ct instead of light Fusion at 9 pt. `qt5ct` and `kvantum-qt5` are core
  packages; `qt5ct.conf` mirrors `qt6ct.conf`; both use the one generated
  Kvantum theme. Cursor size also settled at 20 (Bibata's 24 looked big).
  Tested: Qt 6 with qt6ct/qt5ct/a made-up name (qt6ct, qt6ct, Fusion); a
  Qt 5 gallery with qt5ct, kvantum-qt5 and PyQt5 extracted to a scratch
  dir, before and after; the container run. Not yet seen in a real Qt 5
  app on screen
- [x] **Flatpak Qt apps** (done): `stage_flatpak_theming` installs Flathub's
  `org.kde.KStyle.Kvantum` per user (no root) for every `org.kde.Platform`
  branch present, and the global override adds `QT_STYLE_OVERRIDE=kvantum`
  and read access to `~/.config/Kvantum` and `kdeglobals`. Runs on update;
  a branch with no Kvantum on Flathub (6.11, qView's, today) is noted and
  retried. Tested with a flatpak shim shaped like this machine (installs
  5.15-25.08 and 6.10, notes 6.11, skips on a second run), then for real:
  PrismLauncher came up in Kvantum's grey built-in theme. A flatpak sees
  `~/.config/Kvantum` mounted inside its own config folder, where the
  stowed `kvantum.kvconfig` (a relative link into the clone) points at
  nothing. It is now a real file written by `sync-palette` (kept when the
  user has their own); checked from inside Prism's sandbox
- Chromium, Discord and accent-tinted icons: left out by the owner, moved
  to MISSING.md (U1-U3)
- [x] Tick "Create a custom uniform theme" in DEVELOPMENT.md's roadmap

## Phase 9: notifications, privacy, media

Moved from MISSING.md (notification grouping, privacy indicators, C6 media
extras), with the owner's choices.

- [x] **Notification grouping** (done): `Notifs.historyGroups` groups the
  history by app (ordered by each app's newest); `NotificationGroup.qml`
  shows one notification as a plain card, two or more under a header (app,
  count, expand, Clear) with the newest card and the stacked edges of the
  rest, or every card when open. Open groups are kept by app name while the
  centre is open, so a new notification does not close them. Popups are
  unchanged. Tested in a scratch shell on a private bus (notify-send from
  three apps): collapsed, and expanded (a scratch copy forced open; a click
  cannot be sent safely)
- [ ] **Privacy indicators**: microphone, camera and screen-share dots in the
  bar's indicators, from PipeWire streams; hovering or clicking lists the
  apps using them
- [ ] **Media panel**: clicking the bar's media island opens it. Cover art,
  title, artist, a seek bar, the controls, and a switcher when several
  players are open (the one picked stays the bar's player)
- [ ] **Visualiser**: a cava spectrum in the media panel (`cava` from the
  official repos), running only while the panel is open
- [ ] **Synced lyrics**: from LRCLIB for the playing track, the current line
  highlighted in the media panel
