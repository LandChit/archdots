# archdots

My personal Arch + Hyprland dotfiles, managed with GNU stow.

I made this repo because I'm both lazy and too incompetent to create my own install script. I am also too lazy to create my own ISO. I will create an install script for the dotfiles when it's polished...

## At a glance

| | |
|---|---|
| **Compositor** | Hyprland 0.56 — configured in **Lua**, not hyprlang |
| **Session** | uwsm (`hyprland-uwsm`) |
| **Desktop shell** | `fabric_shell` — my own bar / launcher / notifications, in this repo |
| **Terminal** | alacritty |
| **File manager** | dolphin (+ ark, kfind) |
| **Browser** | zen-browser |
| **Login manager** | SDDM, `silent` theme |
| **Login shell** | zsh + oh-my-zsh, custom `chit` theme |
| **Colors** | pywal — everything follows the wallpaper |
| **GTK theme** | `catppuccin-mocha-pink-standard+default` (modified for transparency) |
| **Qt theme** | Kvantum `KvGlass`, via qt6ct |
| **Icons** | breeze-dark |

<hr>

## Repo layout

```
.config/
  hypr/            Hyprland — hyprland.lua + config/*.lua, hyprlock, hyprpaper
  fabric_shell/    the desktop shell (Python + GTK3 layer-shell)
  wal/templates/   pywal templates — the source of all theming
  alacritty/ eza/ fastfetch/ cliphist/ fontconfig/
  Kvantum/ qt6ct/ kdeglobals    Qt theming
  uwsm/            session env (forces Hyprland onto the iGPU)
.themes/           GTK theme
.themes_sddm/      SDDM theme
.ohmyzsh_custom/   zsh theme + plugins (git submodules)
wallpapers/
.zshrc
```

Everything except `README.md` and `installscript.sh` is stowed into `$HOME`
(see `.stow-local-ignore`).

<hr>

## Theming

There is no hardcoded palette. **pywal** generates colors from the current
wallpaper, and templates in `.config/wal/templates/` push them everywhere:

| Template | Feeds | How |
|---|---|---|
| `colors-hyprland.lua` | borders, shadows | `theme.lua` does `dofile` on `~/.cache/wal/colors-hyprland.lua` |
| `colors-fabric.css` | the whole shell | copied into `fabric_shell/css/`, live-reloaded on change |
| `colors-alacritty.toml` | terminal | imported by the alacritty config |

`color4` is the accent throughout — it is the workspace highlight, the selected
row glow, the search caret and the window border gradient. Each config falls
back to a dark neutral palette if `~/.cache/wal/` is missing, so nothing breaks
on a fresh install before the first `wal` run.

To re-theme: set a wallpaper with `wal`, then hit the restart-shell keybind
(below), which re-runs `wal -R`, re-copies the palette and restarts the shell.

<hr>

## fabric_shell

A small desktop shell written with [Fabric](https://github.com/Fabric-Development/fabric)
(Python + GTK3 + layer-shell). It replaces waybar, rofi, dunst and nwg-bar.

**Three long-lived processes:**

| Process | Role |
|---|---|
| `bar.py` | one bar per monitor — window title, workspaces, tray, volume/temp/battery, clock |
| `notifications.py` | notification daemon (cards, actions, critical never auto-expires) |
| `daemon.py` | hosts the four overlays and listens on `/tmp/fabric-shell.sock` |

**Four overlays**, kept alive in the background and shown on demand — the launcher
opens instantly because it is never respawned:

- **launcher** — app search with frequency ranking, `?` prefix for a web search
- **clipboard** — `cliphist` history with image thumbnails
- **emoji** — searchable grid with a category rail, remembers your most used
- **powermenu** — full-screen scrim: lock / logout / restart / shutdown

`ctl.py toggle|show|hide <window>` sends one line to the daemon's socket; that's
what the keybinds call. Shared window, animation, keyboard and stylesheet logic
lives in `common.py`.

> Fabric isn't packaged for Arch, so it lives in a venv at
> `.config/fabric_shell/.venv` (see [Install](#install)).

<hr>

## Keybinds

`SUPER` is the mod key.

### Launching

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Return</kbd> | Terminal (alacritty) |
| <kbd>SUPER</kbd> <kbd>E</kbd> | File manager (dolphin) |
| <kbd>SUPER</kbd> <kbd>B</kbd> | Browser (zen-browser) |
| <kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>Esc</kbd> | Mission Center |

### Shell

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Space</kbd> | App launcher |
| <kbd>SUPER</kbd> <kbd>.</kbd> | Emoji picker |
| <kbd>SUPER</kbd> <kbd>V</kbd> | Clipboard history |
| <kbd>SUPER</kbd> <kbd>Esc</kbd> | Power menu |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>Ctrl</kbd> <kbd>Alt</kbd> <kbd>R</kbd> | Restart the shell (re-syncs pywal colors) |

### Windows

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>Q</kbd> | Close window |
| <kbd>SUPER</kbd> <kbd>←↑↓→</kbd> | Move focus |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>←↑↓→</kbd> | Move window |
| <kbd>SUPER</kbd> <kbd>U</kbd> / <kbd>P</kbd> | Resize narrower / wider |
| <kbd>SUPER</kbd> <kbd>I</kbd> / <kbd>O</kbd> | Resize shorter / taller |
| <kbd>SUPER</kbd> <kbd>T</kbd> | Toggle floating |
| <kbd>SUPER</kbd> <kbd>F</kbd> | Fullscreen |
| <kbd>SUPER</kbd> + drag <kbd>LMB</kbd> / <kbd>RMB</kbd> | Move / resize with mouse |

### Workspaces

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Switch to workspace 1–10 |
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Move window to workspace |

Odd workspaces live on the external monitor, even ones on the laptop screen
(`config/monitor.lua`).

### Screenshots & media

| Keys | Action |
|---|---|
| <kbd>SUPER</kbd> <kbd>Shift</kbd> <kbd>S</kbd> or <kbd>PrtSc</kbd> | Region → clipboard + `~/Pictures/screenshots/` |
| <kbd>Shift</kbd> <kbd>PrtSc</kbd> | Whole screen → same |
| Volume / mute / mic-mute keys | wpctl |
| Brightness keys | brightnessctl |
| Play / pause / next / prev | playerctl |

<hr>

## Install

### 1. Base system

Install Arch with `archinstall`, selecting:

- **NetworkManager** — network
- **Pipewire** — audio

### 2. Packages

See [Packages](#packages) below.

### 3. Dotfiles

```bash
git clone --recurse-submodules <this repo> ~/archdots
cd ~/archdots
stow .
```

### 4. Shell venv

Fabric is not in the repos, so the shell brings its own environment:

```bash
python -m venv ~/.config/fabric_shell/.venv
~/.config/fabric_shell/.venv/bin/pip install fabric pycairo PyGObject loguru click
```

### 5. First colors

```bash
wal -i ~/archdots/wallpapers/<pick-one>
```

Then log into Hyprland — `autorun.lua` starts the shell for you.

<hr>

## Packages

### Core — needed for these dotfiles

```
hyprland hyprpaper hyprlock hyprpolkitagent xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk uwsm sddm alacritty foot dolphin ark kfind
python-pywal python-gobject gtk-layer-shell python-pip
cliphist wl-clipboard grim slurp brightnessctl playerctl libnotify
pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber pavucontrol
networkmanager network-manager-applet blueman
qt6ct kvantum qt5-wayland qt6-wayland
zsh stow git
```

`foot` is only used by the launcher to run terminal apps; alacritty is the
interactive terminal. `libnotify` provides `notify-send`, which the screenshot
keybinds use to report themselves — the card is drawn by the shell's own
notification daemon.

### Utilities

```
tlp zoxide eza fzf fd bat htop nvtop fastfetch tmux unzip wget
solaar smartmontools kwallet-pam kwalletmanager flatpak
```

### Fonts

```
ttf-jetbrains-mono-nerd ttf-dejavu ttf-roboto
noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
```

JetBrainsMono Nerd Font is the shell's font — without it every glyph in the bar
renders as a box.

### AUR

```
paru zen-browser-bin visual-studio-code-bin sddm-silent-theme
hyprls-git downgrade qt5-websockets snapd
```

### Flatpak

```
com.github.tchx84.Flatseal        io.missioncenter.MissionCenter
com.interversehq.qView            org.videolan.VLC
com.obsproject.Studio             org.kde.kdenlive
com.usebottles.bottles            org.prismlauncher.PrismLauncher
org.onlyoffice.desktopeditors     org.remmina.Remmina
org.gnome.TextEditor              org.gnome.Snapshot
io.github.nozwock.Packet          io.github.kukuruzka165.materialgram
moe.launcher.an-anime-game-launcher
```

### Regenerating these lists

The lists above are curated — they cover the desktop, not every package on the machine. For everything actually installed:

```bash
pacman -Qqen          # explicit, from the official repos
pacman -Qqem          # foreign / AUR
flatpak list --app --columns=application
```

<hr>

## Known rough edges

- **GTK transparency is not uniform.** The catppuccin theme was hand-modified to
  be transparent, so it is definitely broken in places.
- **Dolphin's list view is broken** under Kvantum `KvGlass`. Use icon view.
- **Machine-specific config is not separated yet.** `config/monitor.lua` hardcodes
  my exact monitor layout (eDP-1 + HDMI-A-1 + DP-1, with transforms), and
  `uwsm/env-hyprland` pins specific DRM device paths. Both need editing on any
  other machine.
- **No install script yet.** The steps above are manual.

<hr>

## TODO

- [ ] Create a keybinds graphic
- [ ] Create a custom uniform theme
- [ ] Create an install script
- [ ] Separate machine-specific config (per-program configs, and screen configs)
- [x] Drop the unused waybar / rofi / dunst leftovers
