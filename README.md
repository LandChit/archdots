# archdots

My personal Arch + Hyprland desktop — the whole thing, ready to install.

Everything you see is themed from your wallpaper. Pick a new picture and the
bar, menus, borders and terminal all recolour to match, instantly.

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

| | |
|---|---|
| **Compositor** | Hyprland — configured in Lua |
| **Desktop shell** | `fabric_shell` — the bar, menus and notifications, written for this repo |
| **Terminal** | alacritty |
| **File manager** | dolphin |
| **Browser** | zen-browser |
| **Login screen** | SDDM, `silent` theme |
| **Shell** | zsh + oh-my-zsh |
| **Colors** | pywal — everything follows the wallpaper |

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
> Expect to fix something. Read it before you run it, and prefer a spare machine
> or a VM over the laptop you need tomorrow.

You need Arch Linux with **NetworkManager** and **Pipewire** (both are options
in `archinstall`). Then, as your normal user — not as root:

```bash
curl -fsSL https://raw.githubusercontent.com/LandChit/archdots/main/install.sh | bash
```

That's it. The installer clones the repo, installs everything, links the config
into your home folder, builds the shell, and sets up the parts that depend on
*your* machine — which graphics card to use, your monitor layout, your wallpaper
paths. It shows you each of those before writing it.

It asks before each optional group, so you can skip the ones you don't want.
Run it with `--yes` to accept every default instead, or `--help` for the full
list of options. Flatpaks are off unless you pass `--flatpak`.

Already have the repo cloned? `./install.sh` from inside it does the same thing
and skips the clone. It's safe to run again — a second run updates rather than
duplicates.

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
wal -i ~/Pictures/wallpapers/<pick-one>
cp ~/.cache/wal/colors-fabric.css ~/.config/fabric_shell/css/
```

You'll also need to edit `.config/hypr/hyprpaper.conf` and
`.config/uwsm/env-hyprland` for your own monitors and graphics card, and apply
the settings in
[DEVELOPMENT.md](DEVELOPMENT.md#settings-that-cannot-be-stowed) that can't be
stowed.

</details>

<hr>

## Making it yours

**Change the wallpaper and colors:** <kbd>SUPER</kbd> <kbd>W</kbd>.

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
python-pywal python-gobject gtk3 gtk-layer-shell libdbusmenu-gtk3 python-pip
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
paru zen-browser-bin visual-studio-code-bin hyprls-git
sddm-silent-theme
```

`paru` is built from source rather than `paru-bin`: the prebuilt binary is
linked against one libalpm version and stops working the moment pacman bumps
it. `sddm-silent-theme` is pinned to a specific version and added to `IgnorePkg`,
because a theme upgrade replaces the login screen's config.

### Flatpak — optional, off by default

Tools only. Pass `--flatpak` to install them.

```
com.github.tchx84.Flatseal    io.missioncenter.MissionCenter
org.videolan.VLC              com.obsproject.Studio
io.github.nozwock.Packet      org.gnome.Snapshot
org.gnome.TextEditor
```

<hr>

## Good to know

- The theme is hand-modified for transparency, so a few GTK apps look off in
  places.
- Dolphin's list view is broken with this Qt theme — use icon view.
- Some tray icons show a generic placeholder if the app ships an icon the theme
  doesn't have.
- Bluetooth pairing still needs `bluetoothctl` in a terminal; connecting to an
  already-paired device is one click in the control centre.
- The installer's monitor layout is a left-to-right guess. If your screens sit
  differently, edit `~/.config/hypr/config/custom/monitor.lua` — it's yours and
  it's not tracked by git.

<hr>

## For developers

How it all works, why certain decisions were made, and what's still to do:
**[DEVELOPMENT.md](DEVELOPMENT.md)**.
