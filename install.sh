#!/usr/bin/env bash
#
# archdots installer — https://github.com/LandChit/archdots
#
# Two ways to run it:
#
#   curl -fsSL https://raw.githubusercontent.com/LandChit/archdots/main/install.sh | bash
#   ./install.sh          # from inside an existing clone
#
# It clones the repo (with submodules) if it is not already in one, installs the
# packages, stows the dotfiles, builds the shell's virtualenv, and writes the
# handful of settings that are specific to *this* machine — GPU order, monitor
# layout, wallpaper paths — after showing you each one.
#
# Once installed, `./install.sh update` pulls the repo, re-links, refreshes the
# packages and the virtualenv, and offers to restart the running shell.
#
# The prompts are whiptail dialogs when whiptail (libnewt) is present and there
# is a terminal to draw on. Everything works without it: pass --no-gui, or -y,
# or run it from something that is not a tty, and the same questions are asked
# as plain text on stdout.
#
# Run it as your normal user. It calls sudo where it needs to and nowhere else:
# stow, the venv and every gsettings call must run as you, not as root.

set -euo pipefail

# ── settings ────────────────────────────────────────────────────────────────

REPO_URL_DEFAULT="https://github.com/LandChit/archdots"
REPO_DIR_DEFAULT="$HOME/archdots"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# The SDDM theme is pinned. Its config schema changes between releases, and
# .themes_sddm/ holds a default.conf written against this one.
SDDM_THEME_VERSION="1.3.5"

# Packages. These mirror README.md#packages — keep the two in step.
#
# Core is what the desktop cannot start without. Everything else is optional and
# lives further down, because a package that is merely nice to have should not
# be able to fail an install.
PKG_CORE=(
    hyprland hyprpaper hyprlock hyprpolkitagent
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm sddm
    alacritty dolphin
    python-pywal python-gobject gtk3 gtk-layer-shell python-pip
    # fabric.system_tray does gi.require_version("DbusmenuGtk3", "0.4") at
    # import time, and daemon.py imports it through controlcenter -> tray. Miss
    # this and *every* overlay dies with the daemon — launcher, clipboard,
    # notifications, control centre, the lot — while bar.py keeps running, so
    # the desktop looks half-alive rather than broken. pip cannot supply it:
    # it is a typelib, not a wheel.
    libdbusmenu-gtk3
    cliphist wl-clipboard grim slurp brightnessctl playerctl libnotify
    pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
    networkmanager bluez bluez-utils blueman
    qt6ct kvantum qt5-wayland qt6-wayland
    # GTK side of the theming. .config/gtk-3.0/settings.ini names both of these
    # by name; without them GTK silently falls back to Adwaita *light* and the
    # shell renders white panels with unreadable text.
    breeze-icons adwaita-fonts
    zsh stow git
    # .zshrc calls all four unconditionally — `eval "$(zoxide init zsh)"` plus
    # `alias cd="z"`, `alias ls="eza …"`, `alias cat="bat"`, `eval "$(fzf --zsh)"`.
    # Leaving any of them out breaks the login shell, `cd` included.
    zoxide fzf eza bat
    # hypr/config/autorun.lua starts kwalletmanager5 and pam_kwallet_init.
    kwallet-pam kwalletmanager
    # whiptail, for this script's own dialogs. Cheap, and it means the *next*
    # run — an update, or a re-run after a change — gets the boxes even if this
    # one had to fall back to plain prompts.
    libnewt
    # pip compiles pycairo and PyGObject from source rather than fetching
    # wheels, so their build dependencies have to be present. base-devel is
    # also what makepkg needs to bootstrap paru.
    base-devel cairo gobject-introspection pkgconf
)

# JetBrainsMono Nerd is required — without it every glyph in the bar is a box.
# Noto covers emoji (the picker) and CJK; dejavu and roboto are the generic
# fallbacks GTK and Qt reach for when an app asks for a family neither has.
PKG_FONTS=(
    ttf-jetbrains-mono-nerd ttf-dejavu ttf-roboto
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
)

PKG_UTILS=(
    tlp fd htop nvtop fastfetch tmux unzip wget curl smartmontools ark
)

PKG_AUR=(
    zen-browser-bin visual-studio-code-bin hyprls-git
    xwaylandvideobridge   # started by autorun.lua; moved out of extra to the AUR
)

# Tools only. Media players, office suites and game launchers are a matter of
# taste and are quicker to install by hand than to argue with in a script.
PKG_FLATPAK=(
    com.github.tchx84.Flatseal
    io.missioncenter.MissionCenter
    org.videolan.VLC
    com.obsproject.Studio
    io.github.nozwock.Packet
    org.gnome.Snapshot
    org.gnome.TextEditor
)

# The shell owns org.freedesktop.Notifications. Any of these takes that bus
# name at login and the shell's cards silently never appear.
PKG_CONFLICTS=(dunst mako swaync)

# ── options ─────────────────────────────────────────────────────────────────

MODE=""                 # install | update; empty means "ask, or install"
ASSUME_YES=0
WANT_GUI=1              # whiptail dialogs, when they are available
REPO_URL="$REPO_URL_DEFAULT"
REPO_DIR="$REPO_DIR_DEFAULT"
WANT_UTILS=1
WANT_AUR=1
WANT_FLATPAK=0
DO_PACKAGES=1
DO_STOW=1
DO_VENV=1
DO_MACHINE=1

usage() {
    cat <<'EOF'
archdots installer

Usage: install.sh [install|update] [options]

  install             Full install (the default).
  update              Pull the repo, re-link, refresh the packages and the
                      virtualenv, and offer to restart the running shell.

  -y, --yes           Take the default for every prompt (non-interactive).
                      Implies --no-gui.
      --no-gui        Plain-text prompts instead of whiptail dialogs.
                      (--gui forces the dialogs back on.)
      --repo URL      Clone from URL instead of the default remote.
      --dir PATH      Clone into PATH (default: ~/archdots).
      --flatpak       Also install the flatpak applications (off by default).
      --no-utils      Skip the utility packages.
      --no-aur        Skip paru and every AUR package.
      --skip-packages Install nothing; only link, build and configure.
      --skip-stow     Do not run stow.
      --skip-venv     Do not build the fabric_shell virtualenv.
      --skip-machine  Do not touch machine-specific config (GPU, monitors,
                      wallpaper paths).
  -h, --help          This text.

Run as your normal user, not as root.
EOF
}

ARGS_ORIGINAL=("$@")

case "${1:-}" in
    install|update) MODE="$1"; shift ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)        ASSUME_YES=1 ;;
        --gui)           WANT_GUI=1 ;;
        --no-gui|--no-tui|--plain) WANT_GUI=0 ;;
        --update)        MODE="update" ;;
        --repo)          REPO_URL="${2:?--repo needs a URL}"; shift ;;
        --dir)           REPO_DIR="${2:?--dir needs a path}"; shift ;;
        --flatpak)       WANT_FLATPAK=1 ;;
        --no-utils)      WANT_UTILS=0 ;;
        --no-aur)        WANT_AUR=0 ;;
        --skip-packages) DO_PACKAGES=0 ;;
        --skip-stow)     DO_STOW=0 ;;
        --skip-venv)     DO_VENV=0 ;;
        --skip-machine)  DO_MACHINE=0 ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ── output ──────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; BLU=$'\033[34m'; R=$'\033[0m'
else
    B=''; DIM=''; RED=''; GRN=''; YEL=''; BLU=''; R=''
fi

SUMMARY=()
note()    { SUMMARY+=("$1"); }
step()    { printf '\n%s==>%s %s%s%s\n' "$BLU" "$R" "$B" "$1" "$R"; }
say()     { printf '    %s\n' "$1"; }
ok()      { printf '    %s✓%s %s\n' "$GRN" "$R" "$1"; }
skip()    { printf '    %s·%s %s\n' "$DIM" "$R" "$1"; }
warn()    { printf '    %s!%s %s\n' "$YEL" "$R" "$1" >&2; }
die()     { printf '\n%serror:%s %s\n' "$RED" "$R" "$1" >&2; exit 1; }

# ── the prompts ─────────────────────────────────────────────────────────────
#
# Every question goes through this layer, and it has two backends:
#
#   whiptail  boxes, when libnewt is installed and there is a terminal to draw
#             on. Only the *questions* are drawn — pacman, makepkg and pip keep
#             printing to the terminal as they always did, because hiding a
#             half-hour compile behind a fake progress bar helps nobody.
#   plain     the same questions on stdout, read from /dev/tty.
#
# Plain is not a degraded mode, it is a supported one: -y, --no-gui, a pipe, a
# container with no TERM, and a machine that does not have whiptail yet all end
# up there, and all of them have to work.

UI="plain"
BACKTITLE="archdots — Arch + Hyprland desktop"

# Piped from curl, stdin is the script itself, so every prompt — plain or
# whiptail — reads from /dev/tty instead.
have_tty() { [[ -r /dev/tty && -w /dev/tty ]]; }

ui_init() {
    (( WANT_GUI ))     || return 0
    (( ! ASSUME_YES )) || return 0
    have_tty           || return 0
    command -v whiptail >/dev/null || return 0
    [[ -n "${TERM:-}" && "$TERM" != "dumb" ]] || return 0
    UI="whiptail"
}

# Box geometry. whiptail does not size itself to its text, so measure the text:
# widest line for the width, line count for the height, both clamped to
# something that still fits a small terminal.
wt_width() {
    local text="$1" max=0 len line
    while IFS= read -r line; do
        len=${#line}
        (( len > max )) && max=$len
    done <<< "$text"
    (( max += 8 ))
    (( max < 50 )) && max=50
    (( max > 76 )) && max=76
    printf '%s' "$max"
}
wt_height() {
    local text="$1" extra="${2:-6}" lines
    lines="$(wt_lines "$text" "$(wt_width "$text")")"
    (( lines += extra ))
    (( lines < 8 ))  && lines=8
    (( lines > 22 )) && lines=22
    printf '%s' "$lines"
}

# How many rows the text will occupy once whiptail has wrapped it to the box.
wt_lines() {
    local text="$1" width="$(( ${2:-76} - 6 ))" total=0 line len
    while IFS= read -r line; do
        len=${#line}
        (( total += len / width + 1 ))
    done <<< "$text"
    printf '%s' "$total"
}

# Nothing here uses --scrolltext, deliberately. A scrollable whiptail widget
# puts the keyboard focus in the text pane, so Enter scrolls instead of pressing
# a button and the dialog looks frozen until you think to press Tab; given a box
# taller than its own text it also draws a broken scrollbar over the border.
# Long content is clipped for the box and printed in full to the terminal
# instead, which scrolls the way people expect.
wt_clip() {
    local text="$1" rows="${2:-14}" total
    total="$(printf '%s\n' "$text" | wc -l)"
    if (( total <= rows )); then
        printf '%s' "$text"
    else
        printf '%s\n… %s more line(s), printed in full in the terminal' \
            "$(printf '%s\n' "$text" | head -n "$rows")" "$(( total - rows ))"
    fi
}

# whiptail draws the widget on stdout and answers on stderr, so the answer is
# captured with 2>&1 while the widget itself is pushed at the terminal.
wt() {
    whiptail --backtitle "$BACKTITLE" "$@" 2>&1 1>/dev/tty </dev/tty
}
# For widgets that answer with an exit status only, and so need no capture.
wt_status() {
    whiptail --backtitle "$BACKTITLE" "$@" >/dev/tty </dev/tty
}

# Ask a yes/no question. $2 is the default taken by --yes and by a bare Enter.
confirm() {
    local prompt="$1" default="${2:-y}" reply
    if (( ASSUME_YES )) || ! have_tty; then
        [[ $default == y ]]
        return
    fi
    if [[ $UI == whiptail ]]; then
        local defaultno=() text
        [[ $default == y ]] || defaultno=(--defaultno)
        text="$(wt_clip "$prompt")"
        wt_status --title "archdots" "${defaultno[@]}" \
            --yesno "$text" "$(wt_height "$text")" "$(wt_width "$text")"
        return
    fi
    local hint="[Y/n]"; [[ $default == y ]] || hint="[y/N]"
    read -r -p "    ${prompt} ${hint} " reply </dev/tty || reply=""
    reply="${reply:-$default}"
    [[ ${reply,,} == y* ]]
}

# Ask for a line of text, falling back to $2 under --yes or on a bare Enter.
ask() {
    local prompt="$1" default="$2" reply
    if (( ASSUME_YES )) || ! have_tty; then
        printf '%s' "$default"
        return
    fi
    if [[ $UI == whiptail ]]; then
        # Cancel means "leave it alone", which is the default, not an abort.
        reply="$(wt --title "archdots" --inputbox "$prompt" \
            "$(wt_height "$prompt" 8)" "$(wt_width "$prompt")" "$default")" || reply=""
        printf '%s' "${reply:-$default}"
        return
    fi
    read -r -p "    ${prompt} [${default}] " reply </dev/tty || reply=""
    printf '%s' "${reply:-$default}"
}

# Pick one of several tagged options. Arguments after the default are
# tag/description pairs. Prints the chosen tag.
choose() {
    local prompt="$1" default="$2"; shift 2
    if (( ASSUME_YES )) || ! have_tty; then
        printf '%s' "$default"
        return
    fi
    if [[ $UI == whiptail ]]; then
        # A menu's height has to cover the prompt *and* the list, or whiptail
        # silently drops rows off the bottom of the box.
        local reply rows height
        rows=$(( $# / 2 ))
        height=$(( $(wt_lines "$prompt" 76) + rows + 8 ))
        (( height > 20 )) && height=20
        reply="$(wt --title "archdots" --default-item "$default" \
            --menu "$prompt" "$height" 76 "$rows" "$@")" || reply=""
        printf '%s' "${reply:-$default}"
        return
    fi
    # The menu goes to stderr, not stdout: the caller reads this function
    # through $(…), and anything printed on stdout would be swallowed into the
    # answer. read -p already writes its prompt to stderr for the same reason.
    local tag desc
    printf '    %s\n' "$prompt" >&2
    while (( $# )); do
        tag="$1"; desc="$2"; shift 2
        printf '      %s) %s\n' "$tag" "$desc" >&2
    done
    ask "Which?" "$default"
}

# Show a generated file and ask whether to write it. The two are one operation,
# because the point of showing it is to answer the question.
review_confirm() {
    local path="$1" body="$2" prompt="${3:-Write it?}"
    if (( ASSUME_YES )) || ! have_tty; then
        return 0
    fi
    # The full text goes to the terminal either way. In dialog mode the box
    # shows as much of it as fits and the scrollback keeps the rest.
    printf '    %s--- %s%s\n' "$DIM" "$path" "$R"
    printf '%s\n' "$body" | sed "s/^/    ${DIM}|${R} /"
    printf '    %s---%s\n' "$DIM" "$R"

    if [[ $UI == whiptail ]]; then
        local text
        text="$path

$(wt_clip "$body" 12)"
        wt_status --title "$prompt" --yes-button "Write" --no-button "Skip" \
            --yesno "$text" "$(wt_height "$text")" 76
        return
    fi
    confirm "$prompt" y
}

# ── guards ──────────────────────────────────────────────────────────────────

(( EUID != 0 )) || die "do not run this as root — stow, the venv and gsettings must run as your user."
command -v pacman >/dev/null || die "pacman not found. This installer is for Arch Linux."
command -v sudo   >/dev/null || die "sudo not found. Install it and add your user to a wheel rule."

ui_init

printf '\n%sarchdots%s — Arch + Hyprland desktop\n' "$B" "$R"
# $USER is not exported by every shell — it is absent in a bare container and
# when piped from curl, which under `set -u` would abort on the banner.
say "user: $(id -un)    home: $HOME"
(( ASSUME_YES )) && say "running non-interactively (--yes)"
[[ $UI == plain ]] && (( ! ASSUME_YES )) && say "plain-text prompts (whiptail not in use)"

# ── the repo ────────────────────────────────────────────────────────────────
#
# The script may be running from a clone, or piped straight from curl on a bare
# install. Work out which, and clone if there is nothing to work with.

find_repo_root() {
    local dir
    # Piped from curl there is no BASH_SOURCE path to resolve.
    [[ -f "${BASH_SOURCE[0]}" ]] || return 1
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 1
    # A clone is identifiable by these two, which exist nowhere else.
    [[ -f "$dir/.stow-local-ignore" && -d "$dir/.config/fabric_shell" ]] || return 1
    printf '%s' "$dir"
}

locate_repo() {
    step "Locating the repository"
    if REPO_ROOT="$(find_repo_root)"; then
        ok "running from $REPO_ROOT"
        if [[ -d "$REPO_ROOT/.git" ]]; then
            # .ohmyzsh_custom carries the zsh plugins as submodules; a plain
            # clone leaves those directories empty and zsh then starts without
            # them.
            if git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null | grep -q '^-'; then
                say "submodules are empty — initialising"
                git -C "$REPO_ROOT" submodule update --init --recursive
                ok "submodules initialised"
            else
                skip "submodules already present"
            fi
        fi
    else
        command -v git >/dev/null || {
            say "git is missing; installing it first"
            sudo pacman -Sy --needed --noconfirm git
        }
        if [[ -e "$REPO_DIR" ]]; then
            if [[ -f "$REPO_DIR/.stow-local-ignore" ]]; then
                ok "existing clone at $REPO_DIR"
                git -C "$REPO_DIR" submodule update --init --recursive
            else
                die "$REPO_DIR exists and is not an archdots clone. Move it, or pass --dir."
            fi
        else
            say "cloning $REPO_URL into $REPO_DIR"
            git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
            ok "cloned"
        fi
        REPO_ROOT="$REPO_DIR"

        # Hand over to the freshly cloned copy so the rest of the run uses the
        # version that is actually on disk.
        if [[ "${ARCHDOTS_REEXEC:-}" != 1 ]]; then
            say "handing over to $REPO_ROOT/install.sh"
            export ARCHDOTS_REEXEC=1
            exec bash "$REPO_ROOT/install.sh" ${ARGS_ORIGINAL+"${ARGS_ORIGINAL[@]}"}
        fi
    fi
    cd "$REPO_ROOT"
}

# ── packages ────────────────────────────────────────────────────────────────

pac_install() {
    (( $# )) || return 0
    sudo pacman -S --needed --noconfirm "$@"
}

# Build paru from source, unless a working one is already here.
ensure_paru() {
    if command -v paru >/dev/null && paru --version &>/dev/null; then
        skip "paru already installed"
        return 0
    fi
    if command -v paru >/dev/null; then
        # A paru that will not even print its version is the libalpm break: the
        # binary is linked against the pacman that was current when it was
        # packaged, and pacman has moved since.
        warn "paru is installed but broken (libalpm mismatch) — rebuilding"
    fi
    # Built from source, not paru-bin. paru-bin ships a prebuilt binary against
    # one libalpm soname; the moment pacman bumps it that binary dies with
    # 'error while loading shared libraries: libalpm.so.N'. Compiling here links
    # against the pacman actually installed.
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
    ( cd "$tmp/paru" && makepkg -si --noconfirm )
    rm -rf "$tmp"; trap - EXIT
    paru --version &>/dev/null || die "paru still will not run after a source build."
    ok "built from source and installed"
}

stage_packages() {
    if (( ! DO_PACKAGES )); then
        step "Packages"
        skip "skipped (--skip-packages)"
        return 0
    fi

    step "Removing conflicting notification daemons"
    local installed_conflicts=() pkg
    for pkg in "${PKG_CONFLICTS[@]}"; do
        pacman -Qq "$pkg" &>/dev/null && installed_conflicts+=("$pkg")
    done
    if (( ${#installed_conflicts[@]} )); then
        warn "installed: ${installed_conflicts[*]}"
        say "the desktop shell *is* the notification daemon — it owns"
        say "org.freedesktop.Notifications. Each of these grabs that bus name at"
        say "login, and the shell's notifications then silently never appear."
        if confirm "Installed: ${installed_conflicts[*]}

The desktop shell *is* the notification daemon — it owns org.freedesktop.Notifications. Each of these grabs that bus name at login, and the shell's notifications then silently never appear.

Remove them?" y; then
            sudo pacman -Rns --noconfirm "${installed_conflicts[@]}"
            ok "removed"
            note "removed conflicting notification daemon(s): ${installed_conflicts[*]}"
        else
            warn "left installed — expect no notifications until they are gone"
            note "${installed_conflicts[*]} still installed; notifications will not work"
        fi
    else
        skip "none installed"
    fi

    step "Core packages and fonts"
    say "${#PKG_CORE[@]} core + ${#PKG_FONTS[@]} font packages"
    sudo pacman -Syu --needed --noconfirm "${PKG_CORE[@]}" "${PKG_FONTS[@]}"
    ok "installed"

    if (( WANT_UTILS )) && confirm "Install the utility packages (${#PKG_UTILS[@]})?

${PKG_UTILS[*]}" y; then
        step "Utilities"
        pac_install "${PKG_UTILS[@]}"
        ok "installed"
    else
        skip "utilities"
    fi

    if (( WANT_AUR )) && confirm "Install paru and the AUR packages (${#PKG_AUR[@]})?

${PKG_AUR[*]}

paru is built from source, which takes a few minutes." y; then
        step "paru"
        ensure_paru

        step "AUR packages"
        # One failed build should not lose the rest of the install.
        paru -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: paru -S ${PKG_AUR[*]}"
        }
        ok "done"
    else
        skip "AUR"
    fi

    if (( WANT_FLATPAK )) || confirm "Install the flatpak tools (${#PKG_FLATPAK[@]})?

${PKG_FLATPAK[*]}" n; then
        step "Flatpaks"
        command -v flatpak >/dev/null || pac_install flatpak
        flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
        flatpak install -y flathub "${PKG_FLATPAK[@]}" || {
            warn "some flatpaks failed to install"
            note "some flatpaks failed; re-run the flatpak install by hand"
        }
        ok "done"
    else
        skip "flatpaks"
    fi
}

# ── the SDDM theme ──────────────────────────────────────────────────────────
#
# Three separate things, all outside $HOME and so none of them stowable:
# the theme package, the greeter config in /etc, and the theme's own
# default.conf — which this repo overrides with an edited copy.

install_sddm_theme() {
    step "SDDM theme (silent $SDDM_THEME_VERSION)"

    local theme_dir="/usr/share/sddm/themes/silent"
    local custom_conf="$REPO_ROOT/.themes_sddm/silent_sddmTheme_custom_default/default.conf"

    # ── the package, pinned ─────────────────────────────────────────────────
    local have=""
    have="$(pacman -Qi sddm-silent-theme 2>/dev/null | awk '/^Version/{print $3}')" || true

    if [[ "${have%%-*}" == "$SDDM_THEME_VERSION" ]]; then
        skip "sddm-silent-theme $have already installed"
    elif ! command -v paru >/dev/null; then
        warn "paru not available — skipping the theme"
        note "install by hand: paru -S sddm-silent-theme (then pin it)"
        return 0
    else
        # The AUR has no version tags, so walk PKGBUILD history for the newest
        # commit that declares the pkgver we want and build from there.
        local tmp commit=""
        tmp="$(mktemp -d)"
        git clone --quiet https://aur.archlinux.org/sddm-silent-theme.git "$tmp/theme" || {
            rm -rf "$tmp"
            warn "could not reach the AUR — skipping the theme"
            note "install by hand: paru -S sddm-silent-theme"
            return 0
        }
        local c
        while read -r c; do
            if git -C "$tmp/theme" show "$c:PKGBUILD" 2>/dev/null \
                | grep -qx "pkgver=$SDDM_THEME_VERSION"; then
                commit="$c"; break
            fi
        done < <(git -C "$tmp/theme" log --format=%H -- PKGBUILD)

        if [[ -z "$commit" ]]; then
            warn "no PKGBUILD in the AUR history declares pkgver=$SDDM_THEME_VERSION"
            say "building the current version instead"
        else
            say "building from $(git -C "$tmp/theme" log -1 --format=%h "$commit") (pkgver=$SDDM_THEME_VERSION)"
            git -C "$tmp/theme" checkout --quiet "$commit"
        fi

        # The theme depends on redhat-fonts, which is itself an AUR package, and
        # makepkg resolves dependencies with pacman only — so `makepkg -si`
        # dies on "target not found: redhat-fonts". Install the declared deps
        # through paru first. Read them from the PKGBUILD rather than hardcoding
        # them, so a version bump cannot silently drift from this list.
        local deps=()
        mapfile -t deps < <(
            cd "$tmp/theme" && bash -c 'source ./PKGBUILD; printf "%s\n" "${depends[@]}"' 2>/dev/null
        )
        if (( ${#deps[@]} )); then
            say "theme dependencies: ${deps[*]}"
            paru -S --needed --noconfirm "${deps[@]}" || {
                rm -rf "$tmp"
                warn "could not install the theme's dependencies"
                note "SDDM theme skipped; retry: paru -S sddm-silent-theme"
                return 0
            }
        fi

        ( cd "$tmp/theme" && makepkg -si --noconfirm ) || {
            rm -rf "$tmp"
            warn "theme build failed — the desktop still works, the login screen is plain"
            note "SDDM theme failed to build; retry: paru -S sddm-silent-theme"
            return 0
        }
        rm -rf "$tmp"
        ok "installed"
    fi

    # ── the version lock ────────────────────────────────────────────────────
    # A theme upgrade would replace default.conf and can change the config
    # schema out from under the edited copy, so hold it where it is.
    if grep -qE '^IgnorePkg.*\bsddm-silent-theme\b' /etc/pacman.conf; then
        skip "already pinned in /etc/pacman.conf"
    elif confirm "Pin sddm-silent-theme so pacman never upgrades it?

An upgrade replaces the theme's default.conf, which this repo overrides with an edited copy written against $SDDM_THEME_VERSION." y; then
        if grep -qE '^IgnorePkg' /etc/pacman.conf; then
            sudo sed -i 's/^\(IgnorePkg.*\)$/\1 sddm-silent-theme/' /etc/pacman.conf
        else
            # There is a commented template under [options]; add a live one.
            sudo sed -i '0,/^\[options\]/s//[options]\nIgnorePkg = sddm-silent-theme/' \
                /etc/pacman.conf
        fi
        grep -qE '^IgnorePkg.*sddm-silent-theme' /etc/pacman.conf \
            && ok "pinned in /etc/pacman.conf" \
            || warn "could not pin it — add 'IgnorePkg = sddm-silent-theme' by hand"
    fi

    # ── the edited default.conf ─────────────────────────────────────────────
    if [[ ! -f "$custom_conf" ]]; then
        warn "$custom_conf missing — leaving the theme's own config"
    elif [[ ! -d "$theme_dir" ]]; then
        warn "$theme_dir does not exist — theme not installed"
    elif sudo cmp -s "$custom_conf" "$theme_dir/configs/default.conf"; then
        skip "default.conf already matches the repo copy"
    else
        # The theme ships its own; keep it so the change is reversible.
        [[ -f "$theme_dir/configs/default.conf.orig" ]] \
            || sudo cp "$theme_dir/configs/default.conf" "$theme_dir/configs/default.conf.orig"
        sudo install -Dm644 "$custom_conf" "$theme_dir/configs/default.conf"
        ok "installed the repo's default.conf (original kept as default.conf.orig)"
        note "SDDM theme config is a root-owned copy — re-run install.sh after editing .themes_sddm/"
    fi

    # ── the greeter config ──────────────────────────────────────────────────
    # QML2_IMPORT_PATH is not optional: without it the greeter loads with no
    # components and SDDM falls back to a blank screen.
    local sddm_conf="/etc/sddm.conf.d/10-archdots.conf"
    local sddm_body="# Written by archdots install.sh.
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=$theme_dir/components/,QT_IM_MODULE=qtvirtualkeyboard
Numlock=on

[Theme]
Current=silent"

    if [[ -f "$sddm_conf" ]] && [[ "$(sudo cat "$sddm_conf")" == "$sddm_body" ]]; then
        skip "$sddm_conf already correct"
    elif review_confirm "$sddm_conf" "$sddm_body" "Write it? (needs root)"; then
        sudo mkdir -p /etc/sddm.conf.d
        printf '%s\n' "$sddm_body" | sudo tee "$sddm_conf" >/dev/null
        ok "wrote $sddm_conf"
    else
        skip "greeter config"
        note "SDDM will not use the silent theme until $sddm_conf exists"
    fi
}

# ── stow ────────────────────────────────────────────────────────────────────

stage_stow() {
    if (( ! DO_STOW )); then
        step "Linking the dotfiles"
        skip "skipped (--skip-stow)"
        return 0
    fi

    step "Linking the dotfiles into \$HOME"
    command -v stow >/dev/null || die "stow is not installed (--skip-packages was used?)"

    # stow refuses to overwrite a real file. Find those first so the failure is
    # a question rather than a wall of errors.
    # stow aborts the entire run on any conflict, and reports them on stderr as
    # a "WARNING! stowing . would cause conflicts:" block. Only one shape is
    # fixable here — an ordinary file sitting where a link should go:
    #   * cannot stow <source> over existing target <path> since neither a
    #     link nor a directory and --adopt not specified
    # Anything else (an absolute symlink in the package, say) needs a human, so
    # collect the unrecognised lines rather than proceeding into a hard failure.
    local simulate line rel src backup
    local conflicts=() unhandled=()
    simulate="$(stow --simulate --verbose=1 --target="$HOME" . 2>&1 || true)"
    while IFS= read -r line; do
        [[ "$line" == *"  * "* ]] || continue
        if [[ "$line" =~ cannot\ stow\ .*\ over\ existing\ target\ (.+)\ since ]]; then
            conflicts+=("${BASH_REMATCH[1]}")
        else
            unhandled+=("${line#*\* }")
        fi
    done <<< "$simulate"

    if (( ${#unhandled[@]} )); then
        warn "stow reported a conflict this script cannot resolve:"
        printf '        %s\n' "${unhandled[@]}"
        say "an entry in the repo root that should not be stowed belongs in"
        say ".stow-local-ignore. Fix that and re-run."
        die "refusing to continue with an unresolved stow conflict."
    fi

    if (( ${#conflicts[@]} )); then
        warn "${#conflicts[@]} existing file(s) are in the way:"
        printf '        %s\n' "${conflicts[@]}"
        backup="$HOME/.archdots-backup-$(date +%Y%m%d-%H%M%S)"
        if confirm "${#conflicts[@]} existing file(s) sit where the dotfiles need to go:

$(printf '%s\n' "${conflicts[@]}")

Move them to $backup and continue?" y; then
            for rel in "${conflicts[@]}"; do
                src="$HOME/$rel"
                [[ -e "$src" ]] || continue
                mkdir -p "$backup/$(dirname "$rel")"
                mv "$src" "$backup/$rel"
            done
            ok "backed up to $backup"
            note "pre-existing dotfiles moved to $backup"
        else
            die "cannot stow with those files in place."
        fi
    fi

    stow --restow --target="$HOME" .
    ok "stowed into $HOME"
}

# ── zsh ─────────────────────────────────────────────────────────────────────

stage_zsh() {
    step "zsh"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        skip "oh-my-zsh already installed"
    elif ! command -v curl >/dev/null; then
        warn "curl not available — skipping oh-my-zsh"
        note "oh-my-zsh not installed; .zshrc sources it and will error on login"
    elif confirm "Install oh-my-zsh? (.zshrc expects it)" y; then
        # --keep-zshrc is essential: without it the installer replaces the .zshrc
        # symlink stow just created with its own template.
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended --keep-zshrc
        ok "installed"
    else
        skip "oh-my-zsh"
        note "oh-my-zsh not installed; .zshrc sources it and will error on login"
    fi

    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" == */zsh ]]; then
        skip "zsh is already your login shell"
    elif confirm "Make zsh your login shell?" y; then
        # Through sudo, which is already authenticated. A bare chsh prompts for
        # the password again and stalls an unattended run.
        if sudo chsh -s /usr/bin/zsh "$(id -un)"; then
            ok "login shell set to zsh (takes effect next login)"
        else
            warn "could not change the login shell"
            note "run it yourself: chsh -s /usr/bin/zsh"
        fi
    fi
}

# ── the shell's virtualenv ──────────────────────────────────────────────────

stage_venv() {
    step "fabric_shell virtualenv"
    if (( ! DO_VENV )); then
        skip "skipped (--skip-venv)"
        return 0
    fi

    local mode="${1:-install}"
    local venv="$HOME/.config/fabric_shell/.venv"
    local reqs="$HOME/.config/fabric_shell/requirements.txt"

    if [[ ! -f "$reqs" ]]; then
        warn "$reqs not found — did stow run?"
        note "venv skipped: requirements.txt missing"
        return 0
    fi

    [[ -d "$venv" ]] || python -m venv "$venv"
    say "installing fabric (this compiles pycairo and PyGObject — slow)"
    # The absolute path matters. A bare `-r requirements.txt` resolves against
    # the working directory, which here is the repo root, where no such file
    # exists.
    "$venv/bin/pip" install --upgrade pip >/dev/null
    local pip_args=(install -r "$reqs")
    # On an update, requirements.txt may have moved to a newer fabric.
    [[ "$mode" == "upgrade" ]] && pip_args=(install --upgrade -r "$reqs")
    if "$venv/bin/pip" "${pip_args[@]}"; then
        ok "$venv"
    else
        # Non-fatal so the machine config below still gets written.
        warn "fabric failed to build — the bar and overlays will not start"
        note "retry: $venv/bin/pip install -r $reqs"
    fi
}

# ── wallpapers ──────────────────────────────────────────────────────────────
#
# The picker reads ~/Pictures/wallpapers (wallpapers.py:29), so that is where the
# repo's wallpapers have to land — the repo directory itself is not searched.

WALLPAPER=""

stage_wallpapers() {
    step "Wallpapers"
    mkdir -p "$WALLPAPER_DIR"
    local copied=0 wall total candidate
    shopt -s nullglob
    for wall in "$REPO_ROOT"/wallpapers/*; do
        [[ -f "$wall" ]] || continue
        if [[ ! -e "$WALLPAPER_DIR/$(basename "$wall")" ]]; then
            cp "$wall" "$WALLPAPER_DIR/"
            copied=$(( copied + 1 ))
        fi
    done
    shopt -u nullglob
    total="$(find "$WALLPAPER_DIR" -maxdepth 1 -type f | wc -l)"
    ok "$WALLPAPER_DIR ($copied copied, $total total)"

    # Pick the wallpaper everything else will point at.
    WALLPAPER=""
    shopt -s nullglob
    for candidate in "$WALLPAPER_DIR"/*; do
        [[ -f "$candidate" ]] && { WALLPAPER="$candidate"; break; }
    done
    shopt -u nullglob
    [[ -n "$WALLPAPER" ]] || warn "no wallpaper found — the desktop starts on its fallback palette"
}

# ── machine-specific config ─────────────────────────────────────────────────
#
# Everything below differs per machine. The Lua bits go in config/custom/, which
# is gitignored and loaded after the defaults. The rest are tracked files that
# have to be edited in place — those are listed in the summary at the end.

stage_machine() {
    if (( ! DO_MACHINE )); then
        step "Machine-specific config"
        skip "skipped (--skip-machine)"
        return 0
    fi

    step "Detecting this machine"

    # ── GPUs ────────────────────────────────────────────────────────────────
    # AQ_DRM_DEVICES tells Hyprland which card to render on, in order of
    # preference. The integrated GPU goes first; a discrete NVIDIA card leading
    # the list makes Hyprland render the whole desktop on it.
    local drm_igpu=() drm_nvidia=() card name vendor
    shopt -s nullglob
    for card in /dev/dri/card*; do
        name="$(basename "$card")"
        vendor="$(cat "/sys/class/drm/$name/device/vendor" 2>/dev/null || true)"
        if [[ "$vendor" == "0x10de" ]]; then
            drm_nvidia+=("$card")
        else
            drm_igpu+=("$card")
        fi
    done
    shopt -u nullglob
    local drm_ordered=(${drm_igpu+"${drm_igpu[@]}"} ${drm_nvidia+"${drm_nvidia[@]}"})

    say "GPUs: ${#drm_ordered[@]} (${drm_ordered[*]:-none})"

    # This file is *tracked*, and it ships with the author's card paths in it.
    # Leaving it alone is therefore not a neutral choice: it hands every other
    # machine a pin to devices that do not exist there, and aquamarine responds
    # by failing to create a DRI screen, falling back to kms_swrast and then
    # dying on DRM_IOCTL_MODE_CREATE_DUMB. So it is always rewritten to describe
    # *this* machine, even when the answer is "no pin needed".
    local env_file="$HOME/.config/uwsm/env-hyprland" env_body drm_list=""
    if (( ${#drm_ordered[@]} > 1 )); then
        drm_list="$(IFS=:; printf '%s' "${drm_ordered[*]}")"
        env_body="# Which GPU Hyprland renders on, in order of preference.
# Written by install.sh for this machine — these paths are not portable, and
# card numbering can change between boots. If the session ever comes up on the
# wrong GPU, re-run install.sh or use a stable name from /dev/dri/by-path/.
export AQ_DRM_DEVICES=\"$drm_list\""
    else
        # One GPU (or none, as in a container): there is nothing to choose
        # between, and a pin can only be wrong. Ship the file with the export
        # commented out rather than carrying another machine's value.
        env_body="# Which GPU Hyprland renders on. Written by install.sh.
#
# This machine has ${#drm_ordered[@]} DRM device(s), so there is nothing to pick
# between and the variable is deliberately left unset — pinning a single card
# only risks naming one that is absent after a reboot or on other hardware.
#
# On a multi-GPU machine install.sh writes the real ordering here, integrated
# GPU first, so the desktop does not render on a discrete card.
#
# export AQ_DRM_DEVICES=\"/dev/dri/card1:/dev/dri/card0\""
    fi

    if [[ -f "$env_file" ]] && [[ "$(cat "$env_file")" == "$env_body" ]]; then
        skip "env-hyprland already matches this machine"
    elif review_confirm "$env_file" "$env_body"; then
        # > follows the symlink, so this edits the tracked file in the repo.
        printf '%s\n' "$env_body" > "$env_file"
        if (( ${#drm_ordered[@]} > 1 )); then
            ok "AQ_DRM_DEVICES=$drm_list"
        else
            ok "AQ_DRM_DEVICES left unset (${#drm_ordered[@]} GPU detected)"
        fi
        note "edited tracked file .config/uwsm/env-hyprland (GPU selection)"
    else
        warn "env-hyprland left as-is — it still pins another machine's cards"
        note "env-hyprland pins GPU paths that may not exist here; edit it by hand"
    fi

    # ── monitors ────────────────────────────────────────────────────────────
    # Hyprland is the authority when it is running. Before first login, the DRM
    # connector names in sysfs are the same names Hyprland uses.
    local monitors=() conn n m
    if command -v hyprctl >/dev/null && hyprctl monitors -j &>/dev/null; then
        # Parse the JSON properly. Grepping for "name" also matches the nested
        # activeWorkspace object and yields workspace numbers as monitor names.
        mapfile -t monitors < <(
            hyprctl monitors -j \
                | python3 -c 'import json,sys; [print(m["name"]) for m in json.load(sys.stdin)]' \
                2>/dev/null \
            || hyprctl monitors | grep -oP '^Monitor \K\S+'
        )
        say "monitors (from Hyprland): ${monitors[*]:-none}"
    else
        shopt -s nullglob
        for conn in /sys/class/drm/card*-*; do
            [[ -r "$conn/status" ]] || continue
            [[ "$(cat "$conn/status")" == connected ]] || continue
            n="$(basename "$conn")"
            monitors+=("${n#card*-}")
        done
        shopt -u nullglob
        say "monitors (from sysfs): ${monitors[*]:-none detected}"
    fi

    if (( ! ${#monitors[@]} )); then
        warn "no monitors detected — write config/custom/monitor.lua after first login"
        note "monitor layout not generated; see DEVELOPMENT.md#per-machine-config"
        return 0
    fi

    # A built-in panel is the sane primary when there is one.
    local primary="${monitors[0]}" secondary=""
    for m in "${monitors[@]}"; do
        [[ "$m" == eDP-* ]] && { primary="$m"; break; }
    done
    if (( ${#monitors[@]} > 1 )) && [[ $UI == whiptail ]]; then
        # With several to choose from, a menu beats retyping a connector name.
        local menu_items=()
        for m in "${monitors[@]}"; do menu_items+=("$m" "connected output"); done
        primary="$(choose "Which monitor is the primary one?

Workspaces and the lock screen favour it." "$primary" "${menu_items[@]}")"
    else
        primary="$(ask "Primary monitor?" "$primary")"
    fi

    for m in "${monitors[@]}"; do
        [[ "$m" != "$primary" ]] && { secondary="$m"; break; }
    done

    # Lay them out left to right at 1920 intervals. Anything more precise is a
    # decision only you can make, and this file is yours to edit.
    local mon_body="-- Per-machine monitor layout, generated by install.sh.
-- Loaded after config/monitor.lua, so these win. Gitignored — edit freely.
-- The positions are a left-to-right guess; adjust them to match your desk.
"
    local x=0
    for m in "${monitors[@]}"; do
        mon_body+="
hl.monitor({
    output = \"$m\",
    mode = \"preferred\",
    position = \"${x}x0\",
    scale = 1.0,
})"
        x=$(( x + 1920 ))
    done

    mon_body+="

-- The committed default splits workspaces across two monitors named for
-- another machine. Send them somewhere that exists here instead.
"
    if [[ -n "$secondary" ]]; then
        mon_body+="for workspace = 1, 10 do
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = workspace % 2 == 0 and \"$primary\" or \"$secondary\",
    })
end

hl.workspace_rule({ workspace = \"2\", monitor = \"$primary\",   default = true, persistent = true })
hl.workspace_rule({ workspace = \"1\", monitor = \"$secondary\", default = true, persistent = true })"
    else
        mon_body+="for workspace = 1, 10 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = \"$primary\" })
end

hl.workspace_rule({ workspace = \"1\", monitor = \"$primary\", default = true, persistent = true })"
    fi

    local custom_dir="$HOME/.config/hypr/config/custom"
    mkdir -p "$custom_dir"
    local mon_file="$custom_dir/monitor.lua"

    if [[ -s "$mon_file" ]]; then
        skip "$mon_file already exists — left alone"
    elif review_confirm "$mon_file" "$mon_body"; then
        printf '%s\n' "$mon_body" > "$mon_file"
        ok "wrote $mon_file"
        # A broken override is reported rather than fatal, but catching it here
        # is cheaper than reading ~/.cache/hypr-custom.log later.
        if command -v luac >/dev/null; then
            luac -p "$mon_file" && ok "syntax checks out" \
                || warn "generated Lua does not parse — check it before logging in"
        fi
        note "review ~/.config/hypr/config/custom/monitor.lua — positions are a guess"
    else
        skip "monitor.lua"
    fi

    # ── wallpaper paths ─────────────────────────────────────────────────────
    # hyprpaper.conf and hyprlock.conf are tracked files carrying one machine's
    # monitor names and one user's home directory.
    [[ -n "$WALLPAPER" ]] || return 0

    local hyprpaper="$HOME/.config/hypr/hyprpaper.conf"
    # An empty monitor means "every output" to hyprpaper — the same catch-all
    # the picker uses when it sends `hyprctl hyprpaper wallpaper ",path"`.
    # Naming monitors here instead looks tidier but silently shows nothing the
    # moment an output is named differently than it was at install time: a dock,
    # a new cable, a nested session. A black desktop with no error is the result.
    local paper_body="# Written by install.sh.
# The empty monitor is deliberate: it means every output, so this keeps working
# when the monitors change. The wallpaper picker (SUPER + W) rewrites the path
# line when you pick a new one.
splash = false

wallpaper {
    monitor =
    path = $WALLPAPER
}"
    if review_confirm "$hyprpaper" "$paper_body"; then
        printf '%s\n' "$paper_body" > "$hyprpaper"
        ok "hyprpaper.conf points at $WALLPAPER"
        note "edited tracked file .config/hypr/hyprpaper.conf (monitors + wallpaper)"
    else
        skip "hyprpaper.conf"
    fi

    local hyprlock="$HOME/.config/hypr/hyprlock.conf"
    if [[ -f "$hyprlock" ]] && grep -q '^[[:space:]]*path[[:space:]]*=' "$hyprlock"; then
        # --follow-symlinks, or sed replaces the stow symlink with a regular
        # file and the repo copy quietly stops being the source.
        sed -i --follow-symlinks \
            "s|^\([[:space:]]*path[[:space:]]*=[[:space:]]*\).*|\1$WALLPAPER|" \
            "$hyprlock"
        ok "hyprlock.conf background set"
        note "edited tracked file .config/hypr/hyprlock.conf (wallpaper path)"
    fi
}

# ── first pywal run ─────────────────────────────────────────────────────────
#
# Without this the shell starts on its hardcoded fallback palette and nothing is
# themed from the wallpaper.

stage_theming() {
    step "Theming"
    if [[ -z "$WALLPAPER" ]]; then
        skip "no wallpaper to theme from"
    elif ! command -v wal >/dev/null; then
        warn "python-pywal not installed — skipping"
        note "run once pywal is installed: wal -i $WALLPAPER"
    elif ! wal -i "$WALLPAPER" -n -q; then
        warn "pywal failed — the shell will start on its fallback palette"
        note "run by hand: wal -i $WALLPAPER"
    else
        ok "palette generated from $(basename "$WALLPAPER")"
        # Every shell window watches this copy, not pywal's cache.
        local css_src="$HOME/.cache/wal/colors-fabric.css"
        local css_dst="$HOME/.config/fabric_shell/css/colors-fabric.css"
        if [[ -f "$css_src" ]]; then
            cp "$css_src" "$css_dst"
            ok "palette copied into fabric_shell/css/"
            note "edited tracked file .config/fabric_shell/css/colors-fabric.css (palette)"
        else
            warn "$css_src missing — is .config/wal/templates/ stowed?"
        fi
    fi
}

# ── settings that cannot be stowed ──────────────────────────────────────────
#
# GSettings live in ~/.config/dconf/user, a binary database. Only a command can
# set them.

stage_dconf() {
    step "dconf settings"

    # ── GTK theme ───────────────────────────────────────────────────────────
    # .config/gtk-3.0/settings.ini is stowed and is what GTK3 itself reads, but
    # anything going through XSettings/portals (and GTK4) asks dconf instead.
    # Both have to agree or apps disagree about whether they are light or dark.
    local gtk_theme="" icon_theme=""
    if command -v gsettings >/dev/null; then
        gtk_theme="$(awk -F= '/^gtk-theme-name=/{print $2}' \
            "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null)"
        icon_theme="$(awk -F= '/^gtk-icon-theme-name=/{print $2}' \
            "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null)"
        if [[ -n "$gtk_theme" ]]; then
            gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null \
                && ok "gtk-theme = $gtk_theme" || warn "could not set gtk-theme"
            gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
            [[ -n "$icon_theme" ]] && gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null
            ok "colour scheme = prefer-dark, icons = ${icon_theme:-default}"
        else
            warn "no gtk-theme-name in .config/gtk-3.0/settings.ini — was stow run?"
        fi
        if [[ ! -d "$HOME/.themes/$gtk_theme" && ! -d "/usr/share/themes/$gtk_theme" ]]; then
            warn "theme '$gtk_theme' not found in ~/.themes or /usr/share/themes"
            note "GTK will fall back to Adwaita light and the shell will look washed out"
        fi
    fi

    # ── blueman ─────────────────────────────────────────────────────────────
    if ! command -v gsettings >/dev/null; then
        skip "gsettings not available"
        return 0
    elif ! pacman -Qq blueman &>/dev/null; then
        skip "blueman not installed"
        return 0
    fi

    say "blueman draws its own centred window when it connects a device before"
    say "the shell has claimed the notification bus — which is exactly what"
    say "happens at boot, when a headset auto-connects."
    local choice
    choice="$(choose "blueman draws its own centred popup when it connects a device before the shell has claimed the notification bus — which is what happens at boot, when a headset auto-connects.

What should it do?" "1" \
        1 "Disable ConnectionNotifier — stops the popup" \
        2 "Disable both plugins — also stops auto-reconnect" \
        3 "Leave blueman alone")"
    case "$choice" in
        1)
            gsettings set org.blueman.general plugin-list "['!ConnectionNotifier']" \
                && ok "ConnectionNotifier disabled" \
                || { warn "gsettings failed (no dbus session?)"; note "run later: gsettings set org.blueman.general plugin-list \"['!ConnectionNotifier']\""; }
            ;;
        2)
            # AutoConnect *performs* the reconnect and only notifies afterwards,
            # so disabling it costs the auto-reconnect too.
            gsettings set org.blueman.general plugin-list \
                "['!ConnectionNotifier', '!AutoConnect']" \
                || { warn "gsettings failed (no dbus session?)"; note "set the blueman plugin-list by hand"; }
            ok "ConnectionNotifier and AutoConnect disabled"
            warn "blueman no longer auto-reconnects"
            note "blueman AutoConnect off — use 'bluetoothctl trust <MAC>' for auto-reconnect"
            ;;
        *)
            skip "blueman left as-is"
            ;;
    esac
}

# ── services ────────────────────────────────────────────────────────────────

stage_services() {
    step "Services"
    local svc
    for svc in NetworkManager bluetooth sddm; do
        if ! systemctl list-unit-files "$svc.service" &>/dev/null; then
            skip "$svc not installed"
            continue
        fi
        if systemctl is-enabled "$svc" &>/dev/null; then
            skip "$svc already enabled"
        elif confirm "Enable $svc?" y; then
            # Non-fatal: this fails in a container, and everything above it is
            # still worth keeping.
            if sudo systemctl enable "$svc"; then
                ok "$svc enabled"
            else
                warn "could not enable $svc"
                note "enable it by hand: sudo systemctl enable $svc"
            fi
        fi
    done
}

# ── restarting the running shell ────────────────────────────────────────────
#
# Only meaningful during an update, and only when a session is up. The command
# mirrors hypr/config/helpers/shell.lua: kill both long-lived modules, refresh
# the pywal colours, start them again — all inside one shell, so that shell's
# own command line is what its own pkill sees rather than the processes it is
# about to spawn.

shell_is_running() {
    pgrep -f 'fabric_shel[l][^ ]*/(daemon|bar)\.py' >/dev/null 2>&1
}

restart_shell() {
    step "Restarting the shell"
    if ! shell_is_running; then
        skip "not running — it starts itself at your next login"
        return 0
    fi
    if ! confirm "Restart the running shell now?

The bar and the overlays disappear for a second while it comes back. Skip this if you are in the middle of something — SUPER + SHIFT + R does the same later." y; then
        skip "left running the old code"
        note "restart the shell with SUPER + SHIFT + R, or log out and back in"
        return 0
    fi
    # setsid, or the new daemon is a child of this script and dies with it.
    setsid bash -c '
        R=$HOME/.config/fabric_shell; PY=$R/.venv/bin/python
        pkill -f "fabric_shel[l][^ ]*/(daemon|bar|notifications)\.py"
        sleep 1
        wal -R >/dev/null 2>&1 && cp "$HOME/.cache/wal/colors-fabric.css" "$R/css/colors-fabric.css"
        $PY $R/daemon.py >/dev/null 2>&1 &
        $PY $R/bar.py >/dev/null 2>&1 &
    ' >/dev/null 2>&1 || true
    sleep 3
    if shell_is_running; then
        ok "restarted"
    else
        warn "the shell did not come back"
        note "restart it by hand with SUPER + SHIFT + R, or log out and back in"
    fi
}

# ── update ──────────────────────────────────────────────────────────────────
#
# What an install does that an update should not: clone, ask the machine
# questions over again, rewrite generated config that is already correct. What
# an update does that an install cannot: pull, and put back the local edits that
# install.sh itself made to tracked files.

update_repo() {
    step "Updating the repository"

    if [[ ! -d "$REPO_ROOT/.git" ]]; then
        warn "$REPO_ROOT is not a git clone — nothing to pull"
        note "this copy was not cloned, so it cannot be pulled; fetch a fresh one"
        return 0
    fi

    local before after dirty stashed=0 count
    before="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

    # install.sh edits tracked files on purpose — env-hyprland, hyprpaper.conf,
    # the pywal CSS — so a dirty tree is the normal case here, not the exception.
    # Stash it across the pull and put it back afterwards.
    dirty="$(git -C "$REPO_ROOT" status --porcelain)"
    if [[ -n "$dirty" ]]; then
        say "local changes:"
        printf '%s\n' "$dirty" | sed 's/^/        /'
        if confirm "This clone has local changes — usually the machine-specific values install.sh wrote:

$dirty

Stash them, pull, and put them back?" y; then
            git -C "$REPO_ROOT" stash push -u \
                -m "archdots update $(date '+%Y-%m-%d %H:%M')" >/dev/null
            stashed=1
            ok "stashed"
        else
            warn "pulling with a dirty tree — git refuses if anything conflicts"
        fi
    fi

    if git -C "$REPO_ROOT" pull --ff-only; then
        ok "pulled"
    else
        warn "pull failed — resolve it by hand and re-run"
        note "git pull failed; the rest of the update ran against the old checkout"
    fi

    git -C "$REPO_ROOT" submodule update --init --recursive && ok "submodules up to date"

    if (( stashed )); then
        if git -C "$REPO_ROOT" stash pop; then
            ok "local changes restored"
        else
            warn "the stash did not apply cleanly — your changes are still in it"
            note "resolve the conflict, then: git -C $REPO_ROOT stash pop"
        fi
    fi

    after="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    if [[ "$before" == "$after" ]]; then
        say "already at $after"
    else
        count="$(git -C "$REPO_ROOT" rev-list --count "$before..$after" 2>/dev/null || echo '?')"
        ok "$before → $after ($count commits)"
        note "updated $before → $after"
    fi
}

update_packages() {
    if (( ! DO_PACKAGES )); then
        step "Packages"
        skip "skipped (--skip-packages)"
        return 0
    fi

    # An update's job here is the packages the repo has *gained* since the last
    # run. --needed makes that a no-op for everything already installed, so it
    # is cheap even when nothing changed. A full -Syu is a separate question,
    # asked below, because upgrading the system is the user's call and not a
    # side effect of updating some dotfiles.
    if ! confirm "Install any packages the repo has added since your last run?

This is 'pacman -S --needed' over the package lists: already-installed packages are untouched, and nothing is upgraded." y; then
        step "Packages"
        skip "left alone"
        return 0
    fi

    step "Package lists"
    pac_install "${PKG_CORE[@]}" "${PKG_FONTS[@]}"
    ok "core and fonts up to date"

    if (( WANT_UTILS )); then
        pac_install "${PKG_UTILS[@]}" && ok "utilities up to date"
    fi

    if (( WANT_AUR )) && command -v paru >/dev/null; then
        step "AUR packages"
        paru -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: paru -S ${PKG_AUR[*]}"
        }
        ok "done"
    elif (( WANT_AUR )); then
        skip "paru not installed — AUR packages left alone"
    fi

    if confirm "Upgrade the whole system as well (pacman -Syu)?" n; then
        step "System upgrade"
        sudo pacman -Syu --noconfirm
        ok "upgraded"
    fi
}

run_update() {
    step "Checking sudo"
    sudo -v || die "sudo authentication failed."
    ok "authenticated"

    update_repo
    update_packages
    stage_stow          # picks up whatever the update added, moved or renamed
    stage_venv upgrade  # requirements.txt may have moved to a newer fabric
    stage_wallpapers    # copies any new wallpapers into ~/Pictures/wallpapers
    restart_shell

    step "Done"
    say "Updated. Anything that only applies at login — a new autorun entry, a"
    say "changed login shell — waits for your next session."
    say ""
    say "Machine-specific config (GPU, monitors, wallpaper paths) was left alone."
    say "Re-run './install.sh install --skip-packages' if the hardware changed."

    if (( ${#SUMMARY[@]} )); then
        printf '\n    %sWorth knowing:%s\n' "$B" "$R"
        printf '      • %s\n' "${SUMMARY[@]}"
    fi
    printf '\n'
}

# ── install ─────────────────────────────────────────────────────────────────

run_install() {
    step "Checking sudo"
    sudo -v || die "sudo authentication failed."
    ok "authenticated"

    stage_packages
    (( DO_PACKAGES )) && install_sddm_theme
    stage_stow
    stage_zsh
    stage_venv
    stage_wallpapers
    stage_machine
    stage_theming
    stage_dconf
    stage_services

    step "Done"
    say "Log out and pick Hyprland at the SDDM login screen. The desktop starts itself."
    say "Press SUPER + / once you are in for the keybind cheatsheet."

    if (( ${#SUMMARY[@]} )); then
        printf '\n    %sWorth knowing:%s\n' "$B" "$R"
        printf '      • %s\n' "${SUMMARY[@]}"
    fi

    cat <<EOF

    ${B}Machine-specific edits${R}
    Some of the files above are tracked, so this machine's values now show up as
    repo changes. That is expected — they are the values this machine needs.
      see them:      git -C $REPO_ROOT status
      discard them:  git -C $REPO_ROOT checkout -- <file>

    Anything else that differs on this machine belongs in
    ~/.config/hypr/config/custom/, which is gitignored and loaded last.
    See DEVELOPMENT.md#per-machine-config.

    ${B}Later${R}
      $REPO_ROOT/install.sh update

EOF
}

# ── which of the two, and with what ─────────────────────────────────────────
#
# Only the dialog build asks. With no mode on the command line and no dialogs,
# it installs — which is what every existing curl one-liner expects.

choose_stages() {
    local sel tag
    on_off() { (( $1 )) && printf 'on' || printf 'off'; }

    sel="$(wt --title "Custom install" --checklist \
        "Which parts should run? Space toggles, Enter confirms." 20 76 7 \
        packages "Install packages"                        "$(on_off $DO_PACKAGES)" \
        utils    "  the utility packages"                  "$(on_off $WANT_UTILS)" \
        aur      "  paru and the AUR packages"             "$(on_off $WANT_AUR)" \
        flatpak  "  the flatpak applications"              "$(on_off $WANT_FLATPAK)" \
        stow     "Link the dotfiles into \$HOME"           "$(on_off $DO_STOW)" \
        venv     "Build the fabric_shell virtualenv"       "$(on_off $DO_VENV)" \
        machine  "Machine config: GPU, monitors, wallpaper" "$(on_off $DO_MACHINE)")" \
        || { say "cancelled"; exit 0; }

    # The tags are the same switches --help documents, so this checklist cannot
    # ask for anything the flags cannot. whiptail returns them quoted, space
    # separated.
    DO_PACKAGES=0; DO_STOW=0; DO_VENV=0; DO_MACHINE=0
    WANT_UTILS=0; WANT_AUR=0; WANT_FLATPAK=0
    for tag in ${sel//\"/}; do
        case "$tag" in
            packages) DO_PACKAGES=1 ;;
            utils)    WANT_UTILS=1 ;;
            aur)      WANT_AUR=1 ;;
            flatpak)  WANT_FLATPAK=1 ;;
            stow)     DO_STOW=1 ;;
            venv)     DO_VENV=1 ;;
            machine)  DO_MACHINE=1 ;;
        esac
    done
}

choose_mode() {
    [[ -z "$MODE" ]] || return 0
    if [[ $UI != whiptail ]]; then
        MODE="install"
        return 0
    fi

    # An existing stow tree means this machine has been installed before, so an
    # update is the likelier answer.
    local default="install"
    [[ -L "$HOME/.config/hypr" || -L "$HOME/.zshrc" ]] && default="update"

    # Straight to whiptail rather than through choose(): cancelling the *main*
    # menu means "I did not want to run this", which is not the same as taking
    # the default.
    MODE="$(wt --title "archdots" --default-item "$default" --menu \
        "Arch + Hyprland desktop.

Everything here can also be driven from the command line — see --help." 20 76 4 \
        install "Install: packages, dotfiles, shell, machine config" \
        update  "Update: pull, re-link, refresh packages and the venv" \
        custom  "Custom install: pick the stages yourself" \
        quit    "Quit")" || MODE="quit"

    case "$MODE" in
        quit|"") say "nothing to do"; exit 0 ;;
        custom)  MODE="install"; choose_stages ;;
    esac
}

# ── main ────────────────────────────────────────────────────────────────────

choose_mode
locate_repo

case "$MODE" in
    update) run_update ;;
    *)      run_install ;;
esac
