# fabric_shell — feature build-out

Working list for the shell expansion. **Update this file as each task lands** so a
fresh session can pick up where the last one stopped without re-reading everything.

Status key: `[ ]` not started · `[~]` in progress · `[x]` done

---

## Ground rules for every task

- New overlays subclass `common.Overlay` (notification-like, `exclusive = False`)
  or `common.Panel` (search-driven mode, `exclusive = True`, the default).
- Register the window in `daemon.py`'s dict, add its sheet to `common.style_screen(...)`,
  and add its name to the shared name list (see task 10).
- Every sheet lives in `css/` and is concatenated after `css/style.css`, so it
  inherits the base and only needs its own rules.
- Design language, taken from `css/style.css` and `css/battery.css`:
  - surface: `alpha(mix(var(--background), var(--color4), 0.22), 0.92–0.94)`
  - radius `18px` on windows/cards, `11–13px` on inner controls
  - border `1px solid alpha(var(--color4), 0.28)`
  - shadow `0 30px 70px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06)`
  - accent is **`--color4`** — never hardcode a colour except the danger red
    `rgb(224, 96, 78)` already used by `battery.css`
  - font `JetBrainsMono NF` @ 12.5px base; icons are Nerd Font glyphs
  - transitions 140–180ms ease; panels fade+slide via the `.anim-out` class
- Restart the shell with `SUPER+SHIFT+CONTROL+ALT+R` (runs `helpers/shell.lua`
  `restart()`, which also re-syncs pywal colours).

---

## Tasks

### 1. [~] `todolist.md` — this file
Continuity notes so work survives a context reset.

### 2. [x] OSD (volume / mic / brightness)
On-screen display card, bottom-centre, auto-dismiss after 1.6s.
- `osd.py` — `OSD(Overlay)`, `exclusive = False`, layer `overlay`, anchor bottom,
  margin `0 0 90px 0`. Reads its own value through `common.audio_state()` /
  `common.backlight_state()` rather than being told one, so a held key never
  drifts out of sync. Repeated presses restart the dismiss timer.
- `css/osd.css` — mirrors `battery.css`; a boosted sink (>100%) turns the bar
  and label the same warm red `battery.css` uses for critical.
- Socket protocol now takes an optional third token (`show osd volume`):
  `daemon.handle()` splits into `action name *args` and calls `reveal(*args)`.
- `common.py` gained `SINK`, `SOURCE`, `audio_state()`, `backlight_state()`.
- `helpers/shell.lua` gained `M.with_osd(command, kind)`; the six `XF86Audio*` /
  `XF86MonBrightness*` binds in `keybind.lua` now go through it.
- Hyprland blur needs no new rule — `rules.lua`'s `namespace = "fabric-*"`
  already matches the new `fabric-osd` window.
- Verified on screen at 175% (red), 45% (accent) and muted (dimmed + "Muted").

### 3. [x] Event-driven audio
`bar.py` used to spawn `wpctl` every 300ms; it now listens instead.
- `common.watch_audio(callback)` runs `pactl subscribe` through
  `exec_shell_command_async` and coalesces the burst of events one change
  produces into a single call (`AUDIO_DEBOUNCE_MS = 60`).
- **It returns the subprocess and the caller must keep a reference** — drop it
  and the subscription is collected with it. `bar.py` parks it on the label.
- `StatusBar._poll_volume` became `_volume_text()` + `_volume_meter()`. A slow
  10s poll (`VOLUME_FALLBACK_SECONDS`) sits behind the subscription purely to
  recover if pipewire restarts and takes `pactl subscribe` with it.
- Verified: bar reflected 33% and Muted within 0.4s, and zero `wpctl` spawns
  while idle (200 samples over 4s) against ~3.3/second before.

### 4. [x] Clickable bar islands
- `StatusBar._clickable(child, on_click, on_scroll)` wraps a meter in an
  `EventBox` and sets a hand cursor on realize. **The wrapper owns the pointer
  events, so `:hover` lands on it, not the label** — hence `.island-hot` and the
  `.island-hot:hover .clock-island` rule in `bar.css`.
- volume: scroll adjusts by `VOLUME_STEP` (wheel notches and touchpad deltas
  both), left click toggles mute. No manual label refresh — the task-3
  subscription does that. `-l 2` matches the keybind's ceiling.
- battery: left click sends `show battery`; the card now fills itself with the
  current charge and time-to-full/empty when opened by hand rather than showing
  a stale warning (`BatteryWarning._fill_status()`, `common.battery_time()`).
- clock: left click sends `toggle calendar`.
- `windows.py` grew `SOCKET_PATH` and `send()`, so the bar can talk to the
  daemon without importing fabric twice over; `ctl.py` is now a CLI over it.
  **A failed send is swallowed in the bar on purpose** — a dead daemon should
  not take a click handler down with it.
- New `calendar_popup.py` + `css/calendar.css`. **Named `calendar_popup` so it
  cannot shadow the stdlib `calendar` module**, which fabric's deps import.
- Verified: calendar renders August 2026 with today highlighted (4 open/close
  cycles), battery card read "Battery · 95% / Charging — 18m until full",
  and every scroll/click handler was exercised with synthetic events.
- One oddity worth knowing: the very first reveal once rendered the *next*
  year. Not reproducible since, but `_go_to_today()` now sets the year/month/day
  properties directly instead of stepping through `select_month()` +
  `select_day()`, which left the widget on an intermediate date between calls.

### 5. [x] Control centre
`controlcenter.py` + `css/controlcenter.css`, opened with `SUPER+C`.
Toggles (Wi-Fi / Bluetooth / Alerts), volume + brightness sliders, the nearby
networks and the paired Bluetooth devices.

- Wi-Fi: `nmcli radio wifi on|off`; list from
  `nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list`. **`-t` escapes
  literal colons in an SSID as `\:`**, so they are masked before splitting.
  Same SSID on two bands is deduped to the strongest. Clicking connects; an
  unsaved network reports that it needs a password rather than pretending.
- Bluetooth: **bluez-utils was installed mid-build (2026-08-12)**, so this is
  real device management now, not the rfkill-only fallback first planned.
  `bluetoothctl show` → `Powered: yes`; devices from
  `bluetoothctl devices Paired|Connected` (`Device AC:80:… Galaxy Buds2`).
  Powering on runs `sh -c 'rfkill unblock bluetooth; bluetoothctl power on'` —
  **`power on` fails silently while the radio is soft-blocked.** Pairing is
  still left to bluetoothctl: it needs a passkey exchange with nowhere to go.
- DND reads and writes `NotificationStore` directly (task 6), no new socket
  message. The tile says "Alerts", so it is lit when DND is *off*.
- **Networks / Bluetooth / Tray are tabs sharing one `PAGE_HEIGHT` scroller**,
  not three stacked sections. Stacked, the panel was 685px on a 1080p screen
  and grew with every extra network; tabbed it is a fixed 507px.
  `_show_page()` shows one page and hides the others — the tray is *not*
  reparented between tabs, because a `SystemTray` loses its items if you do.
  It also refreshes the page it just revealed, so an inactive tab costs
  nothing. Any new `show_all()` on a page must go through `_reveal_rows()`,
  or it un-hides the inactive pages.
- **`background-image: none` is load-bearing on the slider CSS.** The GTK theme
  paints the filled part with a gradient, so `background-color` alone left the
  fill bright pink. Same trap will apply to any future scale or progress bar.
- Verified on screen: all three toggles lit against real state, sliders in the
  accent colour, 11 networks with the connected one first, Galaxy Buds listed.

### 6. [x] Notification centre + DND
**Done before task 5 on purpose**: the control centre's DND toggle needed a real
in-process backend, and building a temporary socket message for it would have
been thrown away an hour later.

- `notifications.py` is now three pieces sharing one DBus service:
  `NotificationStore` (service + history + DND flag, with `subscribe()` so both
  windows redraw), `NotificationPopups` (the old `NotificationDaemon`, renamed)
  and `NotificationCenter` (the history window, `toggle notifications`).
- **It no longer runs as its own process** — `shell.lua`'s `MODULES` is now
  `{ "daemon", "bar" }`. Two processes would fight over the
  `org.freedesktop.Notifications` DBus name, so `RETIRED = { "notifications" }`
  was added to the kill pattern: old survivors are killed, never relaunched.
  That entry can go once no pre-2026-08-12 shell can still be running.
- DND records but suppresses: a silenced notification still lands in history.
  **Not persisted** — a restart clears it, so a muted session cannot outlive
  the reason it was muted.
- Opening the centre calls `popups.dismiss_all()`. Both windows live top-right
  and the popups are on the `overlay` layer, so otherwise they cover it.
- Keybind: `SUPER+N`.
- Two GTK gotchas found the hard way, both worth remembering:
  - an **ellipsizing label inside the scroller is handed its minimum width**
    and clips even short text — `NOTIFY-SEND` rendered as `NOTIFY-SEN…`. The
    app-name label is deliberately not ellipsized; a spacer `Box(h_expand=True)`
    pushes the timestamp right instead.
  - `x_align` positions the text block, **`justification` aligns lines within
    it** — a wrapped body centres itself without `justification="left"`.
- Verified: popup still appears; history shows newest-first with times and a
  red border on critical; store probe confirmed DND records-but-suppresses,
  clear, the 50-entry cap and the `%H:%M` format.

### 7. [x] Media / MPRIS
`media.py` holds the state and one `MediaControls` widget used twice:
- **bar island** (`hidden_when_idle=True`) — vanishes when nothing is playing,
  so the bar carries no empty gap. Uses `set_no_show_all(True)` because a
  parent's `show_all()` would otherwise reveal it.
- **control centre row** (`hidden_when_idle=False`) — stays put and reads
  "Nothing playing", so the panel does not change height between tracks.
- `playerctl --follow metadata --format '{{status}}␟{{title}}␟{{artist}}'`,
  one process, no polling. **Separator is `\x1f`**, not `|` or ` - `, because a
  track title can contain those.
- **`--follow` says nothing when a player quits**, so the island would keep
  showing a dead track — a 10s `MEDIA_FALLBACK_SECONDS` re-read covers it, the
  same safety net the volume meter uses.
- Verified against real Spotify: island showed "Antukin · Rico Blanco" with the
  pause glyph, `playerctl pause` flipped it to the play glyph, and `next`
  updated the title to "Dalangin · Earl Agustin" — so the subscription tracks a
  real player. Control centre row verified too.
- No media player is installed for testing (no mpv/vlc/mpd); Spotify was
  started by hand. `scratchpad/mpris_stub.py` in that session was a synthetic
  MPRIS player if one is ever needed again.

### 7b. [x] Bar layout — workspaces moved left
Asked for mid-build: workspaces now sit in `start_children` before the window
title instead of in `center_children`, so the centre no longer squeezes the
right-hand islands on a narrow screen.

### 8. [x] Wallpaper / theme picker
`wallpapers.py` + `css/wallpapers.css`, a `Panel` like the launcher. `SUPER+W`.
Picking one does three things:
1. `hyprctl hyprpaper wallpaper "MONITOR,PATH"` per monitor. **hyprpaper 0.8.4
   rejects `preload`** — the `wallpaper` request loads the file itself.
2. `wal -i` then copies `~/.cache/wal/colors-fabric.css` into `css/`, which
   `common.style_screen()` is already watching, so the shell recolours live.
3. Rewrites the `path =` lines in `~/.config/hypr/hyprpaper.conf` so the choice
   survives a reboot. Everything else in that file is left alone, and an
   unchanged path is a no-op.
- **Do not regex `hyprctl monitors -j` for `"name"`** — each monitor nests an
  `activeWorkspace` with its own `name`, so it returned `['eDP-1','2',...]`.
  It parses the JSON now. (Caught in testing, fixed.)
- The material picture glyph U+F0E09 is missing from JetBrainsMono NF and
  renders as a box; the fa one (U+F03E) is used instead.
- Verified end to end against a temporary second wallpaper: both monitors
  switched, hyprpaper.conf updated, palette file rewritten — then restored.
- Only one wallpaper is in `~/Pictures/wallpapers`, so the list is short until
  more are added; nothing in the code assumes a count.

### 9. [x] Screenshot menu
`screenshot.py` + `css/screenshot.css`, shaped like `powermenu.py` (same scrim
and cards). `SUPER+PRINT`; the existing direct region/full binds still work.
- Region (slurp), Window (`hyprctl activewindow -j` box → grim `-g`), Screen,
  and a 5s delay. Saves to `~/Pictures/screenshots` *and* the clipboard.
- **The filename is expanded once into `$F`.** Repeating `$(date +%F_%T)` at
  each use re-runs the clock, so a capture straddling a second would `wl-copy`
  a file that does not exist. The old keybind one-liners had this shape too.
- The menu hides 120ms before grim fires, or it lands in its own screenshot.
- Fire-and-forget with `Popen`, never `run`: **`wl-copy` stays alive holding
  the clipboard**, so waiting on it hangs forever.
- Verified: a real capture landed in `~/Pictures/screenshots`.

### 11. [x] System tray rescue (`tray.py`)
Not on the original list — the tray had silently vanished from the bar.
- Cause: fabric's `SystemTrayItem` calls `Gtk.IconTheme.load_icon`, which
  **raises** for an unknown icon name, and the exception escapes the item
  constructor. Apps advertising their own `IconThemePath` get a theme
  containing only that path, so even names the system theme *does* have
  (nm-signal-50, battery-090, blueman-tray) came back missing.
- `SafeTrayItem` catches it and retries against `Gtk.IconTheme.get_default()`,
  then falls back to a generic glyph. `SafeSystemTray` also refuses to let one
  bad item abort the rest.
- The tray now lives in the control centre, not the bar (asked for: it was an
  invisible island eating bar width). Icons render properly there.
- **Do not patch the venv** — this lives in our code so a reinstall cannot
  undo it.

### 9. [ ] Screenshot menu
Region / window / full / delayed, wrapping `grim` + `slurp`. Shaped like
`powermenu.py`. The current binds live in `hypr/config/keybind.lua`.

### 10. [x] Dedupe window names
Done alongside task 2, since both touched `ctl.py` and `daemon.py`.
New `windows.py` holds `WINDOWS` and `WINDOW_ARGS`. It deliberately imports
nothing: `ctl.py` runs on every keybind press, so pulling in `common.py` would
drag all of fabric and GTK into a process that only writes one socket line.
`daemon.py` warns at startup if `windows.py` lists a name it has no instance for.
**Add every new window's name there.**

---

## Log

- **2026-08-11** — list created; OSD (2) and window-name dedupe (10) landed.
- **2026-08-12** — OSD verified on screen; event-driven audio (3) landed and
  verified; clickable bar islands (4) landed with the calendar popup;
  notification centre + DND (6) landed ahead of the control centre so DND had a
  real backend; control centre (5) landed — bluez-utils was installed part-way
  through, so Bluetooth grew from a radio toggle into real device management.
  Starting media/MPRIS (7).

  Keybinds added: `SUPER+N` notifications, `SUPER+C` control centre,
  `SUPER+W` wallpapers, `SUPER+PRINT` screenshot menu.
- **2026-08-12 (later)** — media (7), wallpapers (8) and the screenshot menu (9)
  landed; the bar's workspaces moved left (7b); the system tray was rescued and
  moved into the control centre (11). Every item on the original list is done.
- **2026-08-13** — control centre tabbed to cap its height (685px → 507px);
  then five bugs found in real use and fixed: dunst owning notifications (12),
  the palette monitor being garbage collected (13), the 5s panel open (14),
  the static and non-round-tripping brightness slider (15), and a blocked
  Bluetooth radio reading as absent (16).

## Round 2 — bugs found in use (2026-08-13)

### 12. [x] dunst was eating every notification
The shell's notification cards never appeared: **dunst held
`org.freedesktop.Notifications`**, claimed at login by a systemd *user service*
(`dunst.service`), which is why nothing in this repo hinted at it. fabric's
service cannot take a name someone else already owns, so the daemon's
notification support sat idle.
- Fixed by stopping dunst; the fabric daemon picked the name up immediately.
  The dunst package was then uninstalled, so no mask is needed.
- **If notifications ever go quiet again, check the name owner first:**
  `busctl --user status org.freedesktop.Notifications` — compare its PID with
  `pgrep -f fabric_shell/daemon.py`. Anything else (mako, swaync, a
  reinstalled dunst) will silently win the race at login.
- Knock-on effect worth knowing: **`blueman-applet` is what emits the
  "device connected / disconnected" popups**, and it sends them as ordinary
  desktop notifications. While enabled they render as shell cards in the top
  right and expire on the sender's timeout. **Nothing in this shell draws a
  centred Bluetooth popup** — the only centred card is the battery warning
  (`battery.py`, no anchor, so layer-shell centres it), auto-dismissing after
  20s unless the level is critical.

### 18. [x] The centred "Galaxy Buds2 — Connected 86%" window
Reported as a popup the shell was drawing. It was not — **that was blueman's
own GTK fallback window**, which it draws instead of sending a notification
whenever nothing owns `org.freedesktop.Notifications`. Told apart from a shell
card by the giveaway in the screenshot: it had a *title bar*, so it was a real
window, not a layer-shell surface.

It only appeared right after a reboot because blueman-applet is started by
systemd at session start, while the shell comes up later from Hyprland's
`autorun.lua` (which also sleeps and runs `wal -R` first). A headset
auto-connecting in that gap had no daemon to notify.

Fixed by disabling the plugin that sends it — see the repo-root `todolist.md`,
since it is a dconf setting and cannot be stowed:

    gsettings set org.blueman.general plugin-list "['!ConnectionNotifier']"

An earlier attempt reordered startup (a `Hidden=true` autostart override plus a
`gdbus wait` in `autorun.lua`) so blueman could never beat the shell to the bus.
**That was reverted** — turning the plugin off is simpler and needs no ordering
guarantees. Worth knowing if connect notifications are ever re-enabled: the
race comes back, and the fallback window with it.

### 13. [x] Wallpaper changes only recoloured after a restart
`monitor_file()` **returns a `Gio.FileMonitor`, and `common.py` threw it away.**
A GFileMonitor stops watching the moment it is garbage collected, so the palette
watch died almost immediately and only a restart re-read the colours.
- `common._MONITORS` now holds them for the life of the process.
- **Same trap as `watch_audio()` and `media.watch()`** — anything returning a
  monitor or a subprocess must be parked on something long-lived. Verified by
  rewriting the palette live: the bar recoloured without a restart.

### 14. [x] Control centre took ~5s to open
Not window creation — the windows really are kept alive and merely hidden.
`reveal()` ran `nmcli device wifi list` **synchronously on the GTK main loop**,
and nmcli forces a scan: 4872ms. The same query with `--rescan no` returns the
identical twelve networks in 25ms.
- `wifi_networks()` now reads the cache; a real scan runs via
  `process.wait_async()` and redraws the list when it lands.
- `reveal()` shows the window first and fills it from `GLib.idle_add`, so no
  reader can delay the panel appearing. Measured 21–27ms to mapped, most of
  which is `ctl.py`'s own Python startup.
- **Never call a blocking subprocess before `show()`** in any panel.

### 15. [x] Brightness slider was static, and did not round-trip
Two separate problems in one row:
- No live updates: brightnessctl has nothing to subscribe to, unlike PipeWire.
  A 700ms poll now runs **only while the panel is visible** (a 3ms sysfs read),
  with a 1.5s settle window after a drag so it cannot fight the handle.
- **The slider wrote `-e4` (exponential) but read the linear percentage** from
  `brightnessctl -m`: asking for 45% read back as 4%, so the handle jumped on
  the next poll. The panel now writes linear (`brightnessctl -n2 set N%`), which
  round-trips exactly. The *keybinds* keep `-e4` on purpose — relative steps
  want a perceptual curve; only the absolute slider needs the linear scale.

### 16. [x] A blocked Bluetooth radio looked like missing hardware
`bluetoothctl show` reports no controller when the radio is soft-blocked, which
`bluetooth_powered()` could not tell apart from having no adapter — so the tile
greyed out and claimed "No Bluetooth adapter found" when one click could have
fixed it. `bluetooth_present()` now asks rfkill as well; blocked counts as
"off, but switchable".

### 17. [x] Clock was changing format when clicked
Clicking the clock swapped it to "Wednesday", then "08-13-2026", instead of
just opening the calendar. Not a bug in our code — **fabric's `DateTime`
defaults to `formatters=("%I:%M %p", "%A", "%m-%d-%Y")` and cycles them on
left click, right click and scroll.**
- Fixed by passing a single formatter (`CLOCK_FORMAT`). With one entry its own
  cycling handler is a no-op, so the click means only "open the calendar".
- The clock is a `Button` already, so it is now wired directly rather than
  wrapped in an `EventBox` — `_clickable()` is for plain Labels. The hand
  cursor moved to a shared `_set_hand_cursor()`.
- Verified by emitting a real `button-press-event`: the label stayed put and
  the calendar surface went from 0 to 1.

### 19. [x] Bluetooth "off" did not survive a reboot
The control centre turned Bluetooth off with `bluetoothctl power off`, which
only clears the adapter's runtime `Powered` property. **bluez powers on every
controller it finds at startup** — `/etc/bluetooth/main.conf` documents
*"AutoEnable ... Defaults to 'true'"* and leaves the line commented — so the
toggle quietly undid itself on the next boot.

`rfkill` state is the part that persists: systemd-rfkill saves it at shutdown
to `/var/lib/systemd/rfkill/pci-…:bluetooth` and restores it at boot. The off
branch now runs `bluetoothctl power off; rfkill block bluetooth`, pairing with
the on branch that was already `rfkill unblock bluetooth; bluetoothctl power on`.

Verified both directions by reading the persisted file rather than trusting the
UI: off wrote `1`, on wrote `0`. (`systemctl stop systemd-rfkill.socket` forces
the save that normally happens at shutdown, so this is testable without
rebooting.)

### 20. [x] Keybind cheatsheet (`keybinds.py`, `SUPER` + `/`)
Full-screen sheet built from `hyprctl binds -j` on every open, so binds from
`hypr/config/custom/keybind.lua` appear with no change here.

**The naming problem, and the only answer.** Under the Lua config provider
Hyprland registers *every* bind as a `__lua` callback: `hyprctl binds -j`
reports `dispatcher: "__lua"` with an opaque index, so the key combo is
knowable and the action is not. All 63 binds looked identical. The one field
that survives is `description`, set per bind with `desc` in Lua — verified by
round-trip (`desc = "Terminal"` → `has_description: true`). So `keybind.lua`
now carries a `desc` on every bind, by convention `"Group: Label"`.

- Undescribed binds are shown under an **Undescribed** card, deliberately
  styled as unfinished. Hiding them would make a new bind look broken.
- Binds sharing a group+label collapse into one row. **Collapse only folds
  digits (`1…0`) and arrows (`←→↑↓`)** — an earlier version folded any
  single-character key and rendered the four focus binds as the nonsense
  "←…↓".
- The footer counts binds *before* collapsing. Counting rows claimed "48 binds"
  when Hyprland had 64.
- `make_scroller()` already sets `h_align`; passing it again is a duplicate
  keyword argument that killed the daemon at startup.

### 21. [x] All icons reverting to placeholders (`tray.py`, round 2)
Reported as "close a widget and it loses all icons, reverts to default, and a
shell restart does not help". Not a widget bug at all — **fabric's tray was
destroying the process-wide icon theme.**

`fabric/system_tray/service.py`:

```python
self._icon_theme = Gtk.IconTheme.get_default()
self._icon_theme.set_search_path([search_path])   # if the item ships one
```

`get_default()` is the **shared** theme for the whole process, and
`set_search_path` *replaces* the path rather than appending. One tray item
advertising its own `IconThemePath` (spotify does) leaves the daemon with a
theme that can only see that single directory, so every later lookup fails —
tray, launcher app icons, notification icons alike. Restarting never helped
because the same item re-registers and re-breaks it within seconds.

The giveaway: inside the daemon, `Gtk.IconTheme.get_default().has_icon(
"nm-signal-50")` was False while the identical call in a standalone process
said True. Same theme name, same venv — the daemon's copy had been mutated.

`tray.py` now resolves icons itself and **never touches fabric's
`item.icon_theme`**: embedded pixmap first, then the icon name looked up in a
*private* `Gtk.IconTheme` built from `_PRISTINE_SEARCH_PATH` (captured at
import, before any item can register) plus the item's own directory, then a
generic glyph. `restore_default_search_path()` also repairs the shared theme
after each item is added, in case anything else reaches for it.

Note this supersedes the earlier fix in item 11: catching the exception and
retrying against `get_default()` only worked while the shared theme was still
intact, which is why the icons came back for one session and then stopped.

Verified: four real tray icons instead of four placeholders, unchanged across
close/reopen cycles, and launcher app icons intact after cycling every window.

## Where to pick up next

Nothing is outstanding. Natural next steps if you want them:

- **Bluetooth pairing.** To be clear, `bluetoothctl` *is* installed (it ships
  with bluez-utils) and the panel uses it for everything it does — reading
  `Powered`, listing paired devices, connecting and disconnecting. What the
  panel does **not** do is *pair a new device*, because pairing needs a passkey
  prompt it has nowhere to display. So: connecting = one click in the panel,
  first-time pairing = `bluetoothctl` in a terminal. Adding scan-and-pair to
  the panel means a confirmation dialog for the passkey — a real feature, not
  a missing dependency.
- The bar and the daemon each open their own `playerctl --follow`. Harmless,
  but they could share one if a third consumer ever appears.
- `RETIRED` in `helpers/shell.lua` — see below; it can go whenever you like.

### `RETIRED = { "notifications" }` — when to delete it

It exists so a restart kills any `notifications.py` left over from before the
daemon absorbed notifications; two processes would fight over the
`org.freedesktop.Notifications` DBus name. The condition to delete it is simply
"no process started from the old config can still be alive", which was already
true on 2026-08-12: no `notifications.py` was running, and `MODULES` no longer
launches one, so a reboot cannot produce one either.

**Delete it once these changes are committed** — until then a `git checkout` of
the old tree could still start one. Nothing else depends on it, and keeping it
costs one line, so there is no hurry either way.
