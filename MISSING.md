# What's missing compared to DankMaterialShell and Caelestia

A gap list between simplychit (`fabric_shell` + Hyprland) and two Quickshell
shells:

- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS):
  QML with a Go backend (`dms`).
- [Caelestia](https://github.com/caelestia-dots/shell): QML with a Python CLI
  ([`caelestia`](https://github.com/caelestia-dots/cli)), Hyprland-only.

Sources: the DMS README and the docs at danklinux.com/docs (overview,
keybinds/IPC), and the Caelestia shell and CLI READMEs. Some internals, such
as the exact DMS bar widget list and settings tabs, are not documented in
detail, so a few entries go by the IPC targets and config keys each shell
exposes.

Most of what Caelestia has is already listed under DMS. Those entries are
tagged **(both)**. Gaps that only Caelestia shows are in
[their own section](#also-missing-compared-to-caelestia).

---

## Already at parity (roughly)

| Area | simplychit | DMS |
|---|---|---|
| Bar | workspaces, window title, media, volume, CPU temp, battery, clock + calendar | many more widgets (see below) |
| Launcher | apps ranked by usage, `?` web search | apps, files, emoji, windows, calculator, commands, plugins |
| Control centre | Wi-Fi, Bluetooth, volume, brightness, media, tray, DND | same, plus audio device switching, display, night mode, VPN |
| Notifications | popups, history, actions, urgency, DND | same, plus grouping, rich text, keyboard navigation |
| Clipboard | cliphist history | history **with image previews** |
| Emoji picker | yes | yes (inside the launcher) |
| OSD | volume, mic, brightness | same |
| Power menu | lock, logout, restart, shutdown | same, plus session switching |
| Keybind cheatsheet | generated from config | generated, per compositor |
| Wallpaper → theme | pywal16 → bar, GTK, Qt, alacritty, Hyprland | matugen + dank16 → GTK, Qt, terminals, VS Code |
| Lock screen | hyprlock (separate config) | built into the shell |
| Login | SDDM `silent` | dank-greeter (greetd), themed from the shell |

---

## Missing: high impact

These are what make DMS feel like a complete desktop environment instead of a set of widgets.

### 1. Idle management and auto-lock **(both)**
- **DMS:** idle detection, auto-lock and auto-suspend, with separate
  timeouts on AC and on battery. Idle inhibit toggle (`dms ipc call inhibit`).
- **simplychit:** nothing. `hypridle` isn't installed, and
  [powermenu.py](home/.config/fabric_shell/powermenu.py#L17-L22) calls `hyprlock`
  directly, so locking on idle or sleep doesn't happen.
- **Fix:** add `hypridle` with a `hypridle.conf` (lock → DPMS off → suspend),
  and `before_sleep_cmd = loginctl lock-session`. Add an inhibit toggle to the
  control centre (e.g. a "caffeine" toggle that runs `systemd-inhibit`, or
  stops and starts hypridle).

### 2. Polkit agent probably isn't running
- `hyprpolkitagent` is in the installer's package list
  ([install.sh:49](install.sh#L49)), but nothing starts it: there's no
  `exec_cmd` in [autorun.lua](home/.config/hypr/config/autorun.lua) and no
  `systemctl --user enable hyprpolkitagent`. GUI privilege prompts (e.g.
  mounting, gparted, some settings apps) will fail silently. Check this on
  the live machine; it may have been enabled by hand.
- **DMS:** a polkit agent built into the shell and themed with it.
- **Fix:** at minimum, enable `hyprpolkitagent.service`. For parity, write a
  polkit dialog in fabric (harder; needs a polkit agent registration).

### 3. Night light / gamma control
- **DMS:** night mode with colour temperature, gamma, schedule or
  location-based sunrise/sunset (`dms ipc call night`).
- **simplychit:** none.
- **Fix:** `hyprsunset` (IPC via `hyprctl hyprsunset temperature N`) plus a
  toggle and slider in the control centre. Schedule it with a timer or
  `hyprsunset`'s own profiles.

### 4. Settings GUI **(both)**
- **DMS:** a full settings app (`dms ipc call settings`) for the bar layout,
  widgets, theme, wallpaper, greeter, idle, displays, plugins, etc. Settings
  can also be read and written over IPC.
- **simplychit:** every change means editing Python constants or Lua.
- **Fix:** a single `settings.json` that `fabric_shell` reads (and watches),
  then a settings overlay to edit it. Start with: bar widgets on/off, clock
  format, 12/24h, notification timeout, launcher search engine.

### 5. System monitor / process list **(both)**
- **DMS:** CPU, RAM, GPU usage and temps in real time (via `dgop`), plus a
  process list with search and kill (`processlist`), and dashboard widgets.
- **simplychit:** only CPU temperature in the bar, and a keybind to launch
  `nvtop`.
- **Fix:** bar meters for CPU % / RAM / GPU (psutil + `nvidia-smi` or
  `/sys/class/drm`), and a process-list overlay (psutil, sort, search, kill).

### 6. Launcher modes **(both)**
- **Missing:** calculator, file search, open windows (switch to a window),
  shell commands, plugin providers.
- **Fix:** prefix modes on the existing launcher: `=` calc (`qalc` or
  safe-eval), `/` files (`fd`/`plocate`), `>` run command, and a windows
  section from `hyprctl clients -j`. [windows.py](home/.config/fabric_shell/windows.py)
  may already have the data needed.

### 7. Weather **(both)**
- **DMS:** weather widget in the bar and dashboard.
- **Fix:** an Open-Meteo poll (no API key needed) to a bar island and a
  popup forecast.

---

## Missing: medium

### 8. Dashboard ("DankDash") **(both)**
A tabbed overlay that combines media (with an **audio visualiser**), calendar
agenda, weather and system stats. simplychit spreads these across separate
popups (calendar, media island). This could reuse the existing pieces in one
overlay.

### 9. Calendar events
- **DMS:** `dankcalendar` syncs Local, Google, Microsoft and CalDAV events
  into the calendar popup.
- **simplychit:** [calendar_popup.py](home/.config/fabric_shell/calendar_popup.py)
  shows a month grid only.
- **Fix:** `khal` + `vdirsyncer` and list today's events under the grid.

### 10. Audio device switching and per-app volume
The DMS control centre can cycle outputs (`audio` IPC). Add an output/input
picker (`wpctl status` / `pactl`) and per-app sliders to the control centre.

### 11. VPN **(both)**
NetworkManager VPN connection list with toggles in the control centre
(`nmcli connection show --active`, type `vpn`/`wireguard`).

### 12. Power profiles
`powerprofile` IPC: power-saver / balanced / performance via
`power-profiles-daemon`. A three-way toggle in the control centre or battery
popup.

### 13. Dock
DMS has an optional dock with auto-hide. simplychit has none (the plank theme
under `.themes/catppuccin…` is unused). A fabric bottom-anchored window with
pinned apps, plus running ones from `hyprctl clients`.

### 14. Workspace overview
`hypr` IPC opens a Hyprland workspace overview (window previews per
workspace). Possible with the `hyprexpo` plugin, or a fabric overlay that
uses `grim` per window/monitor for thumbnails.

### 15. Light/dark mode toggle **(both)**
DMS switches light and dark modes (`theme` IPC), and the theme follows it.
pywal16 supports `-l` for light; add a toggle that re-runs wal with `-l` and
flips `gtk-application-prefer-dark-theme` /
`org.gnome.desktop.interface color-scheme`.

### 16. Wallpaper extras
- Per-monitor wallpapers (simplychit sets the same one on every monitor:
  [wallpapers.py:255](home/.config/fabric_shell/wallpapers.py#L255)).
- Animated transitions between wallpapers (`swww` instead of hyprpaper).
- Automatic cycling on a timer.

### 17. Editor and app theming
DMS themes VS Code / VSCodium from the wallpaper. Add a pywal16 template for
a VS Code colour theme (or use the `wal-theme` extension), plus templates
for anything else in use (zen-browser via pywalfox, fastfetch, btop,
hyprlock).

### 18. Multi-monitor awareness
Bars are created per monitor at startup ([bar.py:280](home/.config/fabric_shell/bar.py#L280)),
but there's no hotplug handling (plugging in a monitor after start gives it
no bar). DMS also has output profiles (`outputs` IPC) and per-monitor bar
config. Listen to Hyprland `monitoradded`/`monitorremoved` events.
[monitor.lua](home/.config/hypr/config/monitor.lua) also hard-codes
output names; consider `kanshi`-style profiles or a display settings page
(`nwg-displays`).

### 19. Brightness on external monitors **(both)**
DMS controls internal backlight, LEDs **and DDC/CI** (external monitors).
simplychit uses `brightnessctl` (internal only). Add `ddcutil`.

---

## Missing: nice to have

| Feature | DMS | Suggested approach |
|---|---|---|
| Notepad / scratchpad | `notepad` modal | text overlay that saves to `~/.local/share` |
| Colour picker | `color-picker` modal + CLI | `hyprpicker -a` bound to a key, history in a popup |
| Screen recording | screenshot tooling | `wf-recorder` / `gpu-screen-recorder` entry in the screenshot menu, plus a recording indicator in the bar |
| Screenshot annotation | — | pipe to `satty` / `swappy` from the screenshot menu |
| QR codes | `dms qr` | `qrencode` for the clipboard, `zbarimg` on a region grab |
| Privacy indicators | mic/camera/screenshare in use | watch PipeWire nodes and show a dot in the bar |
| System updater | `systemupdater` modal | `checkupdates` + AUR count in the bar, click to run `paru` in a terminal |
| Toasts | `toast` IPC for shell messages | a small transient overlay (`ctl.py toast "…"`) for shell errors and confirmations |
| Browser picker | `dms open <url>` chooser | `.desktop` URL handler that asks which browser |
| Workspace rename | dialog | Hyprland `renameworkspace` |
| System sounds | volume and notification sounds | `canberra-gtk-play` on events |
| User profile picture | `profile` IPC | avatar in the power menu / lock screen |
| Clipboard image previews | yes | cliphist stores images; decode and show a thumbnail |
| Notification grouping | grouped by app | group cards in history by `app_name` |
| Suspend / hibernate | in power menu | add `systemctl suspend` / `hibernate` cards |
| Auto-hide bar | `bar` IPC autohide | toggle `exclusivity` + reveal on edge hover |
| Desktop widgets | clocks/monitors on the wallpaper layer | fabric `layer="bottom"` windows |
| `doctor` command | `dms doctor` | `ctl.py doctor` that checks deps, services and running daemons |
| Plugin system | registry + lockfile | probably not worth it for personal dots |

---

## Also missing compared to Caelestia

These are on top of the DMS gaps above. Caelestia is Hyprland-only like
simplychit, so most of these port over directly.

### C1. Launcher actions (`>` prefix)
- **Caelestia:** a `>` prefix turns the launcher into a command palette:
  calculator (libqalculate), switch colour scheme, scheme variant, pick
  wallpaper, random wallpaper, light/dark mode, lock, sleep, logout, reboot,
  shutdown, open settings. Dangerous actions (shutdown, reboot, logout) are
  off by default. It also has favourite and hidden apps, fuzzy matching per
  category, and optional Vim keys.
- **simplychit:** only `?` for web search. Favourites, hidden apps and fuzzy
  matching are missing too.
- **Fix:** an action table in [launcher.py](home/.config/fabric_shell/launcher.py)
  keyed by `>`, reusing the power menu commands and the wallpaper module.
  This pairs with the DMS launcher modes in #6.

### C2. Scheme variants and premade schemes
- **Caelestia:** Material You schemes from the wallpaper (`caelestia scheme
  set -n dynamic`), several **variants** (tonal, vibrant, expressive, …),
  premade schemes, and a "smart" mode that picks light or dark from the
  wallpaper's brightness.
- **simplychit:** a single pywal16 palette per wallpaper.
- **Fix:** expose pywal16's backends (`--backend colorz|haishoku|…`) and
  `--saturate` as "variants", and allow fixed schemes (`wal --theme`). For true
  Material You roles, run `matugen` alongside or instead of pywal16.

### C3. Wider app theming via user templates
- **Caelestia CLI:** user templates in `~/.config/caelestia/templates/` with
  Material role placeholders (`{{ primary.hex }}`), plus integrations for
  Papirus folder colours and Chromium-based browsers.
- **simplychit:** templates for fabric, alacritty, Hyprland and GTK only
  ([.config/wal/templates/](home/.config/wal/templates/)).
- **Fix:** add templates for hyprlock, fastfetch, btop, the browser, and
  `papirus-folders -C <nearest colour>`. This extends #17.

### C4. Lock screen: fingerprint and face unlock
- **Caelestia:** fingerprint (fprintd) and face unlock (Howdy), each with a
  retry limit, Howdy triggered on wake, notifications hidden on the lock
  screen, and session controls (power off or reboot from the lock screen).
- **simplychit:** password only in [hyprlock.conf](home/.config/hypr/hyprlock.conf).
- **Fix:** hyprlock supports fingerprint (`auth { fingerprint:enabled = true }`).
  Howdy needs PAM. Add the clock/date, the user avatar (`~/.face`) and
  pywal16 colours to the lock screen while you're there.

### C5. Desktop background layer: clock and audio visualiser
- **Caelestia:** draws its own wallpaper layer with a configurable **desktop
  clock** and a **cava audio visualiser** that hides when nothing is playing.
- **simplychit:** hyprpaper only.
- **Fix:** a fabric `layer="bottom"` window with a clock and a cava bar
  visualiser (`cava` raw output mode → a drawing area). This is the "desktop
  widgets" row below, made concrete.

### C6. Media extras
- **Caelestia:** synced lyrics (with a lyrics backend and cache directory),
  a visualiser in the media panel, a default player plus player aliases, and
  a bongo-cat animation while music plays.
- **simplychit:** [media.py](home/.config/fabric_shell/media.py) shows the current
  track and basic controls.
- **Fix:** LRCLIB (free, no key) for `.lrc` lyrics, matched to the playerctl
  position. Add a "preferred player" setting for when several are open.

### C7. Bar details
| Caelestia bar feature | simplychit |
|---|---|
| Window icons inside each workspace button (with a max count) | numbers only |
| Special-workspace (scratchpad) indicators | none |
| Status icons: **keyboard layout**, **Caps Lock**, network, Bluetooth, mic | none of these in the bar |
| Scroll on the bar to change workspace / volume / brightness | volume only |
| Popouts on hover for tray, active window, status icons | click-only calendar and battery |
| Auto-hide bar, shown on hover | always visible |
| Per-monitor bar config, excluded screens | same bar everywhere |
| Logo and power button entries | none |
| Tray icon recolouring and substitutions | tray moved to the control centre because icons failed to resolve |

Tray icon substitutions are worth noting: they're Caelestia's fix for the
same unresolvable-icon problem that made simplychit drop the bar tray.

### C8. Sidebar
A slide-in side panel (shown on hover or by keybind) that holds the
notification list and quick toggles. simplychit splits these between the
control centre (SUPER C) and the notification history (SUPER N).

### C9. Event toasts
- **Caelestia:** small toasts for: charging plugged/unplugged, Caps Lock,
  Num Lock, keyboard layout change, audio output/input device change, VPN
  connect, now playing, DND toggled, game mode toggled, config reloaded,
  and volume/brightness limits.
- **simplychit:** none (the DMS toast row below is the general mechanism; this
  is the list of events worth hooking).
- **Fix:** UPower for charging, Hyprland `activelayout` events for the
  keyboard layout, and a key-state poll or libinput for the lock keys.

### C10. Game mode
A quick toggle that turns off Hyprland animations, blur, shadows and gaps
(and suppresses notification popups) for gaming. Easy with `hyprctl
--batch "keyword animations:enabled 0; …"` and a toggle in the control
centre. Caelestia also lets notifications behave differently over fullscreen
apps.

### C11. Special workspaces / dropdown apps
- **Caelestia CLI:** `caelestia toggle <name>` toggles named special
  workspaces (Discord, WhatsApp, Spotify, btop, Todoist), launching the app
  the first time.
- **simplychit:** no scratchpads in
  [keybind.lua](home/.config/hypr/config/keybind.lua).
- **Fix:** Hyprland `togglespecialworkspace` binds plus window rules that
  send each app to its special workspace. Show them in the bar (C7).

### C12. Window resizer daemon
`caelestia resizer` watches for specific windows (e.g. picture-in-picture,
popups) and resizes or positions them automatically. A small Hyprland
socket2 listener in the fabric daemon could do the same for PiP windows.

### C13. Critical-battery action
[battery.py](home/.config/fabric_shell/battery.py#L25-L26) already warns at 20%
(low) and 10% (critical), so the levels are covered. Caelestia's thresholds
are configurable and the critical level can **suspend or hibernate** the
machine on its own. simplychit only shows a dialog. Add a last-resort
`systemctl hibernate` (or `suspend`) at about 5%.

### C14. Appearance knobs
Global scaling for rounding, spacing, padding, font sizes and animation
durations, plus transparency (base and per-layer opacity). In simplychit
these are hard-coded across the CSS files under
[.config/fabric_shell/css/](home/.config/fabric_shell/css/). Move them to CSS
variables in [style.css](home/.config/fabric_shell/css/style.css) first, then
expose them in the settings file (#4).

### C15. One-command update
`caelestia update` updates the system and the dotfiles together. An
`install.sh --update` (git pull, re-stow, package sync, shell restart)
would match it.

---

## Architectural differences (not features, but worth knowing)

- **IPC surface:** DMS exposes almost everything through `dms ipc call
  <target> <action>`. [ctl.py](home/.config/fabric_shell/ctl.py) covers
  show/toggle for overlays; extending it to set state (volume, DND, night,
  wallpaper, inhibit) would make keybinds and scripts much more capable.
- **Single backend daemon:** DMS's Go backend owns DBus/Wayland state
  (network, Bluetooth, audio, telemetry) and pushes updates. simplychit mostly
  shells out and polls (`nmcli`, `bluetoothctl`, `wpctl`). Moving to DBus
  signals (NetworkManager, BlueZ, UPower) would cut latency and CPU.
- **Compositor support:** DMS supports niri, Hyprland, Sway, MangoWC, labwc
  and others. simplychit is Hyprland-only, which is fine for personal dots.
- **Lock screen and greeter in-shell:** DMS draws its own lock screen and
  greeter, so they match the theme exactly. simplychit uses hyprlock and SDDM
  with separate configs. Templating `hyprlock.conf` from pywal16 (and
  updating SDDM colours on wallpaper change) would close most of the visual gap.

---

## Suggested order

1. Polkit agent, then hypridle + auto-lock (correctness and safety; small)
2. Night light (hyprsunset), idle-inhibit and game-mode toggles in the control centre
3. Launcher: `>` actions (C1), then calc, windows, files
4. Special-workspace scratchpads (C11): a few binds and rules, big daily win
5. CPU/RAM bar meters + process list overlay
6. Bar status icons: keyboard layout, Caps Lock, network, Bluetooth (C7)
7. Monitor hotplug for bars, then per-monitor wallpaper
8. Audio device picker, VPN, power profiles in the control centre
9. Weather + dashboard overlay combining media/calendar/weather/stats
10. Lock screen: fingerprint, avatar, themed colours (C4)
11. Settings file + CSS variables (C14), then a settings UI
12. Everything in "nice to have" and the rest of the Caelestia list as the mood strikes
