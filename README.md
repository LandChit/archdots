# SimplyChit

My personal Arch + Hyprland desktop — the whole thing, ready to install.

Everything you see is themed from your wallpaper. Pick a new picture and the
bar, menus, borders, terminal and your GTK apps all recolour to match.

<hr>

## What you get

A desktop built around one idea: **everything is one keypress away, and it all
looks like it belongs together.**

- **A bar** across the top with your workspaces, the current window, what's
  playing, volume, temperature, battery and a clock. The volume can be scrolled
  to change it, the battery tells you how long you have left, and the clock
  drops down a calendar.
- **An app launcher** (<kbd>SUPER</kbd> <kbd>Space</kbd>) that learns what you
  open most and puts it first. It is also a calculator (`=`), a file search
  (`/`), a window switcher (`@`), a command runner (`!`), a web search (`?`) and
  a menu of actions (`>`): light/dark mode, colour schemes, power.
- **A control centre** (<kbd>SUPER</kbd> <kbd>C</kbd>) for Wi-Fi (passwords
  included), Bluetooth (pairing included), output and input devices, a volume
  per app, brightness, power profiles, whatever's playing, and your tray icons
  — one panel instead of five apps.
- **Notifications** with a history you can scroll back through
  (<kbd>SUPER</kbd> <kbd>N</kbd>), and a do-not-disturb switch that silences
  popups while still keeping a record.
- **A wallpaper picker** (<kbd>SUPER</kbd> <kbd>W</kbd>) that changes the
  wallpaper *and* re-themes the entire desktop, without restarting anything.
- **A screenshot menu** (<kbd>SUPER</kbd> <kbd>PrtSc</kbd>) — region, window,
  whole screen, or a 5-second delay. Every shot is saved *and* copied to the
  clipboard.
- **Clipboard history** (<kbd>SUPER</kbd> <kbd>V</kbd>) and an **emoji picker**
  (<kbd>SUPER</kbd> <kbd>.</kbd>), both searchable.
- **A keybind cheatsheet** (<kbd>SUPER</kbd> <kbd>/</kbd>) that reads your
  actual keybinds — so it's never out of date, even after you change them.
- **On-screen display** for volume and brightness, a warning when the battery
  gets low (and a suspend before it runs out), and small toasts for things
  like the charger, Caps Lock or a VPN coming up.
- **Its own polkit dialog**, and an optional lock screen, in the same theme.
- **A settings app** (<kbd>SUPER</kbd> <kbd>,</kbd>) for all of it, including a
  Windows-style **Displays** page: drag your screens into place, pick modes,
  scale and rotation, and it reverts by itself unless you keep the change. It
  remembers a layout for each set of monitors you plug in.

<hr>

## At a glance

| Feature | What is used |
|---|---|
| **Compositor** | Hyprland — configured in Lua |
| **Desktop shell** | Quickshell (QML) — the bar, wallpaper, menus, notifications and OSD, written for this repo |
| **Terminal** | alacritty |
| **File manager** | dolphin |
| **Browser** | zen-browser |
| **Login screen** | SDDM, `silent` theme; or, experimental, the shell's own greeter on greetd (`install.sh --greeter`) |
| **Shell** | zsh + oh-my-zsh |
| **Colors** | pywal16 — everything follows the wallpaper, 16 distinct colours |
| **App theme** | `simplychit` — GTK 3 hand-written, GTK 4 recolours libadwaita |

<hr>

## Keybinds

`SUPER` is the Windows/Command key.

Press <kbd>SUPER</kbd> <kbd>/</kbd> at any time for a cheatsheet of every
keybind, generated from your own config.

### Apps

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Return</kbd> | Terminal |
| <kbd>SUPER</kbd> <kbd>E</kbd> | File manager |
| <kbd>SUPER</kbd> <kbd>B</kbd> | Browser |
| <kbd>SUPER</kbd> <kbd>Space</kbd> | App launcher |

### The desktop

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>C</kbd> | Control centre |
| <kbd>SUPER</kbd> <kbd>N</kbd> | Notifications |
| <kbd>SUPER</kbd> <kbd>V</kbd> | Clipboard history |
| <kbd>SUPER</kbd> <kbd>.</kbd> | Emoji picker |
| <kbd>SUPER</kbd> <kbd>W</kbd> | Wallpaper picker |
| <kbd>SUPER</kbd> <kbd>/</kbd> | Keybind cheatsheet |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>N</kbd> | Notepad (saved to `~/.local/share/simplychit/notepad.md`) |
| <kbd>SUPER</kbd> <kbd>PrtSc</kbd> | Screenshot menu |
| <kbd>SUPER</kbd> <kbd>Esc</kbd> | Power menu |
| <kbd>SUPER</kbd> <kbd>,</kbd> | Settings |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>I</kbd> | Stay awake (no dim, lock or suspend) until pressed again |

### Windows

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>Q</kbd> | Close window |
| <kbd>SUPER</kbd> <kbd>←↑↓→</kbd> | Move focus |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>←↑↓→</kbd> | Move the window |
| <kbd>SUPER</kbd> <kbd>U</kbd> <kbd>P</kbd> <kbd>I</kbd> <kbd>O</kbd> | Resize |
| <kbd>SUPER</kbd> <kbd>T</kbd> | Float / untile |
| <kbd>SUPER</kbd> <kbd>F</kbd> | Fullscreen |
| <kbd>SUPER</kbd> + drag mouse | Move or resize with the mouse |

### Workspaces

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Go to workspace |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Send window to workspace |

Media, volume and brightness keys work as expected, and show a little popup.

<hr>

## Install

> [!WARNING]
> **The installer is new and has not yet been proven on real hardware.** It has
> been tested end to end in a container — packages, linking, the shell build,
> the login theme — but nobody has run it on a fresh machine and logged in yet.
> Expect to fix something. Read it before you run it, and use a spare machine, or VM.

You need Arch Linux or an Arch-based system (EndeavourOS, CachyOS, Garuda,
Manjaro). The installer looks first and fits in with what is there: it uses
your `paru` or `yay` (or builds `paru`), and asks before switching anything
that changes how the machine boots or gets online. It replaces PulseAudio with
PipeWire only if you agree, and it switches another login screen (GDM,
LightDM, …) to SDDM or another network manager (iwd, systemd-networkd, …) to
NetworkManager only if you agree. Those switches are off by default and take
effect at the next boot; the installer prints how to undo them. On a desktop
it installs power-profiles-daemon rather than TLP, and it warns about an
NVIDIA card without its driver or a Hyprland older than these dots need.
Then, as your normal user — not as root:

```bash
curl -fsSL https://raw.githubusercontent.com/LandChit/archdots/main/install.sh | bash
```

That's it. The installer clones the repo, installs everything, links the config
into your home folder, builds the shell, and sets up the parts that depend on
*your* machine — which graphics card to use, your monitor layout, your wallpaper
paths. It shows you each of those before writing it.

The questions come up as dialog boxes when the machine has `whiptail`. There you
choose once — install, update, or pick the parts yourself — and the rest runs on
its own behind a progress bar, with everything it did kept in
`~/.local/state/simplychit/`. Pass `--no-gui` to be asked about each step in plain
text and watch the output as it happens, `--yes` to accept every default and ask
nothing at all, `--no-flatpak` to skip the flatpak applications, or `--help` for
the full list.

Already have the repo cloned? `./install.sh` from inside it does the same thing
and skips the clone. It's safe to run again — a second run updates rather than
duplicates.

**To update later:**

```bash
~/simplychit/install.sh update
```

That pulls the repo, re-links anything new, installs packages the repo has
gained since your last run, and offers to restart the running shell. Your machine-specific values — graphics card, monitor
layout, wallpaper — are not in the repo at all, so an update cannot overwrite
them.

> **Updating an install from before the dotfiles moved into `home/`** (or
> from when they were called archdots, cloned at `~/archdots`): the
> installer you have cannot know about the move. Pull first, then run the new
> one, which moves your untracked files across and relinks everything:
>
> ```bash
> git -C ~/archdots pull && ~/archdots/install.sh update
> ```
>
> Until that second command runs, the links in `~/.config` point at paths
> that no longer exist, so do it before logging out.

**The shell's own login screen** (experimental): `./install.sh install
--greeter` sets up greetd with a greeter that looks like the lock screen, and
asks before switching to it (default no). Try it in a virtual machine first:
a broken login screen leaves only a text console. To see it without
switching anything: `qs -p ~/.config/quickshell/simplychit/greeter.qml` (Esc
closes it). Back to SDDM from a console: `sudo systemctl disable greetd &&
sudo systemctl enable sddm && sudo reboot`.

**When it finishes, log out and pick Hyprland at the login screen.** The desktop
starts itself. Press <kbd>SUPER</kbd> <kbd>/</kbd> for the cheatsheet.

> **One warning:** don't install dunst, mako or swaync. This desktop draws its
> own notifications, and those would silently take over and leave you with none.
> The installer offers to remove them if it finds them.

<details>
<summary>Prefer to do it by hand?</summary>

```bash
# 1. install the packages listed below, then:
git clone https://github.com/LandChit/archdots ~/simplychit
cd ~/simplychit && stow --target="$HOME" home
# your own config goes in these (untracked); gtk.css imports user.css and
# warns on every GTK 4 app if it is missing
mkdir -p ~/.config/simplychit/local && touch ~/.config/gtk-4.0/user.css

# 2. wallpapers live here — the picker reads this folder
mkdir -p ~/Pictures/wallpapers && cp ~/simplychit/wallpapers/* ~/Pictures/wallpapers/
# --cols16 dual is what makes colours 8-15 distinct rather than copies of 0-7;
# the templates and every sheet downstream depend on it.
wal -i ~/Pictures/wallpapers/<pick-one> --cols16 dual

# 3. the shell reads the palette from ~/.cache/wal itself; GTK, hyprlock, btop
#    and the browser need their own copies (GTK CSS has no var(), for one).
~/simplychit/home/.local/bin/simplychit sync-palette

# 4. the GTK 4 recolour has to sit *beside* the file that imports it — a flatpak
#    mounts .config/gtk-4.0 inside its own per-app home, so a relative import
#    reaching back to ~/.themes silently fails and every flatpak loses its colour
cp ~/.themes/simplychit/gtk-4.0/overrides.css ~/.config/gtk-4.0/

# 5. the shell and the lock screen start from this symlink
mkdir -p ~/.local/state/simplychit
ln -sfn ~/Pictures/wallpapers/<pick-one> ~/.local/state/simplychit/wallpaper

# 6. only on a machine with two GPUs — put the integrated one first, so the
#    desktop doesn't render on the discrete card. uwsm sources this directory.
mkdir -p ~/.config/uwsm/env-hyprland.d
echo 'export AQ_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0"' \
  > ~/.config/uwsm/env-hyprland.d/10-gpu.sh
```

You'll also want a monitor layout in `~/.config/simplychit/hypr/monitor.lua`,
and the settings in
[DEVELOPMENT.md](DEVELOPMENT.md#settings-that-cannot-be-stowed) that can't be
stowed.

</details>

<hr>

## Making it yours

**Change the wallpaper and colors:** <kbd>SUPER</kbd> <kbd>W</kbd>. Apps already
open keep their old colours until you restart them — GTK reads a theme once.

**Retune the theme itself:** the colours are derived, not written down. Every
surface, border and highlight comes from the wallpaper's palette by way of
`mix()` and `alpha()`, so changing one line changes all of them consistently —
`home/.themes/simplychit/gtk-3.0/gtk.css` for GTK 3, `gtk-4.0/overrides.css` for GTK 4.
The accent is `color4` throughout, the same one the bar and window borders use.

**Change anything else** — your monitors, keybinds, mouse, terminal font,
shell aliases — without touching the originals: everything you edit lives in
`~/.config/simplychit/`. Those files are loaded after the defaults, so whatever
you write wins, and they are not in the repo, so updates never overwrite them.
[CUSTOMIZING.md](CUSTOMIZING.md) has a "to change X, edit Y" table.

**Add a keybind:** edit `~/.config/simplychit/hypr/keybind.lua` and give it a
`desc` so it shows up on the cheatsheet:

```lua
hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"), { desc = "Launch: GIMP" })
```

To change or remove a default bind, use the helper in that file's comments:
binding a combo twice runs both actions.

<hr>

## Packages

These are what `install.sh` installs. Core is what the desktop cannot start
without; everything below it is optional and can be declined.

### Core

```
hyprland hyprlock hypridle hyprpolkitagent quickshell upower
xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm sddm alacritty dolphin
cliphist wl-clipboard grim slurp brightnessctl playerctl libnotify
pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
networkmanager bluez bluez-utils blueman
qt6ct kvantum qt5-wayland qt6-wayland breeze-icons adwaita-fonts
zsh zsh-autosuggestions zsh-syntax-highlighting stow git
zoxide fzf eza bat kwallet-pam kwalletmanager base-devel
```

`zoxide`, `fzf`, `eza` and `bat` are core rather than optional because `.zshrc`
calls all four on every login — `alias cd="z"` means a missing zoxide breaks
`cd` itself. `base-devel` is what building `paru` needs. hyprlock and
hyprpolkitagent are fallbacks: the shell has its own lock screen (opt-in) and
polkit dialog.

One core package is not in the official repos:

```
python-pywal16          # AUR — paru -S python-pywal16
```

It is the maintained fork of `python-pywal`, which is unmaintained and was
itself dropped from the repos into the AUR. It both conflicts with and provides
`python-pywal`, so installing it replaces an existing pywal without a separate
removal step. `install.sh` builds `paru` and installs this regardless of whether
the optional AUR packages are wanted, because there is no palette without it.

### Fonts

```
ttf-jetbrains-mono-nerd ttf-dejavu ttf-roboto
noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
```

JetBrainsMono Nerd Font is required — without it the icons in the bar show as
empty boxes.

### Utilities — optional

```
tlp fd htop nvtop fastfetch tmux unzip wget curl smartmontools ark ddcutil
khal vdirsyncer btop
```

`tlp` on laptops only; a desktop gets `power-profiles-daemon` instead (the
control centre's power profiles need one of the two). `khal` and
`vdirsyncer` put your calendar's events in the calendar panel; they need a
one-time setup (CUSTOMIZING.md, Calendar).

### AUR — optional

```
paru zen-browser-bin visual-studio-code-bin hyprls-git xwaylandvideobridge
python-pywalfox sddm-silent-theme
```

An existing `paru` or `yay` is used as it is. Otherwise `paru` is built from
source rather than `paru-bin`: the prebuilt binary is
linked against one libalpm version and stops working the moment pacman bumps
it. `sddm-silent-theme` is pinned to a specific version and added to `IgnorePkg`,
because a theme upgrade replaces the login screen's config.

### Flatpak — installed by default

Tools only. Pass `--no-flatpak` to skip them.

```
com.github.tchx84.Flatseal    io.missioncenter.MissionCenter
org.videolan.VLC              com.obsproject.Studio
io.github.nozwock.Packet      org.gnome.Snapshot
org.gnome.TextEditor
```

<hr>

## Good to know

- The GTK 3 half of the theme is hand-written and doesn't cover every widget, so
  an unusual app may show a stray unstyled corner. GTK 4 apps are safe — that
  half recolours libadwaita's own stylesheet rather than replacing it.
- **Don't press Apply in nwg-look.** It rewrites `~/.config/gtk-4.0/settings.ini`
  and replaces `gtk.css` with a symlink into `~/.themes`, which breaks the theme
  until the next `install.sh`.
- Flatpaks need `~/.themes` in their permissions to be themed at all. Most
  request it already, and the global override grants it —
  `flatpak override --user --show` to check.
- Qt apps go through Kvantum and qt6ct instead, so they don't follow the
  wallpaper the way GTK apps do.
- Dolphin's list view is broken with this Qt theme — use icon view.
- Some tray icons show a generic placeholder if the app ships an icon the icon
  theme doesn't have.
- Bluetooth devices that need a passkey typed in still need `bluetoothctl`;
  everything else pairs and connects from the control centre.
- The installer's monitor layout is a left-to-right guess. If your screens sit
  differently, edit `~/.config/simplychit/hypr/monitor.lua` — it's yours and
  it's not tracked by git.

<hr>

## For developers

How it all works, why certain decisions were made, and what's still to do:
**[DEVELOPMENT.md](DEVELOPMENT.md)**.
