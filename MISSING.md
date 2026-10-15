# What's missing compared to DankMaterialShell and Caelestia

The gaps left between SimplyChit and two other Quickshell shells:
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS)
and [Caelestia](https://github.com/caelestia-dots/shell). Everything already
built has been removed from this list; see [TODO.md](TODO.md) for what was
done and how. The numbers (3, C4, …) are kept from the original list because
TODO.md and code comments refer to them.

**Status: everything below is currently undesired.** These are kept as a
record, not as planned work. To pick one up, move it into TODO.md first.

---

## Features

### 3. Night light / gamma control — *currently undesired*
Colour temperature with a schedule or sunrise/sunset. Possible approach:
`hyprsunset` (`hyprctl hyprsunset temperature N`) with a toggle and slider
in the control centre.

### 5. System monitor / process list — *currently undesired*
The bar shows CPU temperature only. DMS has CPU/RAM/GPU usage meters and a
process list with search and kill. btop (themed) covers this for now.

### 7. Weather — *currently undesired*
A bar island and forecast popup from Open-Meteo (no API key).

### 8. Dashboard — *currently undesired*
One tabbed overlay for media, calendar agenda, weather and system stats.
SimplyChit keeps these in separate panels.

### 11. VPN connection list — *currently undesired*
VPN up/down already shows a toast (C9). Missing: a list of NetworkManager
VPN/WireGuard connections with toggles in the control centre.

### 13. Dock — *currently undesired*
Pinned and running apps along the bottom edge, with auto-hide.

### 14. Workspace overview — *currently undesired*
Window previews per workspace (`hyprexpo`, or a shell overlay with
screencopy thumbnails).

---

## Nice to have — *all currently undesired*

| Feature | Possible approach |
|---|---|
| Colour picker | `hyprpicker -a` on a key, history in a panel |
| Screenshot annotation | pipe to `satty` from the screenshot menu |
| Privacy indicators | watch PipeWire nodes for mic/camera/screenshare, dot in the bar |
| System updater | `checkupdates` + AUR count in the bar, click runs `simplychit update` |
| Browser picker | `.desktop` URL handler that asks which browser |
| Workspace rename | Hyprland `renameworkspace` from a dialog |
| User profile picture | `~/.face` in the power menu and lock screen |
| Notification grouping | group history cards by app |
| Hibernate in the power menu | only suspend is there; hibernate is in the critical-battery action |
| Auto-hide bar | drop the exclusive zone, reveal on edge hover |
| Desktop widgets | clock or meters on a bottom-layer window |
| Plugin system | not worth it for personal dots |

---

## Caelestia extras — *all currently undesired*

### C2. More colour schemes
pywal16 backends (`theme.backend`) and light/dark are done. Not done:
Material You roles (`matugen`), premade schemes, and a "smart" mode that
picks light or dark from the wallpaper's brightness.

### C3. User templates and Papirus folders
App templates (VS Code, browser, btop, hyprlock) are done. Not done: user
templates in `~/.config/simplychit/` and `papirus-folders` set to the
nearest accent colour.

### C4. Lock screen: fingerprint and face unlock
fprintd and Howdy, an avatar, power off / reboot from the lock screen.

### C5. Desktop clock and audio visualiser
A clock and a cava visualiser on the wallpaper layer, hidden when nothing
plays.

### C6. Media extras
Synced lyrics (LRCLIB), a visualiser in the media panel, a preferred player
when several are open.

### C7. Remaining bar details
Done: special-workspace chips, per-monitor bar config, scroll for volume.
Not done:
- window icons inside workspace buttons
- status icons for keyboard layout, Caps Lock, network, Bluetooth, mic
- scroll on the workspaces to switch workspace
- hover popouts
- logo and power-button islands
- tray icon substitutions, which could bring the tray back to the bar

### C8. Sidebar
A slide-in panel that holds notifications and quick toggles together.

### C10. Game mode
One toggle that turns off animations, blur, shadows and gaps, and holds
notification popups.

### C11. Scratchpad binds
The bar shows special workspaces, but there are no `togglespecialworkspace`
binds or rules that send apps to them.

### C12. Window resizer
Auto-place picture-in-picture and similar windows from a Hyprland event
listener.

### C14. Appearance knobs
`appearance.opacity` is done. Not done: global scaling for rounding,
spacing, padding, font sizes and animation speed.

---

## Other ideas — *all currently undesired*

Not from DMS or Caelestia; suggested while tidying this list.

| Idea | Possible approach |
|---|---|
| Rollback after an update | `simplychit update` records the commit (and a snapper snapshot on btrfs); `simplychit rollback` returns to it |
| Settings backup | `simplychit export` / `import` packs `~/.config/simplychit/` for a new machine |
| Alt+Tab window switcher | live thumbnails of open windows, smaller than a workspace overview (14) |
| OCR a screen region | tesseract on a region grab, to the clipboard; next to QR scan in the screenshot menu |
| Safer clipboard | skip entries password managers mark as secret, pinned entries, clear history after a set time |
| Presentation toggle (SUPER+P) | mirror / extend / this screen only, with stay awake and do not disturb on |
| Removable drives | mount and eject through udisks, in the control centre |
| Focus timer | a pomodoro in the bar that turns on do not disturb while it runs |
| Battery charge limit | `charge_control_end_threshold` (e.g. 80%) as a toggle |
| Bluetooth device batteries | headphone and mouse levels in the Bluetooth tab |
| Keyboard backlight | a slider and the OSD, through brightnessctl's `kbd_backlight` device |
| Per-app notification rules | mute, always show or no sound per app, on the Notifications page |
| Automatic do not disturb | while an app is fullscreen or the screen is shared |

---

## Not planned

- **Other compositors:** DMS supports niri, Sway and more. SimplyChit stays
  Hyprland-only.
