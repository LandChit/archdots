# archdots

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
  open most and puts it first. Type `?` and it searches the web instead.
- **A control centre** (<kbd>SUPER</kbd> <kbd>C</kbd>) for Wi-Fi, Bluetooth,
  volume, brightness, whatever's playing, and your tray icons — one panel
  instead of five apps.
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
- **On-screen display** for volume and brightness, and a warning when the
  battery gets low.

<hr>

## At a glance

| Feature | What is used |
|---|---|
| **Compositor** | Hyprland — configured in Lua |
| **Desktop shell** | `fabric_shell` — the bar, menus and notifications, written for this repo |
| **Terminal** | alacritty |
| **File manager** | dolphin |
| **Browser** | zen-browser |
| **Login screen** | SDDM, `silent` theme |
| **Shell** | zsh + oh-my-zsh |
| **Colors** | pywal16 — everything follows the wallpaper, 16 distinct colours |
| **App theme** | `archdots` — GTK 3 hand-written, GTK 4 recolours libadwaita |

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
| <kbd>SUPER</kbd> <kbd>PrtSc</kbd> | Screenshot menu |
| <kbd>SUPER</kbd> <kbd>Esc</kbd> | Power menu |

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

You need Arch Linux with **NetworkManager** and **Pipewire** (both are options
in `archinstall`). Then, as your normal user — not as root:

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
`~/.local/state/archdots/`. Pass `--no-gui` to be asked about each step in plain
text and watch the output as it happens, `--yes` to accept every default and ask
nothing at all, `--no-flatpak` to skip the flatpak applications, or `--help` for
the full list.

Already have the repo cloned? `./install.sh` from inside it does the same thing
and skips the clone. It's safe to run again — a second run updates rather than
duplicates.

**To update later:**

```bash
~/archdots/install.sh update
```

That pulls the repo, re-links anything new, installs packages the repo has
gained since your last run, refreshes the shell's virtualenv, and offers to
restart the running shell. Your machine-specific values — graphics card, monitor
layout, wallpaper — are not in the repo at all, so an update cannot overwrite
them.

**When it finishes, log out and pick Hyprland at the login screen.** The desktop
starts itself. Press <kbd>SUPER</kbd> <kbd>/</kbd> for the cheatsheet.

> **One warning:** don't install dunst, mako or swaync. This desktop draws its
> own notifications, and those would silently take over and leave you with none.
> The installer offers to remove them if it finds them.

<details>
<summary>Prefer to do it by hand?</summary>

```bash
# 1. install the packages listed below, then:
git clone --recurse-submodules https://github.com/LandChit/archdots ~/archdots
cd ~/archdots && stow .

# 2. build the desktop shell
python -m venv ~/.config/fabric_shell/.venv
~/.config/fabric_shell/.venv/bin/pip install -r ~/.config/fabric_shell/requirements.txt

# 3. wallpapers live here — the picker reads this folder
mkdir -p ~/Pictures/wallpapers && cp ~/archdots/wallpapers/* ~/Pictures/wallpapers/
# --cols16 dual is what makes colours 8-15 distinct rather than copies of 0-7;
# the templates and every sheet downstream depend on it.
wal -i ~/Pictures/wallpapers/<pick-one> --cols16 dual

# 4. the rendered palettes are not tracked, so write them where each consumer
#    looks. GTK gets its own format because GTK CSS has no var().
cp ~/.cache/wal/colors-fabric.css ~/.config/fabric_shell/css/
for d in ~/.themes/archdots/gtk-3.0 ~/.themes/archdots/gtk-4.0 ~/.config/gtk-4.0; do
  cp ~/.cache/wal/colors-gtk.css "$d/colors.css"
done

# 5. the GTK 4 recolour has to sit *beside* the file that imports it — a flatpak
#    mounts .config/gtk-4.0 inside its own per-app home, so a relative import
#    reaching back to ~/.themes silently fails and every flatpak loses its colour
cp ~/.themes/archdots/gtk-4.0/overrides.css ~/.config/gtk-4.0/

# 6. the desktop and the lock screen read this symlink, not a path in a config
mkdir -p ~/.local/state/archdots
ln -sfn ~/Pictures/wallpapers/<pick-one> ~/.local/state/archdots/wallpaper

# 7. only on a machine with two GPUs — put the integrated one first, so the
#    desktop doesn't render on the discrete card. uwsm sources this directory.
mkdir -p ~/.config/uwsm/env-hyprland.d
echo 'export AQ_DRM_DEVICES="/dev/dri/card1:/dev/dri/card0"' \
  > ~/.config/uwsm/env-hyprland.d/10-gpu.sh
```

You'll also want a monitor layout in `.config/hypr/config/custom/monitor.lua`,
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
`.themes/archdots/gtk-3.0/gtk.css` for GTK 3, `gtk-4.0/overrides.css` for GTK 4.
The accent is `color4` throughout, the same one the bar and window borders use.

**Change settings for your machine** — your monitors, your mouse, your
graphics card — without touching the originals: put them in
`.config/hypr/config/custom/`. There's a file in there for each part of the
config, they're loaded after the defaults, and whatever you write wins. They're
also kept out of git, so your changes stay yours.
[More detail here](DEVELOPMENT.md#per-machine-config).

**Add a keybind:** edit `.config/hypr/config/custom/keybind.lua` and give it a
`desc` so it shows up on the cheatsheet:

```lua
hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"), { desc = "Launch: GIMP" })
```

<hr>

## Packages

These are what `install.sh` installs. Core is what the desktop cannot start
without; everything below it is optional and can be declined.

### Core

```
hyprland hyprpaper hyprlock hyprpolkitagent xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk uwsm sddm alacritty dolphin
python-gobject gtk3 gtk-layer-shell libdbusmenu-gtk3 python-pip
cliphist wl-clipboard grim slurp brightnessctl playerctl libnotify
pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
networkmanager bluez bluez-utils blueman
qt6ct kvantum qt5-wayland qt6-wayland breeze-icons adwaita-fonts
zsh stow git zoxide fzf eza bat kwallet-pam kwalletmanager
base-devel cairo gobject-introspection pkgconf
```

`zoxide`, `fzf`, `eza` and `bat` are core rather than optional because `.zshrc`
calls all four on every login — `alias cd="z"` means a missing zoxide breaks
`cd` itself. `base-devel`, `cairo`, `gobject-introspection` and `pkgconf` are
there because pip compiles pycairo and PyGObject from source.

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
tlp fd htop nvtop fastfetch tmux unzip wget curl smartmontools ark
```

### AUR — optional

```
paru zen-browser-bin visual-studio-code-bin hyprls-git xwaylandvideobridge
sddm-silent-theme
```

`paru` is built from source rather than `paru-bin`: the prebuilt binary is
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
- Bluetooth pairing still needs `bluetoothctl` in a terminal; connecting to an
  already-paired device is one click in the control centre.
- The installer's monitor layout is a left-to-right guess. If your screens sit
  differently, edit `~/.config/hypr/config/custom/monitor.lua` — it's yours and
  it's not tracked by git.

<hr>

## For developers

How it all works, why certain decisions were made, and what's still to do:
**[DEVELOPMENT.md](DEVELOPMENT.md)**.
