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

# The wallpaper this machine is using, as a symlink. hyprpaper.conf and
# hyprlock.conf point at it instead of at a picture, which is what keeps both of
# those files identical on every machine and out of `git status`.
WALLPAPER_POINTER="$HOME/.local/state/archdots/wallpaper"

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
    python-gobject gtk3 gtk-layer-shell python-pip
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

# AUR packages the desktop genuinely needs. Kept apart from PKG_AUR because
# that list is optional and declinable, and these are not: without pywal16 there
# is no palette and every surface falls back to its hardcoded colours.
#
# python-pywal16 is the maintained fork of python-pywal, which is unmaintained
# and was dropped from the official repos into the AUR at 3.3.0. pywal16 both
# conflicts with and provides python-pywal, so paru swaps a pre-existing
# python-pywal out on its own — no manual removal step is needed.
PKG_AUR_CORE=(
    python-pywal16
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
WANT_FLATPAK=1
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

With whiptail installed this runs as dialogs: you pick what to install once, and
the rest is unattended behind a progress bar, with the full output kept in
~/.local/state/archdots/. Use --no-gui to be asked about each step instead, in
plain text, with every command's output on screen.

  -y, --yes           Take the default for every prompt (non-interactive).
                      Implies --no-gui.
      --no-gui        Plain-text prompts instead of whiptail dialogs, and one
                      question per step. (--gui forces the dialogs back on.)
      --repo URL      Clone from URL instead of the default remote.
      --dir PATH      Clone into PATH (default: ~/archdots).
      --no-flatpak    Skip the flatpak applications.
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
        --flatpak)       WANT_FLATPAK=1 ;;   # kept: it used to be opt-in
        --no-flatpak)    WANT_FLATPAK=0 ;;
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

# What --yes meant on the command line, before the menu had its say. A dialog
# run answers its own questions (see choose_mode) but a handful of them are
# still worth stopping for; those are asked through interactive(), which winds
# ASSUME_YES back to this. With a real --yes, nothing asks anything.
CLI_ASSUME_YES=$ASSUME_YES

# ── output ──────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; BLU=$'\033[34m'; R=$'\033[0m'
else
    B=''; DIM=''; RED=''; GRN=''; YEL=''; BLU=''; R=''
fi

# Everything the script says goes to the log as well as the screen, and *only*
# to the log while the progress bar is up — a gauge with pacman scrolling
# through it is unreadable, and the output is worth keeping either way.
LOG_FILE=""
LOG_DIR="$HOME/.local/state/archdots"

log_open() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    LOG_FILE="$LOG_DIR/${1:-install}-$(date +%Y%m%d-%H%M%S).log"
    {
        printf 'archdots %s\n' "${1:-install}"
        printf 'started  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'user     %s\n' "$(id -un)"
        printf 'command  %s\n\n' "$0 ${ARGS_ORIGINAL[*]:-}"
    } > "$LOG_FILE" 2>/dev/null || LOG_FILE=""
    # Nine logs is enough history to compare a bad run against a good one.
    ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +10 | xargs -r rm -f 2>/dev/null || true
}

log() { [[ -n "$LOG_FILE" ]] && printf '%s\n' "$1" >> "$LOG_FILE"; return 0; }

SUMMARY=()
note()    { SUMMARY+=("$1"); log "    note: $1"; }
step()    {
    log ""; log "==> $1"
    if gauge_up; then gauge_step "$1"
    else printf '\n%s==>%s %s%s%s\n' "$BLU" "$R" "$B" "$1" "$R"; fi
}
say()     { log "    $1";   gauge_up || printf '    %s\n' "$1"; }
ok()      { log "    ok: $1";   gauge_up || printf '    %s✓%s %s\n' "$GRN" "$R" "$1"; }
skip()    { log "    skip: $1"; gauge_up || printf '    %s·%s %s\n' "$DIM" "$R" "$1"; }
warn()    { log "    WARN: $1"; gauge_up || printf '    %s!%s %s\n' "$YEL" "$R" "$1" >&2; }
die()     {
    log "    ERROR: $1"
    gauge_close
    printf '\n%serror:%s %s\n' "$RED" "$R" "$1" >&2
    [[ -n "$LOG_FILE" ]] && printf '       the full log is at %s\n' "$LOG_FILE" >&2
    exit 1
}

# ── the progress bar ────────────────────────────────────────────────────────
#
# One whiptail --gauge runs for the whole install, fed percentages and text on a
# pipe. It replaces the wall of pacman output rather than summarising it: the
# output goes to the log, and what stays on screen is which step is running and
# how far in it is.
#
# The gauge is only ever raised when the run is unattended (dialog mode, which
# answers every question from the menu you already saw), so it can never end up
# hiding a prompt. Anything that does need the screen — sudo, a fatal error —
# closes it first.

GAUGE_OPEN=0
PCT_MIN=0        # the span of the bar belonging to the current step,
PCT_MAX=100      # so a step can report its own internal progress inside it
PCT_NOW=0
GAUGE_TITLE=""
GAUGE_DETAIL=""

gauge_up() { (( GAUGE_OPEN )); }

GAUGE_LABEL=""
GAUGE_PID=""

gauge_open() {
    [[ $UI == whiptail ]] || return 0
    have_tty || return 0
    # Unattended runs only. `install.sh install` names a mode on the command
    # line and so never went through the menu, which means it still has
    # questions to ask — and a question behind the bar is a hang as far as
    # anybody watching is concerned.
    (( ASSUME_YES )) || return 0
    GAUGE_LABEL="${1:-$GAUGE_LABEL}"
    # A coprocess would give a job to manage; a process substitution is a plain
    # fd that closes when the script does.
    exec 3> >(whiptail --backtitle "$BACKTITLE" --title "$GAUGE_LABEL" \
        --gauge "${GAUGE_TITLE:-Starting…}" 9 74 "$PCT_NOW" >/dev/tty 2>/dev/null)
    # $! is the whiptail itself, which the askpass helper needs so it can stop
    # the bar while it asks and start it again afterwards.
    GAUGE_PID=$!
    export ARCHDOTS_GAUGE_PID="$GAUGE_PID"

    # While the bar is up, everything this script prints goes to the log and
    # nothing reaches the terminal.
    #
    # run_logged already routes the output of the commands it runs, but a script
    # this size also calls things directly — chsh announces "Changing shell for
    # you.", systemctl prints the symlinks it made, luac reports a syntax error.
    # Newt owns the screen and keeps its own model of what is on it, so anything
    # written behind its back does not merely look untidy: it lands in the middle
    # of the box, and every repaint after that builds on a screen newt no longer
    # describes correctly. The bar is unaffected — it talks to whiptail down
    # fd 3, and whiptail draws on /dev/tty.
    exec 4>&1 5>&2
    exec >>"${LOG_FILE:-/dev/null}" 2>&1

    GAUGE_OPEN=1
}

# Ask something for real, even in the middle of an unattended run.
#
# Most of an install is foregone once you have chosen it — nobody wants to
# confirm oh-my-zsh — but a few questions are nobody's to answer for you: which
# monitor is the primary one, whether to move dotfiles you already had, whether
# to interrupt the shell you are using right now. Those go through here: the bar
# steps aside, the question is asked properly, and the bar comes back where it
# was.
PROMPT_SAVED_YES=0
PROMPT_GAUGE_WAS_UP=0

prompt_begin() {
    PROMPT_GAUGE_WAS_UP=0
    gauge_up && { PROMPT_GAUGE_WAS_UP=1; gauge_close; }
    PROMPT_SAVED_YES=$ASSUME_YES
    ASSUME_YES=$CLI_ASSUME_YES
}

prompt_end() {
    ASSUME_YES=$PROMPT_SAVED_YES
    (( PROMPT_GAUGE_WAS_UP )) && gauge_open
    PROMPT_GAUGE_WAS_UP=0
    return 0
}

# For prompts whose answer is an exit status. Prompts that answer on *stdout*
# run inside $( ), which is a subshell — pausing the gauge in there would pause
# a copy and leave the real one drawing over the dialog — so those call
# prompt_begin/prompt_end around the substitution instead.
interactive() {
    local rc=0
    prompt_begin
    "$@" || rc=$?
    prompt_end
    return "$rc"
}

gauge_close() {
    gauge_up || return 0
    GAUGE_OPEN=0
    GAUGE_PID=""
    export ARCHDOTS_GAUGE_PID=""
    # Give the script its terminal back before the bar goes away, so whatever
    # prints next — the summary, an error, a prompt — has somewhere to appear.
    exec 1>&4 2>&5
    exec 4>&- 5>&-
    exec 3>&-
    # Let whiptail finish drawing and restore the terminal before anything else
    # writes to it.
    sleep 0.3
}

# The gauge protocol: XXX, percentage, replacement text, XXX.
gauge_paint() {
    gauge_up || return 0
    printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2" >&3 2>/dev/null || true
}

# Give the current step a slice of the bar. Everything it reports moves inside
# that slice, so the bar only ever goes forwards.
phase() {
    PCT_MIN="$1"; PCT_MAX="$2"; PCT_NOW="$1"
    GAUGE_TITLE="${3:-$GAUGE_TITLE}"; GAUGE_DETAIL=""
    gauge_paint "$PCT_NOW" "$(gauge_body)"
}

gauge_step() {
    GAUGE_TITLE="$1"; GAUGE_DETAIL=""
    gauge_paint "$PCT_NOW" "$(gauge_body)"
}

gauge_detail() {
    GAUGE_DETAIL="$1"
    gauge_paint "$PCT_NOW" "$(gauge_body)"
}

# One line, and one line only: whiptail's gauge renders the *first* line of an
# update and silently drops the rest (tested — a three-line update shows line
# one), and it does no escape processing either. So the step and its detail are
# composed into a single line and trimmed to the box.
gauge_body() {
    local text="$GAUGE_TITLE"
    [[ -n "$GAUGE_DETAIL" ]] && text="$GAUGE_TITLE — $GAUGE_DETAIL"
    printf '%s' "${text:0:68}"
}

# Move to `done/total` through the current step's slice.
gauge_fraction() {
    local done="$1" total="$2" span
    (( total > 0 )) || return 0
    span=$(( PCT_MAX - PCT_MIN ))
    PCT_NOW=$(( PCT_MIN + (span * done) / total ))
    (( PCT_NOW > PCT_MAX )) && PCT_NOW=$PCT_MAX
}

# ── running things ──────────────────────────────────────────────────────────

# Run a command with its output in the log instead of on the screen, and the
# gauge following along. Returns the command's own exit status, so every caller
# keeps deciding for itself whether a failure is fatal.
run_logged() {
    local label="$1"; shift
    log ""
    log "--- $label"
    log "+ $*"
    if ! gauge_up; then
        # Plain mode shows everything, as it always did, and logs it too.
        set +e
        "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
        local plain_rc=${PIPESTATUS[0]}
        set -e
        return "$plain_rc"
    fi
    set +e
    "$@" 2>&1 | log_filter "$label"
    local rc=${PIPESTATUS[0]}
    set -e
    # If the helper had to ask for a password, a dialog has been drawn over the
    # bar and the bar was stopped while it was up. Redraw it from scratch rather
    # than leaving the leftovers on screen.
    if [[ -n "$ASKPASS_FLAG" && -f "$ASKPASS_FLAG" ]]; then
        rm -f "$ASKPASS_FLAG"
        log "    (sudo asked for a password)"
        gauge_up && { gauge_close; gauge_open; }
    fi
    return "$rc"
}

# Reads a command's output line by line: everything to the log, and the
# interesting lines to the gauge.
#
# It runs in a pipeline, so it is a subshell — it can read PCT_* and write to
# the gauge's fd, but nothing it assigns comes back. That is why the percentage
# it computes is sent straight to the bar rather than stored.
log_filter() {
    local label="$1" line text pct done total
    while IFS= read -r line; do
        log "$line"
        # Strip the carriage returns and colour escapes that pacman and pip use
        # to animate a terminal; on one line of a gauge they are just noise.
        line="${line//$'\r'/}"
        line="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')"
        # pacman's own counter: "( 12/692) installing glibc-common".
        if [[ "$line" =~ ^\(\ *([0-9]+)/([0-9]+)\)\ *(.*)$ ]]; then
            done="${BASH_REMATCH[1]}"; total="${BASH_REMATCH[2]}"
            pct=$(( PCT_MIN + ((PCT_MAX - PCT_MIN) * done) / total ))
            (( pct > PCT_MAX )) && pct=$PCT_MAX
            # "installing"/"upgrading" is already obvious from the step, and
            # the package name is the part worth the room.
            text="$label — $done of $total — ${BASH_REMATCH[3]#* }"
            printf 'XXX\n%s\n%s\nXXX\n' "$pct" "${text:0:68}" >&3 2>/dev/null || true
            continue
        fi
        # Everything else: keep the bar where it is and show the line, which is
        # what makes a long pip build or an AUR compile look alive rather than
        # hung. Blank and decorative lines are skipped so the text stays put.
        [[ -n "${line// /}" ]] || continue
        [[ "$line" =~ ^[[:punct:][:space:]]+$ ]] && continue
        text="$label — $line"
        printf 'XXX\n%s\n%s\nXXX\n' "$PCT_NOW" "${text:0:68}" >&3 2>/dev/null || true
    done
}

# ── sudo ────────────────────────────────────────────────────────────────────
#
# A password prompt is the one thing that must never appear *behind* the
# progress bar. It did once: makepkg ran `sudo pacman -U` after a long build,
# sudo drew "[sudo] password for you:" straight over the gauge, and the
# keystrokes went to whiptail — which owns the terminal — so sudo read nothing
# and answered "Sorry, try again".
#
# Two things stop that. The timestamp is kept warm in the background, so the
# question usually never comes up; and when it does, sudo asks through a helper
# that puts the gauge to sleep, shows a proper password box, and wakes it again.
# Nothing gets to prompt on the raw terminal while the bar is up.

SUDO=(sudo)          # becomes (sudo -A) once the helper exists
ASKPASS_DIR=""
ASKPASS_FLAG=""

# Which terminal to draw on, by name rather than by /dev/tty.
#
# /dev/tty is by definition the *controlling* terminal, and anything that has
# been detached from one — a daemon, a setsid child, a build system being
# thorough — cannot open it at all: "No such device or address", and there is
# nowhere to put the box. The device itself is still perfectly openable by path,
# so the path is what gets passed down.
current_tty() {
    local t fd
    t="$(tty 2>/dev/null)" && [[ "$t" == /dev/* ]] && { printf '%s' "$t"; return 0; }
    # Piped from curl, stdin is not the terminal — but stdout or stderr still is.
    for fd in 1 2; do
        t="$(readlink -f "/proc/$$/fd/$fd" 2>/dev/null)" || continue
        [[ "$t" == /dev/pts/* || "$t" == /dev/tty[0-9]* ]] && { printf '%s' "$t"; return 0; }
    done
    t="$(ps -o tty= -p $$ 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$t" && "$t" != "?" ]] && { printf '/dev/%s' "$t"; return 0; }
    return 1
}

sudo_askpass_setup() {
    [[ $UI == whiptail ]] || return 0
    have_tty || return 0
    local term
    term="$(current_tty)" || return 0
    ASKPASS_DIR="$(mktemp -d)" || return 0
    chmod 700 "$ASKPASS_DIR"
    ASKPASS_FLAG="$ASKPASS_DIR/asked"

    cat > "$ASKPASS_DIR/askpass" <<'HELPER'
#!/usr/bin/env bash
# Written by archdots install.sh, and run by sudo instead of prompting on the
# terminal.
#
# $ARCHDOTS_TTY, not /dev/tty: whoever called sudo may have no controlling
# terminal, and /dev/tty is exactly that terminal — it cannot be opened from a
# detached process. If even the named device is unusable, exit rather than hand
# sudo an empty password: three silent retries and a "Sorry, try again" tell
# nobody anything.
T="${ARCHDOTS_TTY:-/dev/tty}"
if [[ ! -r "$T" || ! -w "$T" ]]; then
    printf 'archdots: no terminal to ask for a password on (%s)\n' "$T" >&2
    exit 1
fi
# SIGSTOP rather than a kill: the gauge has to survive to be resumed, and a
# stopped process cannot repaint over the box while it is up.
[[ -n "${ARCHDOTS_GAUGE_PID:-}" ]] && kill -STOP "$ARCHDOTS_GAUGE_PID" 2>/dev/null
[[ -n "${ARCHDOTS_ASKPASS_FLAG:-}" ]] && : > "$ARCHDOTS_ASKPASS_FLAG"
pw="$(whiptail --backtitle "${ARCHDOTS_BACKTITLE:-archdots}" \
    --title "Administrator password" \
    --passwordbox "${1:-Password:}

Installing packages needs root. Your password is not
stored, and nothing is echoed as you type.

Enter confirms · Esc cancels" 13 62 2>&1 1>"$T" <"$T")"
[[ -n "${ARCHDOTS_GAUGE_PID:-}" ]] && kill -CONT "$ARCHDOTS_GAUGE_PID" 2>/dev/null
printf '%s\n' "$pw"
HELPER
    chmod 700 "$ASKPASS_DIR/askpass"

    # A stand-in for sudo, first on PATH, for everything this script starts.
    #
    # makepkg and paru call `sudo` themselves and there is no -A to add to
    # those calls — and makepkg's is `sudo -k`, which discards the cached
    # credentials so that every single pacman call needs a password typed
    # again. The shim drops the -k, so the session we already authenticated
    # stays usable, and adds -A, so a password that genuinely is needed is
    # asked for in a dialog rather than on a terminal the progress bar owns.
    #
    # Only leading options are rewritten: everything from the first non-option
    # onwards is the command being run and is passed through untouched.
    mkdir -p "$ASKPASS_DIR/bin"
    cat > "$ASKPASS_DIR/bin/sudo" <<HELPER
#!/usr/bin/env bash
# Written by archdots install.sh. See sudo_askpass_setup.
real=$(command -v sudo)
opts=(); saw_a=0
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -k|--reset-timestamp) shift ;;
        -A|--askpass)         saw_a=1; opts+=("\$1"); shift ;;
        -*)                   opts+=("\$1"); shift ;;
        *)                    break ;;
    esac
done
(( saw_a )) || opts+=(-A)
exec "\$real" \${opts[@]+"\${opts[@]}"} "\$@"
HELPER
    chmod 700 "$ASKPASS_DIR/bin/sudo"
    export PATH="$ASKPASS_DIR/bin:$PATH"

    export SUDO_ASKPASS="$ASKPASS_DIR/askpass"
    export ARCHDOTS_ASKPASS_FLAG="$ASKPASS_FLAG"
    export ARCHDOTS_BACKTITLE="$BACKTITLE"
    export ARCHDOTS_TTY="$term"
    # The shim adds -A itself, and our own calls go through it too.
    SUDO=(sudo)
}

# Ask once, up front, before the bar goes up.
sudo_authenticate() {
    step "Checking sudo"
    if sudo -n true 2>/dev/null; then
        ok "already authenticated"
        sudo_keepalive
        return 0
    fi
    local try
    for try in 1 2 3; do
        if "${SUDO[@]}" -v 2>/dev/null; then
            ok "authenticated"
            sudo_keepalive
            return 0
        fi
        (( try < 3 )) && warn "that password did not work — try again"
    done
    die "sudo authentication failed."
}

# sudo's timestamp expires while a long build runs. Refresh it for as long as
# the script is alive: a failure here is not fatal, because the askpass helper
# is still there to ask properly if it comes to that.
SUDO_KEEPALIVE_PID=""
sudo_keepalive() {
    [[ -z "$SUDO_KEEPALIVE_PID" ]] || return 0
    ( while true; do sudo -n true 2>/dev/null; sleep 45; done ) &
    SUDO_KEEPALIVE_PID=$!
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    gauge_close
    [[ -n "$ASKPASS_DIR" ]] && rm -rf "$ASKPASS_DIR"
    return 0
}
trap cleanup EXIT

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

# Newt has a help line for exactly this and whiptail does not expose it, so the
# key hints go inside the box, on the last line, where somebody who has never
# used a dialog like this is already looking.
KEYS_YESNO="Enter confirms · Tab switches buttons · Esc cancels"
KEYS_INPUT="Type to edit · Enter confirms · Esc keeps the suggestion"
KEYS_MENU="↑ ↓ choose · Enter confirms · Esc cancels"
KEYS_LIST="↑ ↓ move · Space ticks · Tab to the buttons · Enter confirms"
KEYS_RADIO="↑ ↓ move · Space picks · Enter confirms"

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
        text="$(wt_clip "$prompt")

$KEYS_YESNO"
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
        local text="$prompt

$KEYS_INPUT"
        reply="$(wt --title "archdots" --inputbox "$text" \
            "$(wt_height "$text" 8)" "$(wt_width "$text")" "$default")" || reply=""
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
        local reply rows height text
        rows=$(( $# / 2 ))
        text="$prompt

$KEYS_MENU"
        height=$(( $(wt_lines "$text" 76) + rows + 8 ))
        (( height > 20 )) && height=20
        reply="$(wt --title "archdots" --default-item "$default" \
            --menu "$text" "$height" 76 "$rows" "$@")" || reply=""
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

# Pick exactly one of a list, with the current answer already selected. Same
# arguments as choose(), but drawn as radio buttons — for a question like "which
# monitor" the point is to *see* everything that was detected, including when
# there is only one of them and nothing to choose.
choose_radio() {
    local prompt="$1" default="$2"; shift 2
    if (( ASSUME_YES )) || ! have_tty || [[ $UI != whiptail ]]; then
        printf '%s' "$default"
        return
    fi
    local items=() tag desc rows=0 text height reply
    while (( $# )); do
        tag="$1"; desc="$2"; shift 2
        items+=("$tag" "$desc" "$([[ "$tag" == "$default" ]] && printf on || printf off)")
        rows=$(( rows + 1 ))
    done
    text="$prompt

$KEYS_RADIO"
    height=$(( $(wt_lines "$text" 76) + rows + 8 ))
    (( height > 20 )) && height=20
    reply="$(wt --title "archdots" --radiolist "$text" "$height" 76 "$rows" "${items[@]}")" \
        || reply=""
    # whiptail quotes what it returns, and returns nothing if you untick
    # everything and press Enter.
    reply="${reply//\"/}"
    printf '%s' "${reply:-$default}"
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

$(wt_clip "$body" 12)

$KEYS_YESNO"
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
            "${SUDO[@]}" pacman -Sy --needed --noconfirm git
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
    local label="$1"; shift
    (( $# )) || return 0
    run_logged "$label" "${SUDO[@]}" pacman -S --needed --noconfirm "$@"
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
    run_logged "Fetching paru" git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"

    # Install the build dependencies here rather than letting makepkg do it.
    #
    # makepkg escalates with `sudo -k` (see run_pacman in /usr/bin/makepkg), and
    # -k throws away the cached credentials on purpose: every pacman call it
    # makes demands a password, however recently you typed one. That is fine
    # when you are watching a terminal and fatal when a progress bar owns the
    # screen — the ask goes somewhere invisible, sudo fails, and makepkg reports
    # "Could not resolve all dependencies", which is a sentence about
    # dependencies describing a problem about passwords.
    #
    # So makepkg is given nothing to escalate for. The dependencies go in first
    # through our own sudo, and the built package is installed by us afterwards.
    # -s stays as a safety net for any dependency this misses.
    local deps=()
    mapfile -t deps < <(pkgbuild_deps "$tmp/paru")
    if (( ${#deps[@]} )); then
        say "paru needs: ${deps[*]}"
        pac_install "paru's build dependencies" "${deps[@]}" \
            || warn "could not pre-install every dependency — makepkg will try"
    fi

    run_logged "Building paru from source" \
        bash -c "cd '$tmp/paru' && makepkg -s --noconfirm" \
        || { rm -rf "$tmp"; die "paru failed to build — see the log."; }

    local built=()
    mapfile -t built < <(built_packages "$tmp/paru")
    (( ${#built[@]} )) || { rm -rf "$tmp"; die "paru built no package — see the log."; }
    run_logged "Installing paru" "${SUDO[@]}" pacman -U --noconfirm "${built[@]}" \
        || { rm -rf "$tmp"; die "could not install the paru package — see the log."; }

    rm -rf "$tmp"
    paru --version &>/dev/null || die "paru still will not run after a source build."
    ok "built from source and installed"
}

# The packages a finished build actually produced, minus the debug ones.
#
# Arch builds with OPTIONS=(debug) by default, so `makepkg` leaves *two* files
# behind: paru-2.1.0-2-x86_64.pkg.tar.zst and paru-debug-2.1.0-2-…, the second
# being nothing but detached debug symbols. Installing that one succeeds, looks
# entirely convincing in pacman's output — "reinstalling paru-debug" — and
# leaves no paru on the system. Picking the first file a glob happens to return
# is therefore a coin flip, and it came up wrong.
#
# makepkg --packagelist is the authority on what it built, so ask it, and keep
# the glob only for the case where that fails.
built_packages() {
    local dir="$1" list=()
    mapfile -t list < <(
        cd "$dir" 2>/dev/null && makepkg --packagelist 2>/dev/null | grep -v -- '-debug-'
    )
    if (( ! ${#list[@]} )); then
        mapfile -t list < <(
            find "$dir" -maxdepth 1 -name '*.pkg.tar*' ! -name '*-debug-*' | sort
        )
    fi
    local pkg
    for pkg in ${list[@]+"${list[@]}"}; do
        [[ -f "$pkg" ]] && printf '%s\n' "$pkg"
    done
}

# The depends and makedepends of a PKGBUILD, with version constraints trimmed:
# pacman wants `rust`, not `rust>=1.70`.
pkgbuild_deps() {
    local dir="$1" dep
    ( cd "$dir" && bash -c 'source ./PKGBUILD 2>/dev/null
        printf "%s\n" ${depends[@]+"${depends[@]}"} ${makedepends[@]+"${makedepends[@]}"}' ) 2>/dev/null \
    | while read -r dep; do
        dep="${dep%%[<>=]*}"
        # Soname dependencies (libalpm.so=15-64) are not package names. pacman
        # would abort the whole transaction on one unknown target, taking the
        # real dependencies down with it, and whatever provides the soname is
        # installed already if the PKGBUILD builds at all.
        [[ "$dep" == *.so ]] && continue
        [[ -n "$dep" ]] && printf '%s\n' "$dep"
    done | sort -u
}

stage_packages() {
    if (( ! DO_PACKAGES )); then
        step "Packages"
        skip "skipped (--skip-packages)"
        return 0
    fi

    phase 4 6 "Checking for conflicting notification daemons"
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
        # Asked even in a dialog run: this uninstalls something the user chose.
        if interactive confirm "Installed: ${installed_conflicts[*]}

The desktop shell *is* the notification daemon — it owns org.freedesktop.Notifications. Each of these grabs that bus name at login, and the shell's notifications then silently never appear.

Remove them?" y; then
            run_logged "Removing ${installed_conflicts[*]}" \
                "${SUDO[@]}" pacman -Rns --noconfirm "${installed_conflicts[@]}"
            ok "removed"
            note "removed conflicting notification daemon(s): ${installed_conflicts[*]}"
        else
            warn "left installed — expect no notifications until they are gone"
            note "${installed_conflicts[*]} still installed; notifications will not work"
        fi
    else
        skip "none installed"
    fi

    phase 6 42 "Core packages and fonts"
    step "Core packages and fonts"
    say "${#PKG_CORE[@]} core + ${#PKG_FONTS[@]} font packages"
    run_logged "Core packages and fonts" \
        "${SUDO[@]}" pacman -Syu --needed --noconfirm "${PKG_CORE[@]}" "${PKG_FONTS[@]}" \
        || die "pacman could not install the core packages."
    ok "installed"

    if (( WANT_UTILS )) && confirm "Install the utility packages (${#PKG_UTILS[@]})?

${PKG_UTILS[*]}" y; then
        phase 42 46 "Utilities"
        step "Utilities"
        pac_install "Utilities" "${PKG_UTILS[@]}"
        ok "installed"
    else
        skip "utilities"
    fi

    # Not optional, and not part of the AUR question below. The palette is core
    # to the desktop, and its only source is an AUR package now, so paru has to
    # be built even for someone who declines the optional AUR list.
    phase 46 47 "paru"
    step "paru"
    ensure_paru

    phase 47 48 "Theming engine"
    step "Theming engine"
    run_logged "Theming engine" paru -S --needed --noconfirm "${PKG_AUR_CORE[@]}" || {
        warn "python-pywal16 could not be built — the desktop starts unthemed"
        note "retry: paru -S ${PKG_AUR_CORE[*]}"
    }
    ok "done"

    if (( WANT_AUR )) && confirm "Install the optional AUR packages (${#PKG_AUR[@]})?

${PKG_AUR[*]}

These are built from source, which takes a few minutes." y; then
        phase 48 64 "AUR packages"
        step "AUR packages"
        # One failed build should not lose the rest of the install.
        run_logged "AUR packages" paru -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: paru -S ${PKG_AUR[*]}"
        }
        ok "done"
    else
        skip "AUR"
    fi

    if (( WANT_FLATPAK )) && confirm "Install the flatpak applications (${#PKG_FLATPAK[@]})?

${PKG_FLATPAK[*]}" y; then
        phase 64 72 "Flatpak applications"
        step "Flatpaks"
        command -v flatpak >/dev/null || pac_install "Installing flatpak" flatpak
        run_logged "Adding the flathub remote" \
            flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
        run_logged "Flatpak applications" \
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
    phase 72 80 "SDDM login theme"
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
        run_logged "Fetching the SDDM theme" \
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
        mapfile -t deps < <(pkgbuild_deps "$tmp/theme")
        if (( ${#deps[@]} )); then
            say "theme dependencies: ${deps[*]}"
            run_logged "Theme dependencies" paru -S --needed --noconfirm "${deps[@]}" || {
                rm -rf "$tmp"
                warn "could not install the theme's dependencies"
                note "SDDM theme skipped; retry: paru -S sddm-silent-theme"
                return 0
            }
        fi

        # Built, then installed by us — never `makepkg -si`. See ensure_paru for
        # why makepkg is not allowed to reach for sudo.
        run_logged "Building the SDDM theme" \
            bash -c "cd '$tmp/theme' && makepkg -s --noconfirm" || {
            rm -rf "$tmp"
            warn "theme build failed — the desktop still works, the login screen is plain"
            note "SDDM theme failed to build; retry: paru -S sddm-silent-theme"
            return 0
        }

        local built=()
        mapfile -t built < <(built_packages "$tmp/theme")
        if (( ! ${#built[@]} )) || ! run_logged "Installing the SDDM theme" \
            "${SUDO[@]}" pacman -U --noconfirm "${built[@]}"; then
            rm -rf "$tmp"
            warn "could not install the built theme package"
            note "SDDM theme not installed; retry: paru -S sddm-silent-theme"
            return 0
        fi
        rm -rf "$tmp"
        ok "installed"
    fi

    # ── the version lock ────────────────────────────────────────────────────
    # A theme upgrade would replace default.conf and can change the config
    # schema out from under the edited copy, so hold it where it is.
    # Not a question. Installing this theme and letting pacman upgrade it out
    # from under the config written against $SDDM_THEME_VERSION are not two
    # sensible halves of a choice — the pin is part of installing it.
    if grep -qE '^IgnorePkg.*\bsddm-silent-theme\b' /etc/pacman.conf; then
        skip "already pinned in /etc/pacman.conf"
    else
        say "pinning sddm-silent-theme so an upgrade cannot replace its config"
        if grep -qE '^IgnorePkg' /etc/pacman.conf; then
            "${SUDO[@]}" sed -i 's/^\(IgnorePkg.*\)$/\1 sddm-silent-theme/' /etc/pacman.conf
        else
            # There is a commented template under [options]; add a live one.
            "${SUDO[@]}" sed -i '0,/^\[options\]/s//[options]\nIgnorePkg = sddm-silent-theme/' \
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
    elif "${SUDO[@]}" cmp -s "$custom_conf" "$theme_dir/configs/default.conf"; then
        skip "default.conf already matches the repo copy"
    else
        # The theme ships its own; keep it so the change is reversible.
        [[ -f "$theme_dir/configs/default.conf.orig" ]] \
            || "${SUDO[@]}" cp "$theme_dir/configs/default.conf" "$theme_dir/configs/default.conf.orig"
        "${SUDO[@]}" install -Dm644 "$custom_conf" "$theme_dir/configs/default.conf"
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

    if [[ -f "$sddm_conf" ]] && [[ "$("${SUDO[@]}" cat "$sddm_conf")" == "$sddm_body" ]]; then
        skip "$sddm_conf already correct"
    elif review_confirm "$sddm_conf" "$sddm_body" "Write it? (needs root)"; then
        "${SUDO[@]}" mkdir -p /etc/sddm.conf.d
        printf '%s\n' "$sddm_body" | "${SUDO[@]}" tee "$sddm_conf" >/dev/null
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

    phase 80 84 "Linking the dotfiles into your home folder"
    step "Linking the dotfiles into \$HOME"
    command -v stow >/dev/null || die "stow is not installed (--skip-packages was used?)"

    # stow refuses to overwrite a real file. Find those first so the failure is
    # a question rather than a wall of errors.
    # stow aborts the entire run on any conflict, and reports them on stderr as
    # a "WARNING! stowing . would cause conflicts:" block. Only one shape is
    # fixable here — an ordinary file sitting where a link should go:
    #   * cannot stow <source> over existing target <path> since neither a
    #     link nor a directory and --adopt not specified
    # A second shape is just as fixable, and nwg-look is what produces it:
    #   * existing target is not owned by stow: <path>
    # Pressing Apply in nwg-look rewrites the GTK settings and replaces
    # .config/gtk-4.0/gtk.css with an absolute symlink into ~/.themes. Those are
    # its files rather than stow's, so stow refuses to touch them — and being
    # links rather than plain files, the pattern above does not catch them. They
    # are safe to move aside for the same reason the others are: the backup keeps
    # them, and nwg-look would only recreate them next time it runs.
    #
    # Anything else (an entry in the repo root that should not be stowed, say)
    # needs a human, so collect the unrecognised lines rather than proceeding
    # into a hard failure.
    local simulate line rel src backup
    local conflicts=() unhandled=()
    simulate="$(stow --simulate --verbose=1 --target="$HOME" . 2>&1 || true)"
    while IFS= read -r line; do
        [[ "$line" == *"  * "* ]] || continue
        if [[ "$line" =~ cannot\ stow\ .*\ over\ existing\ target\ (.+)\ since ]]; then
            conflicts+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ existing\ target\ is\ not\ owned\ by\ stow:\ (.+)$ ]]; then
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
        # Asked even in a dialog run: these are the user's own files.
        if interactive confirm "${#conflicts[@]} existing file(s) sit where the dotfiles need to go:

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

    run_logged "Linking the dotfiles" stow --restow --target="$HOME" . \
        || die "stow failed — see the log."
    ok "stowed into $HOME"
}

# ── zsh ─────────────────────────────────────────────────────────────────────

stage_zsh() {
    phase 84 87 "zsh and oh-my-zsh"
    step "zsh"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        skip "oh-my-zsh already installed"
    elif ! command -v curl >/dev/null; then
        warn "curl not available — skipping oh-my-zsh"
        note "oh-my-zsh not installed; .zshrc sources it and will error on login"
    elif confirm "Install oh-my-zsh? (.zshrc expects it)" y; then
        # --keep-zshrc is essential: without it the installer replaces the .zshrc
        # symlink stow just created with its own template.
        run_logged "Installing oh-my-zsh" \
            env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
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
        if run_logged "Setting zsh as the login shell" \
            "${SUDO[@]}" chsh -s /usr/bin/zsh "$(id -un)"; then
            ok "login shell set to zsh (takes effect next login)"
        else
            warn "could not change the login shell"
            note "run it yourself: chsh -s /usr/bin/zsh"
        fi
    fi
}

# ── the shell's virtualenv ──────────────────────────────────────────────────

stage_venv() {
    phase 87 96 "Building the desktop shell"
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

    [[ -d "$venv" ]] || run_logged "Creating the virtualenv" python -m venv "$venv"
    say "installing fabric (this compiles pycairo and PyGObject — slow)"
    # The absolute path matters. A bare `-r requirements.txt` resolves against
    # the working directory, which here is the repo root, where no such file
    # exists.
    "$venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
    local pip_args=(install -r "$reqs")
    # On an update, requirements.txt may have moved to a newer fabric.
    [[ "$mode" == "upgrade" ]] && pip_args=(install --upgrade -r "$reqs")
    if run_logged "Building fabric (this takes a while)" "$venv/bin/pip" "${pip_args[@]}"; then
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
    if [[ -z "$WALLPAPER" ]]; then
        warn "no wallpaper found — the desktop starts on its fallback palette"
        return 0
    fi

    # ── the pointer ─────────────────────────────────────────────────────────
    # hyprpaper.conf and hyprlock.conf both name $WALLPAPER_POINTER rather than
    # a picture, so neither tracked file has to be edited per machine — or per
    # wallpaper. This symlink is the machine's actual choice, and the picker
    # (SUPER + W) re-points it whenever you change wallpaper.
    #
    # An existing pointer is never repointed: on an update it is the choice made
    # since the install, and quietly resetting it to whatever sorts first would
    # undo it. Only a missing or dangling one is (re)made.
    mkdir -p "$(dirname "$WALLPAPER_POINTER")"
    if [[ -e "$WALLPAPER_POINTER" ]]; then
        WALLPAPER="$(readlink -f "$WALLPAPER_POINTER")"
        skip "wallpaper already set: $(basename "$WALLPAPER")"
    else
        # -e is false for a dangling symlink, so this covers "the file it named
        # is gone" as well as "there is no pointer".
        ln -sfn "$WALLPAPER" "$WALLPAPER_POINTER"
        ok "$WALLPAPER_POINTER → $(basename "$WALLPAPER")"
    fi
}

# ── machine-specific config ─────────────────────────────────────────────────
#
# Everything below differs per machine, and none of it is written into a tracked
# file. Each program is given its own escape hatch instead:
#
#   Hyprland   config/custom/*.lua, loaded after the defaults (gitignored)
#   uwsm       env-hyprland.d/, sourced after env-hyprland  (gitignored)
#   hyprpaper  ~/.local/state/archdots/wallpaper, a symlink the tracked
#   hyprlock   config points at, so neither config names a picture
#
# The repo therefore stays clean after an install, and nothing here can push one
# machine's hardware onto another.

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

    # uwsm sources every file in env-hyprland.d/ after env-hyprland itself
    # (`source_dir` in /usr/lib/uwsm/prepare-env.sh), which is what makes this
    # separable at all: the tracked file keeps no value, and the pin lives in a
    # gitignored drop-in beside it. A missing directory is not an error there,
    # so a machine that needs no pin simply has no drop-in.
    local env_dir="$HOME/.config/uwsm/env-hyprland.d"
    local env_file="$env_dir/10-gpu.sh" env_body drm_list=""

    if (( ${#drm_ordered[@]} <= 1 )); then
        # One GPU (or none, as in a container): nothing to choose between, and a
        # pin can only be wrong — it names a card that may be absent after a
        # reboot. Any drop-in from an earlier run on different hardware has to
        # go, or it outlives the machine it described.
        if [[ -f "$env_file" ]]; then
            if interactive confirm "This machine has ${#drm_ordered[@]} GPU, but $env_file pins one from an earlier run.

With a single GPU there is nothing to choose between, and a stale pin can name a card that no longer exists. Remove it?" y; then
                rm -f "$env_file"
                ok "removed the stale GPU pin"
            else
                warn "left in place — check it names a card this machine has"
            fi
        else
            skip "no GPU pin needed (${#drm_ordered[@]} DRM device(s))"
        fi
    else
        drm_list="$(IFS=:; printf '%s' "${drm_ordered[*]}")"
        env_body="# Which GPU Hyprland renders on, in order of preference.
#
# Written by install.sh for this machine, and sourced by uwsm after
# env-hyprland. Gitignored: these paths are not portable, and card numbering can
# change between boots. If the session ever comes up on the wrong GPU, re-run
# install.sh or name a stable path from /dev/dri/by-path/ instead.
export AQ_DRM_DEVICES=\"$drm_list\""

        if [[ -f "$env_file" ]] && [[ "$(cat "$env_file")" == "$env_body" ]]; then
            skip "GPU pin already matches this machine"
        elif interactive review_confirm "$env_file" "$env_body"; then
            mkdir -p "$env_dir"
            printf '%s\n' "$env_body" > "$env_file"
            ok "AQ_DRM_DEVICES=$drm_list"
        else
            skip "GPU pin"
            warn "Hyprland may render on the discrete card"
            note "no GPU pin written; write $env_file by hand if the session picks the wrong card"
        fi
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
    # Worth stopping for even in an unattended run: only you know which screen
    # you actually look at.
    prompt_begin
    if [[ $UI == whiptail ]]; then
        # Every detected output is listed, with the suggestion already ticked —
        # including when there is only one, because seeing that the installer
        # found your screen (and what it decided to call it) is worth a box on
        # its own. Retyping a connector name from memory is not.
        local radio_items=() label
        for m in "${monitors[@]}"; do
            case "$m" in
                eDP-*|LVDS-*) label="built-in display" ;;
                *)            label="external display" ;;
            esac
            radio_items+=("$m" "$label")
        done
        primary="$(choose_radio "Which monitor is the primary one?

Workspaces and the lock screen favour it. ${#monitors[@]} detected." \
            "$primary" "${radio_items[@]}")"
    else
        primary="$(ask "Primary monitor?" "$primary")"
    fi
    prompt_end

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
    elif interactive review_confirm "$mon_file" "$mon_body"; then
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

}

# ── first pywal16 run ───────────────────────────────────────────────────────
#
# Without this the shell starts on its hardcoded fallback palette and nothing is
# themed from the wallpaper.
#
# --cols16 dual is what makes colors 8-15 real colours instead of copies of 0-7,
# which the templates and every sheet downstream rely on. It has to match the
# flag the wallpaper picker uses (fabric_shell/wallpapers.py) — a run without it
# would quietly rewrite the palette with a duplicated bright half.
#
# Note that on a near-monochrome wallpaper the distinct bright half is a much
# louder look than classic pywal's; that is the intent, not a bug. Drop the flag
# in both places to go back.

WAL_ARGS=(--cols16 dual)

stage_theming() {
    step "Theming"
    if [[ -z "$WALLPAPER" ]]; then
        skip "no wallpaper to theme from"
    elif ! command -v wal >/dev/null; then
        warn "python-pywal16 not installed — skipping"
        note "run once pywal16 is installed: wal -i $WALLPAPER ${WAL_ARGS[*]}"
    elif ! wal -i "$WALLPAPER" "${WAL_ARGS[@]}" -n -q; then
        warn "pywal16 failed — the shell will start on its fallback palette"
        note "run by hand: wal -i $WALLPAPER ${WAL_ARGS[*]}"
    else
        ok "palette generated from $(basename "$WALLPAPER")"

        # pywal16 renders into ~/.cache/wal/; every consumer reads its own copy
        # instead, and this is where those copies are made. All of them are
        # gitignored, so none of this shows up in `git status` afterwards — the
        # wallpaper picker rewrites exactly the same set on SUPER + W.
        #
        # Two formats, because GTK CSS has no var(): the shell compiles SCSS and
        # uses var(--colorN), while GTK needs @define-color, so colors-gtk.css is
        # a second template rather than a copy of the first.
        #
        # Three GTK destinations, not two. GTK resolves a nested @import against
        # the *entry* file's directory rather than the importing file's, so the
        # GTK 4 sheet reached through .config/gtk-4.0/gtk.css looks for its
        # palette there — not next to itself in .themes/.
        local pair src dst copied=0
        for pair in \
            "colors-fabric.css:$HOME/.config/fabric_shell/css/colors-fabric.css" \
            "colors-gtk.css:$HOME/.themes/archdots/gtk-3.0/colors.css" \
            "colors-gtk.css:$HOME/.themes/archdots/gtk-4.0/colors.css" \
            "colors-gtk.css:$HOME/.config/gtk-4.0/colors.css"
        do
            src="$HOME/.cache/wal/${pair%%:*}"
            dst="${pair#*:}"
            if [[ ! -f "$src" ]]; then
                warn "$src missing — is .config/wal/templates/ stowed?"
                continue
            fi
            # The parent is a stowed symlink on a normal install, but a partial
            # or --skip-stow run can leave it absent, and cp would fail there.
            if [[ ! -d "$(dirname "$dst")" ]]; then
                warn "$(dirname "$dst") missing — skipping its palette"
                continue
            fi
            cp "$src" "$dst" && copied=$(( copied + 1 ))
        done
        ok "palette copied to $copied consumer(s)"
    fi
}

# ── the vendored libadwaita stylesheet ──────────────────────────────────────
#
# GTK 4 loads exactly one theme stylesheet, so .themes/archdots/gtk-4.0/ cannot
# be a partial sheet the way the GTK 3 one is: loading it *replaces*
# libadwaita's rather than adding to it, and every metric libadwaita defines
# goes with it — AdwActionRow collapses from 50px, boxed lists lose their card
# shape, tooltips come back light-on-white. The theme therefore ships
# libadwaita's own stylesheet and only recolours it.
#
# That copy has to match the libadwaita actually installed, so it is re-extracted
# here on every install and update — which is exactly when libadwaita changes.
# It is a tracked file, so a refresh does show up in `git status`; that is
# deliberate, since a clone without it would leave flatpaks unstyled.

stage_gtk4_base() {
    step "GTK 4 base stylesheet"

    local dir="$HOME/.themes/archdots/gtk-4.0"
    local lib="/usr/lib/libadwaita-1.so.0"
    local res="/org/gnome/Adwaita/styles"

    if [[ ! -d "$dir" ]]; then
        skip "$dir missing — was stow run?"
        return 0
    fi
    if ! command -v gresource >/dev/null; then
        warn "gresource not found (glib2-devel) — keeping the vendored copy"
        return 0
    fi
    if [[ ! -f "$lib" ]]; then
        warn "$lib not found — keeping the vendored copy"
        return 0
    fi

    # Extract to a temporary file first: a failed extraction that truncated
    # adw-base.css in place would leave every GTK 4 app unstyled until the next
    # run, which is a far worse state than a slightly stale copy.
    local tmp asset
    tmp="$(mktemp)"
    if gresource extract "$lib" "$res/gtk.css" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        mv "$tmp" "$dir/adw-base.css"
        # mktemp creates 0600 and mv keeps it, which would leave the stylesheet
        # readable only by this user. Themes are read by other contexts — a
        # flatpak's sandbox among them — so it has to be world-readable.
        chmod 644 "$dir/adw-base.css"
        mkdir -p "$dir/assets"
        # The sheet names these four by relative path, so they travel with it.
        for asset in bullet check dash devel; do
            gresource extract "$lib" "$res/assets/$asset-symbolic.svg" \
                > "$dir/assets/$asset-symbolic.svg" 2>/dev/null || true
        done
        ok "refreshed from $(pacman -Q libadwaita 2>/dev/null || echo libadwaita)"
        note "edited tracked file .themes/archdots/gtk-4.0/adw-base.css (libadwaita)"
    else
        rm -f "$tmp"
        warn "could not read $res/gtk.css — keeping the vendored copy"
    fi

    # The recolour has to sit *beside* .config/gtk-4.0/gtk.css rather than be
    # imported across from ~/.themes. A flatpak mounts that directory inside its
    # own per-app home, so a relative "../.." climbs to ~/.var/app/<app-id>/ and
    # the import fails with nothing but a warning on stderr — the sheet then
    # loads with no colours at all, and every flatpak sits on Adwaita blue while
    # the host looks perfectly fine. Copying it in keeps both resolving locally.
    local cfg="$HOME/.config/gtk-4.0"
    if [[ -d "$cfg" && -f "$dir/overrides.css" ]]; then
        cp "$dir/overrides.css" "$cfg/overrides.css"
        chmod 644 "$cfg/overrides.css"
        ok "recolour copied into .config/gtk-4.0/"
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
    # A preference with no safe default, so it is asked even in a dialog run.
    prompt_begin
    choice="$(choose "blueman draws its own centred popup when it connects a device before the shell has claimed the notification bus — which is what happens at boot, when a headset auto-connects.

What should it do?" "1" \
        1 "Disable ConnectionNotifier — stops the popup" \
        2 "Disable both plugins — also stops auto-reconnect" \
        3 "Leave blueman alone")"
    prompt_end
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
            if run_logged "Enabling $svc" "${SUDO[@]}" systemctl enable "$svc"; then
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
# the pywal16 colours, start them again — all inside one shell, so that shell's
# own command line is what its own pkill sees rather than the processes it is
# about to spawn.

# Both patterns are anchored to *this* $HOME. The bracket in fabric_shel[l] is
# what keeps pkill from matching the shell running the restart itself; the $HOME
# prefix is what keeps it from matching a session belonging to another home
# under the same user — an installer run with HOME pointed somewhere else would
# otherwise kill the desktop that is running right now. (Found the hard way.)
SHELL_PROCS="$HOME/\.config/fabric_shel[l][^ ]*/(daemon|bar)\.py"
SHELL_PROCS_ALL="$HOME/\.config/fabric_shel[l][^ ]*/(daemon|bar|notifications)\.py"

shell_is_running() {
    pgrep -f "$SHELL_PROCS" >/dev/null 2>&1
}

restart_shell() {
    step "Restarting the shell"
    if ! shell_is_running; then
        skip "not running — it starts itself at your next login"
        return 0
    fi
    if ! interactive confirm "Restart the running shell now?

The bar and the overlays disappear for a second while it comes back. Skip this if you are in the middle of something — SUPER + SHIFT + R does the same later." y; then
        skip "left running the old code"
        note "restart the shell with SUPER + SHIFT + R, or log out and back in"
        return 0
    fi
    # setsid, or the new daemon is a child of this script and dies with it.
    setsid bash -c '
        R=$HOME/.config/fabric_shell; PY=$R/.venv/bin/python
        pkill -f "'"$SHELL_PROCS_ALL"'"
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
    phase 2 15 "Pulling the latest changes"
    step "Updating the repository"

    if [[ ! -d "$REPO_ROOT/.git" ]]; then
        warn "$REPO_ROOT is not a git clone — nothing to pull"
        note "this copy was not cloned, so it cannot be pulled; fetch a fresh one"
        return 0
    fi

    local before after dirty stashed=0 count
    before="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

    # The machine-specific values live outside the repo now, but the pywal16
    # palette is still copied into the tracked colors-fabric.css, so an
    # installed clone can be dirty for reasons the user did not choose. Stash
    # whatever is there across the pull and put it back afterwards; git would
    # otherwise refuse to fast-forward over it.
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

    phase 15 45 "Packages the repo has added"
    step "Package lists"
    pac_install "Core packages and fonts" "${PKG_CORE[@]}" "${PKG_FONTS[@]}"
    ok "core and fonts up to date"

    if (( WANT_UTILS )); then
        pac_install "Utilities" "${PKG_UTILS[@]}" && ok "utilities up to date"
    fi

    # PKG_AUR_CORE carries the theming engine, so it is refreshed whether or not
    # the optional AUR list is wanted — the same reason it is mandatory above.
    if command -v paru >/dev/null; then
        run_logged "Theming engine" paru -S --needed --noconfirm "${PKG_AUR_CORE[@]}" \
            && ok "theming engine up to date" \
            || warn "python-pywal16 could not be updated — continuing"
    else
        skip "paru not installed — python-pywal16 left alone"
    fi

    if (( WANT_AUR )) && command -v paru >/dev/null; then
        phase 45 60 "AUR packages"
        step "AUR packages"
        run_logged "AUR packages" paru -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: paru -S ${PKG_AUR[*]}"
        }
        ok "done"
    elif (( WANT_AUR )); then
        skip "paru not installed — AUR packages left alone"
    fi

    # Not asked in dialog mode: there the run is unattended, and a full system
    # upgrade is a bigger thing than "update my dotfiles" — it has to be chosen
    # deliberately, so the default is no and it stays no.
    if interactive confirm "Upgrade the whole system as well (pacman -Syu)?" n; then
        phase 60 70 "Upgrading the system"
        step "System upgrade"
        run_logged "System upgrade" "${SUDO[@]}" pacman -Syu --noconfirm
        ok "upgraded"
    fi
}

run_update() {
    # Before the gauge, always: the password box is ours to draw, and after this
    # point sudo asks through the askpass helper instead of the terminal.
    sudo_askpass_setup
    sudo_authenticate

    gauge_open "Updating archdots"

    update_repo
    update_packages
    stage_stow          # picks up whatever the update added, moved or renamed
    stage_venv upgrade  # requirements.txt may have moved to a newer fabric
    stage_wallpapers    # copies any new wallpapers into ~/Pictures/wallpapers
    stage_gtk4_base     # update_packages may have moved libadwaita under us
    phase 97 100 "Finishing up"
    gauge_close
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
    [[ -n "$LOG_FILE" ]] && printf '\n    full log: %s\n' "$LOG_FILE"
    printf '\n'
}

# ── install ─────────────────────────────────────────────────────────────────

run_install() {
    # Before the gauge, for the same reason as in run_update: a password
    # request is the one thing that must never land behind the bar.
    sudo_askpass_setup
    sudo_authenticate

    gauge_open "Installing archdots"

    stage_packages
    (( DO_PACKAGES )) && install_sddm_theme
    stage_stow
    stage_zsh
    stage_venv
    phase 96 97 "Wallpapers"
    stage_wallpapers
    phase 97 98 "This machine's hardware"
    stage_machine
    phase 98 99 "Theming"
    stage_gtk4_base
    stage_theming
    stage_dconf
    phase 99 100 "Services"
    stage_services
    gauge_close

    step "Done"
    say "Log out and pick Hyprland at the SDDM login screen. The desktop starts itself."
    say "Press SUPER + / once you are in for the keybind cheatsheet."

    if (( ${#SUMMARY[@]} )); then
        printf '\n    %sWorth knowing:%s\n' "$B" "$R"
        printf '      • %s\n' "${SUMMARY[@]}"
    fi

    cat <<EOF

    ${B}What this machine got, and where it lives${R}
    None of it is in a tracked file, so \`git status\` stays clean and none of
    it can follow you onto another machine.
      monitors, input, autorun   ~/.config/hypr/config/custom/*.lua
      GPU order                  ~/.config/uwsm/env-hyprland.d/10-gpu.sh
      wallpaper                  $WALLPAPER_POINTER
    Anything else that differs here belongs in config/custom/ too — it is loaded
    after the defaults, so whatever it sets wins. See
    DEVELOPMENT.md#per-machine-config.

    ${B}Later${R}
      $REPO_ROOT/install.sh update

    ${B}Full log${R}
      ${LOG_FILE:-not written}

EOF
}

# ── which of the two, and with what ─────────────────────────────────────────
#
# Only the dialog build asks. With no mode on the command line and no dialogs,
# it installs — which is what every existing curl one-liner expects.
#
# Picking from these menus is the *only* question a dialog run asks. Ticking a
# box already means "yes, do this", so asking again once the run is under way
# would be asking the same question twice; everything after this point takes the
# answer it was given. --no-gui is the mode that stops at each step.

choose_stages() {
    local sel tag
    on_off() { (( $1 )) && printf 'on' || printf 'off'; }

    sel="$(wt --title "Custom install" --checklist \
        "Everything ticked here runs without asking again.

$KEYS_LIST" 20 76 7 \
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

Whatever you pick runs on its own from here. The output goes to
a log file and this screen keeps a progress bar instead; run it
with --no-gui to be asked about each step and watch it work.

$KEYS_MENU" 20 76 4 \
        install "Install: packages, dotfiles, shell, machine config" \
        update  "Update: pull, re-link, refresh packages and the venv" \
        custom  "Custom install: pick the stages yourself" \
        quit    "Quit")" || MODE="quit"

    case "$MODE" in
        quit|"") say "nothing to do"; exit 0 ;;
        custom)  MODE="install"; choose_stages ;;
    esac

    # The menu *was* the consent, for both paths. Answer the rest from the
    # defaults so the run is unattended — the gauge could not show a prompt
    # anyway, and a question behind it would look like a hang.
    ASSUME_YES=1
}

# ── main ────────────────────────────────────────────────────────────────────

choose_mode
log_open "$MODE"
locate_repo

case "$MODE" in
    update) run_update ;;
    *)      run_install ;;
esac
