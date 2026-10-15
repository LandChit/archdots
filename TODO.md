# To do

Feature numbers (1, C1, …) refer to the sections in [MISSING.md](MISSING.md).

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
