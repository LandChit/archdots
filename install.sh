#!/usr/bin/env bash
#
# SimplyChit installer — https://github.com/LandChit/archdots
#
# Two ways to run it:
#
#   curl -fsSL https://raw.githubusercontent.com/LandChit/archdots/main/install.sh | bash
#   ./install.sh          # from inside an existing clone
#
# It clones the repo if it is not already in one, installs the
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
# stow, the shell and every gsettings call must run as you, not as root.

set -euo pipefail

# ── settings ────────────────────────────────────────────────────────────────

REPO_URL_DEFAULT="https://github.com/LandChit/archdots"
REPO_DIR_DEFAULT="$HOME/simplychit"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# The wallpaper this machine is using, as a symlink. hyprlock.conf points at it
# instead of at a picture, which keeps that file identical on every machine and
# out of `git status`; the shell's wallpaper picker re-points it.
WALLPAPER_POINTER="$HOME/.local/state/simplychit/wallpaper"

# The SDDM theme is pinned. Its config schema changes between releases, and
# .themes_sddm/ holds a default.conf written against this one.
SDDM_THEME_VERSION="1.3.5"

# Packages. These mirror README.md#packages — keep the two in step.
#
# Core is what the desktop cannot start without. Everything else is optional and
# lives further down, because a package that is merely nice to have should not
# be able to fail an install.
PKG_CORE=(
    # hyprlock is the lock screen unless the shell's own is switched on, and
    # its fallback either way; hyprpolkitagent is the polkit fallback.
    hyprland hyprlock hypridle hyprpolkitagent
    # The desktop shell (~/.config/quickshell/simplychit): bar, wallpaper, every
    # panel, notifications, polkit. Its battery meter reads UPower, which is
    # D-Bus activated: nothing to enable.
    quickshell upower
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm sddm
    alacritty dolphin
    cliphist wl-clipboard grim slurp brightnessctl playerctl libnotify
    # the shell's volume and notification sounds (services/Sounds.qml)
    sound-theme-freedesktop
    pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol
    networkmanager bluez bluez-utils blueman
    qt6ct kvantum qt5-wayland qt6-wayland
    # .webp wallpapers: the picker lists them, and Qt cannot read them without
    # it (the palette would change and the picture would not)
    qt6-imageformats
    # GTK side of the theming. .config/gtk-3.0/settings.ini names both of these
    # by name; without them GTK silently falls back to Adwaita *light* and the
    # shell renders white panels with unreadable text.
    breeze-icons adwaita-fonts
    zsh stow git
    # .zshrc sources both from /usr/share/zsh/plugins/ (they used to be git
    # submodules under .ohmyzsh_custom/plugins/).
    zsh-autosuggestions zsh-syntax-highlighting
    # .zshrc calls all four unconditionally — `eval "$(zoxide init zsh)"` plus
    # `alias cd="z"`, `alias ls="eza …"`, `alias cat="bat"`, `eval "$(fzf --zsh)"`.
    # Leaving any of them out breaks the login shell, `cd` included.
    zoxide fzf eza bat
    # hypr/config/autorun.lua starts pam_kwallet_init; kwalletmanager5 is
    # the wallet's settings app.
    kwallet-pam kwalletmanager
    # whiptail, for this script's own dialogs. Cheap, and it means the *next*
    # run — an update, or a re-run after a change — gets the boxes even if this
    # one had to fall back to plain prompts.
    libnewt
    # what makepkg needs to bootstrap paru
    base-devel
)

# JetBrainsMono Nerd is required — without it every glyph in the bar is a box.
# Noto covers emoji (the picker) and CJK; dejavu and roboto are the generic
# fallbacks GTK and Qt reach for when an app asks for a family neither has.
PKG_FONTS=(
    ttf-jetbrains-mono-nerd ttf-dejavu ttf-roboto
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
)

PKG_UTILS=(
    tlp fd nvtop fastfetch tmux unzip wget curl smartmontools ark
    # External monitor brightness over DDC/CI (the shell's brightness keys on
    # a non-laptop screen). Needs the i2c-dev module and access to /dev/i2c-*.
    ddcutil
    # Events under the calendar's month grid: khal reads the calendars,
    # vdirsyncer syncs them with Google or CalDAV (CUSTOMIZING.md, Calendar).
    khal vdirsyncer
    # the system monitor, themed from the wallpaper (simplychit sync-palette,
    # stage_app_theming)
    btop
    # screen recording from the screenshot menu and SUPER+SHIFT+R
    wf-recorder
    # QR codes: show the clipboard as one, read one off the screen
    qrencode zbar
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
    # the browser's colours from the wallpaper; needs its add-on in the browser
    python-pywalfox
)

# Tools only. Media players, office suites and game launchers are a matter of
# taste and are quicker to install by hand than to argue with in a script.
#
# From the official repos wherever they are packaged: these used to be
# flatpaks, and a first install spent up to an hour on Flathub's bandwidth for
# them (VLC and OBS alone pulled in the whole KDE runtime). Pacman mirrors are
# ranked and close by. Arch splits VLC's codecs into plugin packages; without
# vlc-plugins-all it plays next to nothing.
#
# Fresh installs only: an update does not add them, since an existing install
# has the flatpak copies and would end up with every app twice.
PKG_APPS=(
    flatseal mission-center vlc vlc-plugins-all obs-studio snapshot
    gnome-text-editor
)

# Only what the official repos do not carry. Empty for now (Packet was the
# last, and not worth its runtime download); the flatpak stage skips itself
# while it is, so adding an app id here is all it takes to bring it back.
PKG_FLATPAK=(
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
WANT_APPS=1
WANT_AUR=1
WANT_FLATPAK=1
WANT_GREETER=1          # greetd + the shell's login screen; --no-greeter: SDDM instead
DO_PACKAGES=1
DO_STOW=1
DO_MACHINE=1

usage() {
    cat <<'EOF'
SimplyChit installer

Usage: install.sh [install|update] [options]

  install             Full install (the default).
  update              Pull the repo, re-link, refresh the packages and the
                      virtualenv, and offer to restart the running shell.

With whiptail installed this runs as dialogs: you pick what to install once, and
the rest is unattended behind a progress bar, with the full output kept in
~/.local/state/simplychit/. Use --no-gui to be asked about each step instead, in
plain text, with every command's output on screen.

  -y, --yes           Take the default for every prompt (non-interactive).
                      Implies --no-gui.
      --no-gui        Plain-text prompts instead of whiptail dialogs, and one
                      question per step. (--gui forces the dialogs back on.)
      --repo URL      Clone from URL instead of the default remote.
      --dir PATH      Clone into PATH (default: ~/simplychit).
      --no-apps       Skip the applications (VLC, OBS, Mission Center, ...).
      --no-flatpak    Skip the flatpak applications.
      --no-utils      Skip the utility packages.
      --no-aur        Skip the AUR helper and every AUR package.
      --no-greeter    Use SDDM (silent theme) as the login screen instead of
                      the shell's own greeter on greetd.
      --skip-packages Install nothing; only link, build and configure.
      --skip-stow     Do not run stow.
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
        --no-apps)       WANT_APPS=0 ;;
        --no-aur)        WANT_AUR=0 ;;
        --greeter)       WANT_GREETER=1 ;;   # kept: it used to be opt-in
        --no-greeter)    WANT_GREETER=0 ;;
        --skip-packages) DO_PACKAGES=0 ;;
        --skip-stow)     DO_STOW=0 ;;
        # the fabric shell's virtualenv is gone; still accepted so older
        # scripts that pass it keep working
        --skip-venv)     ;;
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
LOG_DIR="$HOME/.local/state/simplychit"

log_open() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    LOG_FILE="$LOG_DIR/${1:-install}-$(date +%Y%m%d-%H%M%S).log"
    {
        printf 'SimplyChit %s\n' "${1:-install}"
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
    export SIMPLYCHIT_GAUGE_PID="$GAUGE_PID"

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
    export SIMPLYCHIT_GAUGE_PID=""
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
# Written by SimplyChit install.sh, and run by sudo instead of prompting on the
# terminal.
#
# $SIMPLYCHIT_TTY, not /dev/tty: whoever called sudo may have no controlling
# terminal, and /dev/tty is exactly that terminal — it cannot be opened from a
# detached process. If even the named device is unusable, exit rather than hand
# sudo an empty password: three silent retries and a "Sorry, try again" tell
# nobody anything.
T="${SIMPLYCHIT_TTY:-/dev/tty}"
if [[ ! -r "$T" || ! -w "$T" ]]; then
    printf 'SimplyChit: no terminal to ask for a password on (%s)\n' "$T" >&2
    exit 1
fi
# SIGSTOP rather than a kill: the gauge has to survive to be resumed, and a
# stopped process cannot repaint over the box while it is up.
[[ -n "${SIMPLYCHIT_GAUGE_PID:-}" ]] && kill -STOP "$SIMPLYCHIT_GAUGE_PID" 2>/dev/null
[[ -n "${SIMPLYCHIT_ASKPASS_FLAG:-}" ]] && : > "$SIMPLYCHIT_ASKPASS_FLAG"
pw="$(whiptail --backtitle "${SIMPLYCHIT_BACKTITLE:-simplychit}" \
    --title "Administrator password" \
    --passwordbox "${1:-Password:}

Installing packages needs root. Your password is not
stored, and nothing is echoed as you type.

Enter confirms · Esc cancels" 13 62 2>&1 1>"$T" <"$T")"
[[ -n "${SIMPLYCHIT_GAUGE_PID:-}" ]] && kill -CONT "$SIMPLYCHIT_GAUGE_PID" 2>/dev/null
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
# Written by SimplyChit install.sh. See sudo_askpass_setup.
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
    export SIMPLYCHIT_ASKPASS_FLAG="$ASKPASS_FLAG"
    export SIMPLYCHIT_BACKTITLE="$BACKTITLE"
    export SIMPLYCHIT_TTY="$term"
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
BACKTITLE="SimplyChit — Arch + Hyprland desktop"

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
        wt_status --title "SimplyChit" "${defaultno[@]}" \
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
        reply="$(wt --title "SimplyChit" --inputbox "$text" \
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
        reply="$(wt --title "SimplyChit" --default-item "$default" \
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
    reply="$(wt --title "SimplyChit" --radiolist "$text" "$height" 76 "$rows" "${items[@]}")" \
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

(( EUID != 0 )) || die "do not run this as root — stow, the shell and gsettings must run as your user."
command -v pacman >/dev/null || die "pacman not found. This installer is for Arch Linux."
command -v sudo   >/dev/null || die "sudo not found. Install it and add your user to a wheel rule."

ui_init

printf '\n%sSimplyChit%s — Arch + Hyprland desktop\n' "$B" "$R"
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
    [[ -f "$dir/install.sh" && -d "$dir/home/.config/quickshell/simplychit" ]] || return 1
    printf '%s' "$dir"
}

locate_repo() {
    step "Locating the repository"
    if REPO_ROOT="$(find_repo_root)"; then
        ok "running from $REPO_ROOT"
    else
        command -v git >/dev/null || {
            say "git is missing; installing it first"
            "${SUDO[@]}" pacman -Sy --needed --noconfirm git
        }
        if [[ -e "$REPO_DIR" ]]; then
            # home/ is the layout since the dotfiles moved there; a clone from
            # before it has .stow-local-ignore at the root and is updated below.
            if [[ -d "$REPO_DIR/home" || -f "$REPO_DIR/.stow-local-ignore" ]]; then
                ok "existing clone at $REPO_DIR"
            else
                die "$REPO_DIR exists and is not a SimplyChit clone. Move it, or pass --dir."
            fi
        else
            say "cloning $REPO_URL into $REPO_DIR"
            git clone "$REPO_URL" "$REPO_DIR"
            ok "cloned"
        fi
        REPO_ROOT="$REPO_DIR"

        # Hand over to the freshly cloned copy so the rest of the run uses the
        # version that is actually on disk.
        if [[ "${SIMPLYCHIT_REEXEC:-}" != 1 ]]; then
            say "handing over to $REPO_ROOT/install.sh"
            export SIMPLYCHIT_REEXEC=1
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

# ── this system ─────────────────────────────────────────────────────────────
#
# Plain Arch and its derivatives (EndeavourOS, CachyOS, Garuda, Manjaro, ...)
# differ in what they set up already: an AUR helper, a login screen, the audio
# server, the network manager. All of it is read once, here, so the stages
# fit in with it instead of fighting it, and every question that changes how
# the machine boots or gets online is asked before anything runs. Those
# questions default to no: --yes never switches someone else's login screen
# or network manager. (Only SDDM, or no login screen at all, defaults to yes
# for the greeter: see stage_greeter.)

# Tested with these; older ones may not read the Lua config or the QML.
MIN_HYPRLAND="0.56"
MIN_QUICKSHELL="0.3"

DISTRO_ID=""
DISTRO_NAME=""
AUR_HELPER=""       # paru or yay when a working one is here; else paru is built
DM_CURRENT=""       # the enabled login screen's unit, without .service
DM_LABEL=""
WANT_SDDM=1         # 0: another login screen stays; SDDM is neither themed nor enabled
IS_LAPTOP=0
GPU_VENDORS=()
PULSE_PKGS=()       # PulseAudio packages to swap for pipewire-pulse
REPLACE_PULSE=0
NET_OTHER=()        # other enabled network managers
WANT_NM=1           # 0: leave networking as it is; NetworkManager is not enabled

aur_works() { command -v "$1" >/dev/null && "$1" --version &>/dev/null; }

# repo_version PKG: the version pacman would install, or the installed one
repo_version() {
    { pacman -Si "$1" 2>/dev/null || pacman -Qi "$1" 2>/dev/null; } | awk '/^Version/{print $3; exit}'
}

# drop_pkg ARRAY PKG: remove PKG from the named package list
drop_pkg() {
    local -n list="$1"
    local kept=() p
    for p in "${list[@]}"; do [[ "$p" == "$2" ]] || kept+=("$p"); done
    list=(${kept+"${kept[@]}"})
}

detect_system() {
    step "Looking at this system"
    local like="" v unit dm chassis bats=() card vendor pkg have_driver=0
    command -v pacman >/dev/null \
        || die "pacman not found: SimplyChit installs on Arch Linux and Arch-based systems only."
    if [[ -r /etc/os-release ]]; then
        DISTRO_ID="$(. /etc/os-release && printf '%s' "${ID:-}")"
        DISTRO_NAME="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${NAME:-$ID}}")"
        like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    fi
    case " $DISTRO_ID $like " in
        *" arch "*) ok "${DISTRO_NAME:-Arch-based}" ;;
        *) warn "${DISTRO_NAME:-this system} does not say it is Arch-based; carrying on, since pacman is here" ;;
    esac
    if [[ "$DISTRO_ID" == manjaro* ]]; then
        warn "Manjaro's repositories run a few weeks behind Arch's"
        note "on Manjaro, Hyprland and Quickshell can be older than these dots need"
    fi

    # ── versions the repositories offer ────────────────────────────────────
    v="$(repo_version hyprland)"
    if [[ -n "$v" ]] && (( $(vercmp "${v%%-*}" "$MIN_HYPRLAND") < 0 )); then
        warn "Hyprland $v is older than $MIN_HYPRLAND, which these dots are made for"
        note "Hyprland $v may not load the Lua config; update the system or wait for $MIN_HYPRLAND"
    fi
    v="$(repo_version quickshell)"
    if [[ -n "$v" ]] && (( $(vercmp "${v%%-*}" "$MIN_QUICKSHELL") < 0 )); then
        warn "Quickshell $v is older than $MIN_QUICKSHELL, which the shell is written for"
        note "Quickshell $v may not load the shell"
    fi

    # ── AUR helper ──────────────────────────────────────────────────────────
    # EndeavourOS ships yay, CachyOS and Garuda paru. Either is used as it is.
    if aur_works paru; then
        AUR_HELPER=paru
    elif aur_works yay; then
        AUR_HELPER=yay
    fi
    say "AUR helper: ${AUR_HELPER:-none yet (paru gets built)}"

    # ── hardware ────────────────────────────────────────────────────────────
    shopt -s nullglob
    bats=(/sys/class/power_supply/BAT*)
    for card in /sys/class/drm/card[0-9]; do
        vendor="$(cat "$card/device/vendor" 2>/dev/null || true)"
        case "$vendor" in
            0x10de) GPU_VENDORS+=(NVIDIA) ;;
            0x1002) GPU_VENDORS+=(AMD) ;;
            0x8086) GPU_VENDORS+=(Intel) ;;
            "") ;;
            *) GPU_VENDORS+=("$vendor") ;;
        esac
    done
    shopt -u nullglob
    chassis="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || true)"
    # 8-10, 14, 30-32: portable, laptop, notebook, sub-notebook, tablet, convertible, detachable
    if (( ${#bats[@]} )) || [[ "$chassis" =~ ^(8|9|10|14|30|31|32)$ ]]; then
        IS_LAPTOP=1
    fi
    say "GPU: ${GPU_VENDORS[*]:-none found}; $( (( IS_LAPTOP )) && echo laptop || echo desktop)"
    if [[ " ${GPU_VENDORS[*]} " == *" NVIDIA "* ]]; then
        for pkg in nvidia nvidia-open nvidia-dkms nvidia-open-dkms nvidia-lts nvidia-open-lts \
            linux-cachyos-nvidia linux-cachyos-nvidia-open; do
            pacman -Qq "$pkg" &>/dev/null && { have_driver=1; break; }
        done
        if (( ! have_driver )); then
            warn "an NVIDIA GPU without the NVIDIA driver"
            note "Hyprland on NVIDIA needs the proprietary driver: nvidia-open on Arch (Turing and newer), or your distribution's driver tool"
        fi
    fi
    # Only laptops get TLP. A desktop gets power-profiles-daemon instead, for
    # the control centre's power profiles, unless TLP is there already (the two
    # conflict).
    if (( ! IS_LAPTOP )); then
        drop_pkg PKG_UTILS tlp
        pacman -Qq tlp &>/dev/null || PKG_UTILS+=(power-profiles-daemon)
    fi

    # ── audio ───────────────────────────────────────────────────────────────
    # pipewire-pulse conflicts with PulseAudio, and pacman --noconfirm answers
    # "no" to removing it, which fails the whole core install.
    mapfile -t PULSE_PKGS < <(pacman -Qq 2>/dev/null | grep -E '^pulseaudio(-.*)?$' || true)
    if (( ${#PULSE_PKGS[@]} )); then
        if interactive confirm "PulseAudio is installed (${PULSE_PKGS[*]}).

SimplyChit uses PipeWire: the shell's volume controls and device switching talk to it. pipewire-pulse replaces PulseAudio and keeps every PulseAudio app working.

Replace PulseAudio with PipeWire?" y; then
            REPLACE_PULSE=1
        else
            drop_pkg PKG_CORE pipewire-pulse
            warn "PulseAudio stays; the shell's audio controls will not see your devices"
            note "PulseAudio kept: the volume OSD and the audio tab need PipeWire (pipewire-pulse)"
        fi
    fi

    # ── what this machine boots into (asked in install mode only) ───────────
    [[ "$MODE" == update ]] && return 0

    dm="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
    if [[ -n "$dm" && -e "$dm" ]]; then
        DM_CURRENT="$(basename -- "$dm" .service)"
    fi
    if (( WANT_GREETER )); then
        # SDDM stays installed (the fallback, and the way back) but is neither
        # themed nor enabled; stage_greeter asks about switching the login screen
        WANT_SDDM=0
        [[ -n "$DM_CURRENT" ]] && say "login screen: $DM_CURRENT"
    elif [[ -n "$DM_CURRENT" && "$DM_CURRENT" != sddm ]]; then
        say "login screen: $DM_CURRENT"
        if interactive confirm "$DM_CURRENT is this system's login screen.

SimplyChit comes with a themed SDDM. Switch to it? $DM_CURRENT stays installed and is only disabled; the switch happens at the next boot. To go back, from a TTY (Ctrl+Alt+F2):

  sudo systemctl disable sddm && sudo systemctl enable $DM_CURRENT

No keeps $DM_CURRENT: pick Hyprland in its session menu." n; then
            WANT_SDDM=1
        else
            WANT_SDDM=0
            DM_LABEL="$DM_CURRENT"
            note "kept $DM_CURRENT as the login screen; pick the Hyprland session there"
        fi
    fi

    for unit in systemd-networkd iwd connman dhcpcd netctl; do
        systemctl is-enabled "$unit.service" &>/dev/null && NET_OTHER+=("$unit")
    done
    if (( ${#NET_OTHER[@]} )) && ! systemctl is-enabled NetworkManager.service &>/dev/null; then
        say "networking: ${NET_OTHER[*]}"
        if interactive confirm "This system gets online with ${NET_OTHER[*]}.

The control centre's Wi-Fi and network settings need NetworkManager. Switch to it? ${NET_OTHER[*]} stays installed and is only disabled, at the next boot. Have your Wi-Fi password ready. To go back, from a TTY:

  sudo systemctl disable NetworkManager && sudo systemctl enable ${NET_OTHER[*]}

No leaves networking as it is (the network tab will be empty)." n; then
            WANT_NM=1
        else
            WANT_NM=0
            note "networking left on ${NET_OTHER[*]}; the control centre's network tab needs NetworkManager"
        fi
    else
        NET_OTHER=()
    fi
    return 0
}

# Swap PulseAudio for pipewire-pulse before the core install (see detect_system).
replace_pulse() {
    (( REPLACE_PULSE && ${#PULSE_PKGS[@]} )) || return 0
    # -dd: what depends on PulseAudio is satisfied again by pipewire-pulse,
    # installed right after this.
    run_logged "Removing PulseAudio (${PULSE_PKGS[*]})" "${SUDO[@]}" pacman -Rdd --noconfirm "${PULSE_PKGS[@]}" \
        || die "could not remove PulseAudio — see the log."
    ok "PulseAudio removed; pipewire-pulse takes its place"
    note "replaced PulseAudio with PipeWire (log out and in for apps to reconnect)"
    REPLACE_PULSE=0
}

# A working AUR helper in $AUR_HELPER: the one detect_system found, or paru,
# built from source.
ensure_aur_helper() {
    if [[ -n "$AUR_HELPER" ]]; then
        skip "$AUR_HELPER already installed"
        return 0
    fi
    ensure_paru
    AUR_HELPER=paru
}

# A scratch dir for package builds, on disk. Not mktemp's /tmp: that is RAM
# on Arch (tmpfs), and paru's LTO link alone needs a few GB, so a build tree
# there gets a 4 GB machine's rustc killed by the OOM killer (found in a VM).
build_dir() {
    local base="${XDG_CACHE_HOME:-$HOME/.cache}/simplychit"
    mkdir -p "$base" && mktemp -d "$base/build.XXXXXX"
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
    tmp="$(build_dir)"
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

    replace_pulse

    phase 6 42 "Core packages and fonts"
    step "Core packages and fonts"
    say "${#PKG_CORE[@]} core + ${#PKG_FONTS[@]} font packages"
    run_logged "Core packages and fonts" \
        "${SUDO[@]}" pacman -Syu --needed --noconfirm "${PKG_CORE[@]}" "${PKG_FONTS[@]}" \
        || die "pacman could not install the core packages."
    ok "installed"

    if (( WANT_UTILS )) && confirm "Install the utility packages (${#PKG_UTILS[@]})?

${PKG_UTILS[*]}" y; then
        phase 42 44 "Utilities"
        step "Utilities"
        pac_install "Utilities" "${PKG_UTILS[@]}"
        ok "installed"
    else
        skip "utilities"
    fi

    if (( WANT_APPS )) && confirm "Install the applications (${#PKG_APPS[@]})?

${PKG_APPS[*]}" y; then
        phase 44 46 "Applications"
        step "Applications"
        pac_install "Applications" "${PKG_APPS[@]}"
        ok "installed"
    else
        skip "applications"
    fi

    # Not optional, and not part of the AUR question below. The palette is core
    # to the desktop, and its only source is an AUR package now, so paru has to
    # be built even for someone who declines the optional AUR list.
    phase 46 47 "AUR helper"
    step "AUR helper"
    ensure_aur_helper

    phase 47 48 "Theming engine"
    step "Theming engine"
    run_logged "Theming engine" "$AUR_HELPER" -S --needed --noconfirm "${PKG_AUR_CORE[@]}" || {
        warn "python-pywal16 could not be built — the desktop starts unthemed"
        note "retry: $AUR_HELPER -S ${PKG_AUR_CORE[*]}"
    }
    ok "done"

    if (( WANT_AUR )) && confirm "Install the optional AUR packages (${#PKG_AUR[@]})?

${PKG_AUR[*]}

These are built from source, which takes a few minutes." y; then
        phase 48 64 "AUR packages"
        step "AUR packages"
        # One failed build should not lose the rest of the install.
        run_logged "AUR packages" "$AUR_HELPER" -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: $AUR_HELPER -S ${PKG_AUR[*]}"
        }
        ok "done"
    else
        skip "AUR"
    fi

    if (( ! ${#PKG_FLATPAK[@]} )); then
        skip "flatpaks (none listed)"
    elif (( WANT_FLATPAK )) && confirm "Install the flatpak applications (${#PKG_FLATPAK[@]})?

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
    if (( ! WANT_SDDM )); then
        skip "$DM_CURRENT stays the login screen"
        return 0
    fi

    local theme_dir="/usr/share/sddm/themes/silent"
    local custom_conf="$REPO_ROOT/.themes_sddm/silent_sddmTheme_custom_default/default.conf"

    # ── the package, pinned ─────────────────────────────────────────────────
    local have=""
    have="$(pacman -Qi sddm-silent-theme 2>/dev/null | awk '/^Version/{print $3}')" || true

    if [[ "${have%%-*}" == "$SDDM_THEME_VERSION" ]]; then
        skip "sddm-silent-theme $have already installed"
    elif [[ -z "$AUR_HELPER" ]]; then
        warn "no AUR helper — skipping the theme"
        note "install by hand: paru -S sddm-silent-theme (then pin it)"
        return 0
    else
        # The AUR has no version tags, so walk PKGBUILD history for the newest
        # commit that declares the pkgver we want and build from there.
        local tmp commit=""
        tmp="$(build_dir)"
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
            run_logged "Theme dependencies" "$AUR_HELPER" -S --needed --noconfirm "${deps[@]}" || {
                rm -rf "$tmp"
                warn "could not install the theme's dependencies"
                note "SDDM theme skipped; retry: $AUR_HELPER -S sddm-silent-theme"
                return 0
            }
        fi

        # Built, then installed by us — never `makepkg -si`. See ensure_paru for
        # why makepkg is not allowed to reach for sudo.
        run_logged "Building the SDDM theme" \
            bash -c "cd '$tmp/theme' && makepkg -s --noconfirm" || {
            rm -rf "$tmp"
            warn "theme build failed — the desktop still works, the login screen is plain"
            note "SDDM theme failed to build; retry: $AUR_HELPER -S sddm-silent-theme"
            return 0
        }

        local built=()
        mapfile -t built < <(built_packages "$tmp/theme")
        if (( ! ${#built[@]} )) || ! run_logged "Installing the SDDM theme" \
            "${SUDO[@]}" pacman -U --noconfirm "${built[@]}"; then
            rm -rf "$tmp"
            warn "could not install the built theme package"
            note "SDDM theme not installed; retry: $AUR_HELPER -S sddm-silent-theme"
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
    local sddm_conf="/etc/sddm.conf.d/10-simplychit.conf"
    local sddm_body="# Written by SimplyChit install.sh.
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

# ── the move to home/ ───────────────────────────────────────────────────────
#
# The dotfiles used to sit at the repo root and were stowed with `stow .`. They
# live in home/ now, stowed with `stow --dir=<repo> home`. A clone that pulls
# across that move needs two things put right before stow can run:
#
#   · Ignored files stay behind. git moves what it tracks, but config/custom/
#     overrides, GTK user files, the rendered palette and the shell's venv are
#     not tracked, so they are left at the old paths. Move each into home/.
#   · The old symlinks in $HOME point at the old paths. stow only manages links
#     into its own --dir, so it reports those as conflicts. Remove them, but
#     only links that resolve to exactly the old location of something now in
#     home/, or to a repo-only entry that `stow .` used to link.

migrate_layout() {
    local real moved=0 unlinked=0 top rel src dst link target
    real="$(cd -- "$REPO_ROOT" && pwd -P)"

    # Two leftovers have no place in home/ and would only show up untracked
    # there: the zsh plugins' old submodule checkouts (pacman ships them now and
    # .zshrc reads /usr/share/zsh/plugins/), and the old theme's rendered
    # palette (rendered again under .themes/simplychit/).
    rm -rf -- "$real/.ohmyzsh_custom/plugins/zsh-autosuggestions" \
              "$real/.ohmyzsh_custom/plugins/zsh-syntax-highlighting"
    rm -f -- "$real/.themes/archdots/gtk-3.0/colors.css" \
             "$real/.themes/archdots/gtk-4.0/colors.css"

    for top in .config .themes .ohmyzsh_custom; do
        [[ -d "$real/$top" && ! -L "$real/$top" ]] || continue
        while IFS= read -r -d '' src; do
            rel="${src#"$real/"}"
            dst="$real/home/$rel"
            if [[ -e "$dst" || -L "$dst" ]]; then
                warn "left at old path, home/$rel already exists: $rel"
                note "compare $real/$rel with home/$rel by hand, then delete the old one"
                continue
            fi
            mkdir -p "$(dirname -- "$dst")"
            mv -- "$src" "$dst"
            moved=$(( moved + 1 ))
        # A .venv moves as one directory (thousands of files; retire_fabric
        # then deletes the fabric shell's); everything else file by file.
        done < <(find "$real/$top" \( -type d -name .venv -prune -print0 \) -o \( ! -type d -print0 \))
        find "$real/$top" -depth -type d -empty -delete 2>/dev/null
        [[ -d "$real/$top" ]] || ok "moved what was left in $top/ into home/"
    done
    (( moved )) && ok "$moved untracked file(s) moved from the old layout into home/"

    # Links to anything under home/ that point at the same path without home/.
    while IFS= read -r -d '' rel; do
        rel="${rel#"$real/home/"}"
        link="$HOME/$rel"
        [[ -L "$link" ]] || continue
        target="$(readlink -m -- "$link")"
        if [[ "$target" == "$real/$rel" ]]; then
            rm -- "$link"
            unlinked=$(( unlinked + 1 ))
        fi
    done < <(find "$real/home" -mindepth 1 \( -name .venv -o -name .git \) -prune -o -print0)

    # ~/.custom.zsh was a link to the clone's own .custom.zsh (gitignored, the
    # user's file). The loop below removes that link, which would leave the
    # file unread at the repo root: move it to the new place first, or back to
    # ~/.custom.zsh (still sourced) if the new place is already taken.
    if [[ -f "$real/.custom.zsh" && ! -L "$real/.custom.zsh" ]]; then
        link="$HOME/.custom.zsh"
        if [[ -L "$link" && "$(readlink -m -- "$link")" == "$real/.custom.zsh" ]]; then
            rm -- "$link"
        fi
        if [[ ! -e "$USER_DIR/local/zshrc" ]]; then
            mkdir -p "$USER_DIR/local"
            mv -- "$real/.custom.zsh" "$USER_DIR/local/zshrc"
            ok "moved .custom.zsh to ~/.config/simplychit/local/zshrc"
        elif [[ ! -e "$link" ]]; then
            mv -- "$real/.custom.zsh" "$link"
            ok "moved .custom.zsh out of the clone to ~/.custom.zsh"
        else
            warn "left .custom.zsh in the clone: ~/.custom.zsh and local/zshrc both exist"
        fi
    fi

    # Repo-only entries that `stow .` linked into $HOME before the move.
    for top in "$real"/* "$real"/.[!.]*; do
        top="$(basename -- "$top")"
        [[ "$top" == home ]] && continue
        link="$HOME/$top"
        [[ -L "$link" ]] || continue
        target="$(readlink -m -- "$link")"
        if [[ "$target" == "$real/$top" ]]; then
            rm -- "$link"
            unlinked=$(( unlinked + 1 ))
        fi
    done

    if (( unlinked )); then
        ok "removed $unlinked symlink(s) from the old layout"
    fi
    return 0
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

    migrate_layout

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
    # A real ~/.config (and ~/.local/bin, for the simplychit command), so stow
    # links the folders inside rather than folding the whole directory into
    # one symlink to the repo. Folded, everything any app
    # later creates there, ~/.config/simplychit/ included, lands in the clone.
    # Same for the D-Bus services folder, which other installs write into.
    mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/dbus-1/services"
    simulate="$(stow --simulate --verbose=1 --dir="$REPO_ROOT" --target="$HOME" home 2>&1 || true)"
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
        backup="$HOME/.simplychit-backup-$(date +%Y%m%d-%H%M%S)"
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

    run_logged "Linking the dotfiles" stow --restow --dir="$REPO_ROOT" --target="$HOME" home \
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

# ── the user's own files ────────────────────────────────────────────────────
#
# ~/.config/simplychit/ holds everything the user edits by hand. Nothing in it is
# tracked, and this stage only ever creates a file that is missing: a stub that
# is already there is the user's, edited or not, and is never touched again.

USER_DIR="$HOME/.config/simplychit"

# write_stub <path> <text> — create <path> with <text> unless it exists.
write_stub() {
    if [[ -e "$1" ]]; then
        skip "${1/#$HOME/\~} already there"
        return 0
    fi
    mkdir -p "$(dirname -- "$1")"
    printf '%s\n' "$2" > "$1"
    ok "created ${1/#$HOME/\~}"
}

stage_user_dir() {
    step "Your own config files"
    write_stub "$USER_DIR/local/zshrc" \
'# Your zsh settings. Sourced near the end of ~/.zshrc, so anything here
# overrides the defaults. This file is not tracked and updates never touch it.
#
# alias ll="eza -l"
# export EDITOR=nvim'
    write_stub "$USER_DIR/hypr/keybind.lua" \
'-- Your keybinds. Loaded after the defaults in ~/.config/hypr/config/keybind.lua.
-- This file is not tracked and updates never touch it.
--
-- Binding a combo that is already bound adds a second bind (both fire), so
-- change or delete a default through the helper:
--
-- local bind = require("config.helpers.bind")
-- bind.rebind("SUPER + E", hl.dsp.exec_cmd("nautilus"), { desc = "Launch: File manager" })
-- bind.remove("SUPER + B")
--
-- New combos need no helper. Give each a desc so the cheatsheet (SUPER + /)
-- can say what it does:
-- hl.bind("SUPER + G", hl.dsp.exec_cmd("gimp"), { desc = "Launch: GIMP" })'
    write_stub "$USER_DIR/local/alacritty.toml" \
'# Your alacritty settings. Imported last by ~/.config/alacritty/alacritty.toml,
# so anything here wins. This file is not tracked and updates never touch it.
#
# [font]
# size = 14.0'
    # Inside ~/.config/gtk-4.0/ rather than $USER_DIR: gtk.css can only import
    # from its own directory (flatpaks mount just that one).
    write_stub "$HOME/.config/gtk-4.0/user.css" \
'/* Your GTK 4 rules. Imported last by gtk.css, so anything here wins.
 * This file is not tracked and updates never touch it. */'
    # GTK 3 reads this file itself, over the theme, so it needs no import and
    # nothing tracked uses the path. The theme is in ~/.themes/simplychit/gtk-3.0/.
    write_stub "$HOME/.config/gtk-3.0/gtk.css" \
'/* Your GTK 3 rules. GTK loads this over the SimplyChit theme, so anything here
 * wins. This file is not tracked and updates never touch it. */'

    if [[ -e "$HOME/.custom.zsh" ]]; then
        note "~/.custom.zsh is still sourced; ~/.config/simplychit/local/zshrc is the new place for it"
    fi
}

# ── retiring the fabric shell ───────────────────────────────────────────────
#
# The shell used to be fabric_shell (Python, its own virtualenv). It is now
# Quickshell, and the fabric files are gone from the repo, but a clone that
# pulls across that change still has what git never tracked: the venv,
# __pycache__ and the rendered colors-fabric.css, in home/.config/fabric_shell/.
# Left there, stow would keep ~/.config/fabric_shell linked to it. Its processes
# may also still be running.
#
# Deleted only when git tracks nothing under it any more, so this can never
# remove a file that belongs to the repo.

retire_fabric() {
    local dir="$REPO_ROOT/home/.config/fabric_shell"
    # $HOME-anchored, and fabric_shel[l] so pkill never matches this script
    local procs="$HOME/\.config/fabric_shel[l][^ ]*/(daemon|bar|notifications)\.py"

    if pgrep -f "$procs" >/dev/null 2>&1; then
        pkill -f "$procs" && ok "stopped the old fabric shell"
    fi
    if [[ -d "$dir" ]] && [[ -z "$(git -C "$REPO_ROOT" ls-files -- "$dir" 2>/dev/null)" ]]; then
        rm -rf -- "$dir"
        ok "removed the old fabric shell's leftovers (venv, caches)"
    fi
    if [[ -L "$HOME/.config/fabric_shell" && ! -e "$HOME/.config/fabric_shell" ]]; then
        rm -- "$HOME/.config/fabric_shell"
    fi
    return 0
}

# ── retiring the old name ───────────────────────────────────────────────────
#
# These dotfiles were called archdots before they were SimplyChit. Everything
# named after it moved: the user folder ~/.config/archdots/ (settings.json,
# hypr/, local/), ~/.local/state/archdots/ (the wallpaper pointer, logs), the
# shell (qs -c archdots), the GTK theme, the `archdots` command and the SDDM
# config file. Run after stow, so the new names already exist.
#
# Moves never overwrite: an entry that exists under both names stays in the
# old folder, with a warning.

# merge_dir OLD NEW: move OLD's entries into NEW, then remove OLD if empty
merge_dir() {
    local old="$1" new="$2" entry name left=0
    [[ -d "$old" && ! -L "$old" ]] || return 0
    mkdir -p -- "$new"
    for entry in "$old"/* "$old"/.[!.]*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        name="$(basename -- "$entry")"
        if [[ -e "$new/$name" || -L "$new/$name" ]]; then
            left=$(( left + 1 ))
        else
            mv -- "$entry" "$new/$name"
        fi
    done
    if (( left )); then
        warn "$left entries in ${old/#$HOME/\~} also exist in ${new/#$HOME/\~}; left in place"
        note "compare ${old/#$HOME/\~} with ${new/#$HOME/\~} by hand, then delete the old one"
    else
        rmdir -- "$old" 2>/dev/null
        ok "moved ${old/#$HOME/\~} to ${new/#$HOME/\~}"
    fi
}

OLD_SHELL_RUNNING=0

retire_old_name() {
    local real link target pruned=0 old_conf=/etc/sddm.conf.d/10-archdots.conf
    real="$(cd -- "$REPO_ROOT" && pwd -P)"

    merge_dir "$HOME/.config/archdots" "$HOME/.config/simplychit"
    merge_dir "$HOME/.local/state/archdots" "$HOME/.local/state/simplychit"
    # generated (Hyprland rewrites keybinds.json at every load)
    if [[ -d "$HOME/.cache/archdots" && ! -L "$HOME/.cache/archdots" ]]; then
        rm -rf -- "$HOME/.cache/archdots"
    fi

    # stow leaves links to renamed files behind, dangling: ~/.local/bin/archdots,
    # ~/.config/quickshell/archdots, ~/.themes/archdots, ... Only links into
    # this repo's home/ that point at nothing are removed.
    while IFS= read -r -d '' link; do
        target="$(readlink -m -- "$link")"
        if [[ "$target" == "$real/home/"* ]]; then
            rm -- "$link"
            pruned=$(( pruned + 1 ))
        fi
    done < <(find "$HOME/.config" "$HOME/.local/bin" "$HOME/.themes" -maxdepth 3 -xtype l -print0 2>/dev/null)
    (( pruned )) && ok "removed $pruned link(s) to files the repo renamed"

    if command -v gsettings >/dev/null &&
        [[ "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" == "'archdots'" ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme simplychit 2>/dev/null \
            && ok "GTK theme renamed to simplychit"
    fi

    # ours (the first line says so); renamed, so SDDM keeps its theme
    if [[ -f "$old_conf" ]] && head -1 "$old_conf" 2>/dev/null | grep -q '^# Written by archdots install.sh'; then
        if [[ -e /etc/sddm.conf.d/10-simplychit.conf ]]; then
            "${SUDO[@]}" rm -f -- "$old_conf" && ok "removed the old $old_conf"
        else
            "${SUDO[@]}" mv -- "$old_conf" /etc/sddm.conf.d/10-simplychit.conf \
                && ok "renamed $old_conf to 10-simplychit.conf"
        fi
    fi

    # the running shell under the old name: restart_shell replaces it
    if qs list -c archdots 2>/dev/null | grep -q '^Instance'; then
        OLD_SHELL_RUNNING=1
    fi
    return 0
}

# ── the greeter (the default; --no-greeter for SDDM) ────────────────────────
#
# greetd runs the shell's greeter.qml inside cage, so the login screen has the
# lock screen's look and colours. What it writes, all root-owned and outside
# $HOME:
#   /usr/share/simplychit/shell/      a copy of the shell (the greeter user
#                                     cannot read your home)
#   /var/lib/simplychit/greeter/      the greeter's own HOME (greetd's user
#                                     has / as its home): copies of your
#                                     palette, wallpaper and settings.json,
#                                     its last login
#   /etc/greetd/config.toml           the original kept as config.toml.simplychit-orig
# An update refreshes the copies. The login screen is switched only after a
# question: default yes when there is none yet or it is SDDM (an older
# SimplyChit install), default no for any other one. The old one stays
# installed and is only disabled. If the greeter cannot be set up, SDDM is
# enabled instead, so the machine never boots without a login screen.

GREETER_DIR="/usr/share/simplychit/shell"
GREETD_CONF="/etc/greetd/config.toml"
GREETER_HOME="/var/lib/simplychit/greeter"

greeter_copy_files() {
    local src="$REPO_ROOT/home/.config/quickshell/simplychit" gh="$GREETER_HOME" wall ext
    if ! getent passwd greeter >/dev/null; then
        warn "no greeter user (is greetd installed?)"
        return 1
    fi
    "${SUDO[@]}" mkdir -p "$(dirname "$GREETER_DIR")" || return 1
    "${SUDO[@]}" rm -rf -- "$GREETER_DIR.new"
    "${SUDO[@]}" cp -r -- "$src" "$GREETER_DIR.new" || return 1
    "${SUDO[@]}" rm -rf -- "$GREETER_DIR"
    "${SUDO[@]}" mv -- "$GREETER_DIR.new" "$GREETER_DIR" || return 1

    "${SUDO[@]}" mkdir -p "$gh/.cache/wal" "$gh/.local/state/simplychit" "$gh/.config/simplychit"
    # your settings: the primary screen and the keypad choice (lock.numlock)
    if [[ -r "$HOME/.config/simplychit/settings.json" ]]; then
        "${SUDO[@]}" cp -- "$HOME/.config/simplychit/settings.json" "$gh/.config/simplychit/settings.json"
    fi
    if [[ -r "$HOME/.cache/wal/colors.json" ]]; then
        "${SUDO[@]}" cp -- "$HOME/.cache/wal/colors.json" "$gh/.cache/wal/colors.json"
    fi
    wall="$(readlink -f "$WALLPAPER_POINTER" 2>/dev/null || true)"
    if [[ -f "$wall" ]]; then
        ext="${wall##*.}"
        "${SUDO[@]}" cp -- "$wall" "$gh/.local/state/simplychit/wallpaper-image.$ext"
        "${SUDO[@]}" ln -sfn "wallpaper-image.$ext" "$gh/.local/state/simplychit/wallpaper"
    fi
    "${SUDO[@]}" chown -R greeter:greeter "$gh"
    "${SUDO[@]}" chmod 700 "$gh"
}

# greeter_fallback: the greeter is not the login screen after all. With no
# login screen enabled either, SDDM (installed with the core packages, but
# unthemed) takes its place.
greeter_fallback() {
    [[ -e /etc/systemd/system/display-manager.service ]] && return 0
    systemctl list-unit-files sddm.service &>/dev/null || return 0
    if run_logged "Enabling sddm" "${SUDO[@]}" systemctl enable sddm.service; then
        ok "SDDM is the login screen instead"
        DM_LABEL="SDDM"
        note "SDDM unthemed: './install.sh install --no-greeter' themes it"
    else
        warn "could not enable sddm either"
        note "no login screen enabled: log in on a console and run 'sudo systemctl enable sddm'"
    fi
}

stage_greeter() {
    (( WANT_GREETER )) || return 0
    step "Login screen: the SimplyChit greeter"

    # wlr-randr: the greeter switches off every monitor but the primary one
    if (( DO_PACKAGES )); then
        pac_install "greetd and cage" greetd cage wlr-randr || {
            warn "could not install greetd and cage — greeter skipped"
            greeter_fallback
            return 0
        }
    elif ! pacman -Qq greetd cage &>/dev/null; then
        skip "greetd and cage not installed (--skip-packages) — greeter skipped"
        greeter_fallback
        return 0
    fi
    if greeter_copy_files; then
        ok "greeter files in $GREETER_DIR, palette and wallpaper copied"
    else
        warn "could not set up the greeter's files — greeter skipped"
        greeter_fallback
        return 0
    fi

    local body current
    body="# Written by SimplyChit install.sh (--greeter). The original, if there was
# one, is config.toml.simplychit-orig next to this file.
[terminal]
vt = 1

[default_session]
command = \"env HOME=$GREETER_HOME QT_WAYLAND_DISABLE_WINDOWDECORATION=1 cage -s -d -- qs -p $GREETER_DIR/greeter.qml\"
user = \"greeter\""
    if [[ -f "$GREETD_CONF" ]] && [[ "$("${SUDO[@]}" cat "$GREETD_CONF")" == "$body" ]]; then
        skip "$GREETD_CONF already correct"
    elif review_confirm "$GREETD_CONF" "$body" "Write it? (needs root)"; then
        if [[ -f "$GREETD_CONF" && ! -e "$GREETD_CONF.simplychit-orig" ]]; then
            "${SUDO[@]}" cp -- "$GREETD_CONF" "$GREETD_CONF.simplychit-orig"
        fi
        "${SUDO[@]}" mkdir -p "$(dirname "$GREETD_CONF")"
        printf '%s\n' "$body" | "${SUDO[@]}" tee "$GREETD_CONF" >/dev/null
        ok "wrote $GREETD_CONF"
    else
        skip "greetd config left alone — greeter not switched on"
        greeter_fallback
        return 0
    fi
    note "preview the greeter any time: qs -p ~/.config/quickshell/simplychit/greeter.qml (Esc closes it)"

    if systemctl is-enabled greetd.service &>/dev/null; then
        skip "greetd is already the login screen"
        DM_LABEL="SimplyChit"
        return 0
    fi
    # after stage_services, so this is whatever it left enabled
    current="$(basename -- "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service)"
    [[ "$current" == . || "$current" == display-manager ]] && current=""
    # Replacing someone else's login screen is their call; no login screen or
    # SDDM (what SimplyChit used to set up) is ours to replace.
    local default=y
    [[ -n "$current" && "$current" != sddm ]] && default=n
    if interactive confirm "Switch the login screen to the SimplyChit greeter?

If it fails, the next boot has no login screen, only a text console (Ctrl+Alt+F2). ${current:-SDDM} stays installed and is only disabled. To go back, from that console:

  sudo systemctl disable greetd && sudo systemctl enable ${current:-sddm} && sudo reboot" "$default"; then
        if [[ -n "$current" ]]; then
            run_logged "Disabling $current" "${SUDO[@]}" systemctl disable "$current.service" || {
                warn "could not disable $current — greetd not enabled"
                return 0
            }
        fi
        if run_logged "Enabling greetd" "${SUDO[@]}" systemctl enable greetd.service; then
            ok "greetd is the login screen from the next boot"
            DM_LABEL="SimplyChit"
            note "greeter on from the next boot. Back: sudo systemctl disable greetd && sudo systemctl enable ${current:-sddm}"
        else
            warn "could not enable greetd"
            [[ -n "$current" ]] && "${SUDO[@]}" systemctl enable "$current.service" &>/dev/null
            greeter_fallback
        fi
    else
        skip "login screen unchanged"
        [[ -n "$current" ]] && DM_LABEL="${current/#sddm/SDDM}"
        note "greeter set up, not switched on: sudo systemctl disable ${current:-sddm} && sudo systemctl enable greetd"
        greeter_fallback
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
    # hyprlock.conf names $WALLPAPER_POINTER rather than a picture, and the
    # shell starts from it, so no tracked file has to be edited per machine — or
    # per wallpaper. This symlink is the machine's actual choice, and the picker
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
#   Hyprland   ~/.config/simplychit/hypr/*.lua, loaded after the defaults
#   uwsm       env-hyprland.d/, sourced after env-hyprland  (gitignored)
#   wallpaper  ~/.local/state/simplychit/wallpaper, a symlink hyprlock's tracked
#              config points at and the shell starts from
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
        warn "no monitors detected — write ~/.config/simplychit/hypr/monitor.lua after first login"
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
-- Loaded after config/monitor.lua, so these win. Yours: not tracked, never
-- rewritten by install.sh or updates — edit freely.
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

    mkdir -p "$USER_DIR/hypr"
    local mon_file="$USER_DIR/hypr/monitor.lua"
    # Machines set up before the move have it in config/custom/, which is still
    # loaded. Writing a second layout here would override theirs.
    local legacy_mon="$HOME/.config/hypr/config/custom/monitor.lua"

    if [[ -s "$mon_file" ]]; then
        skip "$mon_file already exists — left alone"
    elif [[ -s "$legacy_mon" ]]; then
        skip "$legacy_mon already exists (old location, still loaded) — left alone"
    elif interactive review_confirm "$mon_file" "$mon_body"; then
        printf '%s\n' "$mon_body" > "$mon_file"
        ok "wrote $mon_file"
        # A broken override is reported rather than fatal, but catching it here
        # is cheaper than reading ~/.cache/hypr-custom.log later.
        if command -v luac >/dev/null; then
            luac -p "$mon_file" && ok "syntax checks out" \
                || warn "generated Lua does not parse — check it before logging in"
        fi
        note "review ~/.config/simplychit/hypr/monitor.lua — positions are a guess"
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
# flag the wallpaper picker uses (quickshell/simplychit/services/Theme.qml) — a run without it
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
        [[ -f "$HOME/.cache/wal/colors-gtk.css" ]] \
            || warn "colors-gtk.css missing — is .config/wal/templates/ stowed?"
    fi
    stage_app_theming
}

# ── apps that keep their own copy of the palette ────────────────────────────
#
# pywal16 renders into ~/.cache/wal/; GTK, hyprlock, btop and the browser cannot
# read from there, and `simplychit sync-palette` makes their copies (the shell
# runs it after every wallpaper change; see the command for the why of each).
# All of them are outside the repo, so none of this shows up in `git status`.
#
# Run on install and on update. Even with no palette yet it writes hyprlock's
# colour file, with defaults, so the file hyprlock.conf sources always exists.
# The rest is one-time setup for apps that need to be pointed at the palette.

stage_app_theming() {
    step "Apps themed from the wallpaper"
    # Before sync-palette, which writes the theme into the installed extension.
    stage_vscode_theme
    local copies
    if copies="$("$REPO_ROOT/home/.local/bin/simplychit" sync-palette 2>&1)"; then
        ok "palette copied to $(grep -c . <<<"$copies") place(s)"
    else
        # the rest were still copied; this names the ones that were not
        warn "some palette copies failed:"
        say "$(grep '^not copied' <<<"$copies" || printf '%s' "$copies")"
    fi

    # btop reads color_theme from btop.conf and writes the rest of its settings
    # there itself; only seeded, never edited once it exists.
    if command -v btop >/dev/null && [[ ! -e "$HOME/.config/btop/btop.conf" ]]; then
        mkdir -p "$HOME/.config/btop"
        printf 'color_theme = "simplychit"\ntheme_background = False\n' > "$HOME/.config/btop/btop.conf"
        ok "btop set to the wallpaper theme"
    fi

    # The browser: pywalfox's native host, which its add-on talks to.
    if command -v pywalfox >/dev/null; then
        if run_logged "pywalfox" pywalfox install; then
            ok "pywalfox ready"
            note "browser: add the Pywalfox add-on (addons.mozilla.org) for wallpaper colours"
        else
            warn "pywalfox install failed"
        fi
    fi
}

# ── VS Code ─────────────────────────────────────────────────────────────────
#
# The SimplyChit theme (vscode-theme/), not dlasagno.wal-theme: that one maps the
# dark half of the --cols16 dual palette onto keywords and constants, about
# 1.5:1 on a dim wallpaper. `simplychit vscode-theme --vsix` packs ours with the
# current palette, and sync-palette rewrites it on every wallpaper change; VS
# Code reloads the active theme when its file changes.
#
# A user who picked "Wal" is moved to SimplyChit, which replaces it; any other
# theme is their choice and stays.

stage_vscode_theme() {
    local code settings version vsix
    version="$(awk -F'"' '/"version"/{print $4; exit}' "$REPO_ROOT/vscode-theme/package.json")"
    for code in code codium; do
        command -v "$code" >/dev/null || continue
        if "$code" --list-extensions --show-versions 2>/dev/null \
            | grep -qix "simplychit.simplychit-theme@$version"; then
            skip "$code: SimplyChit theme $version already installed"
        else
            vsix="$(mktemp --suffix=.vsix)"
            if "$REPO_ROOT/home/.local/bin/simplychit" vscode-theme --vsix "$vsix" &&
                run_logged "VS Code theme" "$code" --install-extension "$vsix" --force; then
                ok "$code: SimplyChit theme installed"
            else
                warn "$code: could not install the SimplyChit theme"
            fi
            rm -f "$vsix"
        fi

        case "$code" in
            code)   settings="$HOME/.config/Code/User/settings.json" ;;
            codium) settings="$HOME/.config/VSCodium/User/settings.json" ;;
        esac
        if [[ -f "$settings" ]] &&
            grep -qE '"workbench\.colorTheme": *"Wal( Bordered)?"' "$settings"; then
            sed -i -E 's/("workbench\.colorTheme": *)"Wal( Bordered)?"/\1"SimplyChit"/' "$settings" \
                && ok "$code: colour theme Wal -> SimplyChit"
        elif ! grep -q '"workbench\.colorTheme"' "$settings" 2>/dev/null; then
            note "VS Code: pick the colour theme \"SimplyChit\" (Ctrl+K Ctrl+T) to follow the wallpaper"
        fi
    done
}

# ── the vendored libadwaita stylesheet ──────────────────────────────────────
#
# GTK 4 loads exactly one theme stylesheet, so .themes/simplychit/gtk-4.0/ cannot
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

    local dir="$HOME/.themes/simplychit/gtk-4.0"
    local lib="/usr/lib/libadwaita-1.so.0"
    local res="/org/gnome/Adwaita/styles"

    if [[ ! -d "$dir" ]]; then
        skip "$dir missing — was stow run?"
        return 0
    fi

    # The recolour has to sit *beside* .config/gtk-4.0/gtk.css rather than be
    # imported across from ~/.themes. A flatpak mounts that directory inside its
    # own per-app home, so a relative "../.." climbs to ~/.var/app/<app-id>/ and
    # the import fails with nothing but a warning on stderr — the sheet then
    # loads with no colours at all, and every flatpak sits on Adwaita blue while
    # the host looks perfectly fine. Copying it in keeps both resolving locally.
    #
    # Before the refresh below, not after it: a fresh Arch has neither gresource
    # nor libadwaita, the refresh returns early there, and every host GTK 4 app
    # stayed on Adwaita blue. overrides.css is tracked, the refresh never
    # touches it, so the order costs nothing.
    local cfg="$HOME/.config/gtk-4.0"
    if [[ -d "$cfg" && -f "$dir/overrides.css" ]]; then
        cp "$dir/overrides.css" "$cfg/overrides.css"
        chmod 644 "$cfg/overrides.css"
        ok "recolour copied into .config/gtk-4.0/"
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
        # The sheet names its assets by relative path, so they travel with it.
        # Take whatever the library ships rather than a fixed list: libadwaita
        # 1.10 renamed check-symbolic.svg to check.svg (and devel to
        # devel-stripes). Through a temp file again, so a failed extract never
        # leaves an empty asset behind.
        while IFS= read -r asset; do
            tmp="$(mktemp)"
            if gresource extract "$lib" "$asset" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
                mv "$tmp" "$dir/assets/${asset##*/}"
                chmod 644 "$dir/assets/${asset##*/}"
            else
                rm -f "$tmp"
            fi
        done < <(gresource list "$lib" 2>/dev/null | grep "^$res/assets/")
        ok "refreshed from $(pacman -Q libadwaita 2>/dev/null || echo libadwaita)"
        note "edited tracked file .themes/simplychit/gtk-4.0/adw-base.css (libadwaita)"
    else
        rm -f "$tmp"
        warn "could not read $res/gtk.css — keeping the vendored copy"
    fi
}

# ── flatpaks ────────────────────────────────────────────────────────────────
#
# A flatpak sees none of the theme unless it is let in: ~/.themes for the theme
# GTK_THEME names (GTK 3, and GTK 4 apps that take a theme), the two GTK config
# folders for settings.ini and the user CSS libadwaita apps load. All read-only.
# A per-user override for every app, so a flatpak installed later is themed too.
# Re-applying it each run also replaces a GTK_THEME left from before a rename.

stage_flatpak_theming() {
    step "Flatpak theming"
    if ! command -v flatpak >/dev/null; then
        skip "flatpak not installed"
        return 0
    fi
    local theme
    theme="$(awk -F= '/^gtk-theme-name=/{print $2}' \
        "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null)"
    if run_logged "flatpak override" flatpak override --user \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=~/.themes:ro \
        --env=GTK_THEME="${theme:-simplychit}"; then
        ok "flatpaks can read the GTK theme (GTK_THEME=${theme:-simplychit})"
    else
        warn "could not set the flatpak override"
        note "run by hand: flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=~/.themes:ro --env=GTK_THEME=simplychit"
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
    local other
    # Another login screen or network manager is only switched off when the
    # user said yes in detect_system; both changes take effect at the next boot.
    if (( WANT_SDDM )) && [[ -n "$DM_CURRENT" && "$DM_CURRENT" != sddm ]]; then
        if run_logged "Disabling $DM_CURRENT" "${SUDO[@]}" systemctl disable "$DM_CURRENT.service"; then
            ok "$DM_CURRENT disabled (still installed)"
            note "login screen: SDDM from the next boot. Back to $DM_CURRENT: sudo systemctl disable sddm && sudo systemctl enable $DM_CURRENT"
        else
            warn "could not disable $DM_CURRENT; SDDM stays off"
            WANT_SDDM=0
        fi
    fi
    if (( WANT_NM )) && (( ${#NET_OTHER[@]} )); then
        for other in "${NET_OTHER[@]}"; do
            run_logged "Disabling $other" "${SUDO[@]}" systemctl disable "$other.service" \
                && ok "$other disabled (still installed)"
        done
        note "networking: NetworkManager from the next boot. Back: sudo systemctl disable NetworkManager && sudo systemctl enable ${NET_OTHER[*]}"
    fi

    for svc in NetworkManager bluetooth sddm power-profiles-daemon; do
        [[ "$svc" == sddm ]] && (( ! WANT_SDDM )) && continue
        [[ "$svc" == NetworkManager ]] && (( ! WANT_NM )) && continue
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

    stage_shell_services
}

# What the shell needs from systemd. Install and update both run it: an
# install from before the Quickshell shell still has hyprpolkitagent enabled.
stage_shell_services() {
    # The shell is the polkit agent now. Only one agent can register per
    # session, and an enabled hyprpolkitagent unit starts first and wins, so it
    # is switched off here; autorun.lua starts it only if the shell's agent has
    # not registered (shell down or broken).
    if systemctl --user is-enabled hyprpolkitagent.service &>/dev/null; then
        if run_logged "Disabling hyprpolkitagent (now the fallback)" systemctl --user disable hyprpolkitagent.service; then
            ok "hyprpolkitagent is the fallback agent now"
        else
            warn "could not disable hyprpolkitagent"
            note "the shell's polkit dialog will not show while it runs: systemctl --user disable hyprpolkitagent.service"
        fi
    fi

    # Power profiles in the control centre need the power-profiles D-Bus
    # service. TLP conflicts with power-profiles-daemon but ships tlp-pd, which
    # provides the same interface.
    if command -v tlp >/dev/null && systemctl list-unit-files tlp-pd.service &>/dev/null \
        && ! systemctl is-enabled tlp-pd.service &>/dev/null; then
        if confirm "Enable tlp-pd?

TLP is installed. tlp-pd lets the control centre switch power profiles (saver, balanced, performance) through TLP." y; then
            if run_logged "Enabling tlp-pd" "${SUDO[@]}" systemctl enable --now tlp-pd.service; then
                ok "tlp-pd enabled"
            else
                warn "could not enable tlp-pd"
                note "enable it by hand: sudo systemctl enable --now tlp-pd"
            fi
        fi
    fi
}

# ── restarting the running shell ────────────────────────────────────────────
#
# Only meaningful during an update, and only when a session is up. Same as
# hypr/config/helpers/shell.lua's restart: stop the instance, start a new one
# under the watchdog (hypr/Scripts/shell-watchdog.sh), detached with setsid so
# it does not die with this script.

start_shell() {
    setsid -f sh "$HOME/.config/hypr/Scripts/shell-watchdog.sh" >/dev/null 2>&1 </dev/null || true
}

shell_is_running() {
    qs list -c simplychit 2>/dev/null | grep -q '^Instance'
}

restart_shell() {
    step "Restarting the shell"
    if (( OLD_SHELL_RUNNING )); then
        # renamed: the old instance goes, the new one starts, no question
        qs kill -c archdots >/dev/null 2>&1 || true
        start_shell
        sleep 3
        if shell_is_running; then
            ok "the shell restarted under its new name (qs -c simplychit)"
        else
            warn "the shell did not come back"
            note "restart it with SUPER + SHIFT + CTRL + ALT + R, or log out and back in"
        fi
        return 0
    fi
    if ! shell_is_running; then
        skip "not running — it starts itself at your next login"
        return 0
    fi
    if ! interactive confirm "Restart the running shell now?

The bar and the panels disappear for a second while it comes back. Skip this if you are in the middle of something — SUPER + SHIFT + CTRL + ALT + R does the same later." y; then
        skip "left running the old code"
        note "restart the shell with SUPER + SHIFT + CTRL + ALT + R, or log out and back in"
        return 0
    fi
    qs kill -c simplychit >/dev/null 2>&1 || true
    start_shell
    sleep 3
    if shell_is_running; then
        ok "restarted"
    else
        warn "the shell did not come back"
        note "restart it by hand with SUPER + SHIFT + CTRL + ALT + R, or log out and back in"
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

    # The machine-specific values and the pywal16 output live outside the repo
    # (or in gitignored files) now, but an installed clone can still be dirty
    # for reasons the user did not choose. Stash
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
                -m "SimplyChit update $(date '+%Y-%m-%d %H:%M')" >/dev/null
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
    replace_pulse
    pac_install "Core packages and fonts" "${PKG_CORE[@]}" "${PKG_FONTS[@]}"
    ok "core and fonts up to date"

    if (( WANT_UTILS )); then
        pac_install "Utilities" "${PKG_UTILS[@]}" && ok "utilities up to date"
    fi

    # PKG_AUR_CORE carries the theming engine, so it is refreshed whether or not
    # the optional AUR list is wanted — the same reason it is mandatory above.
    if [[ -n "$AUR_HELPER" ]]; then
        run_logged "Theming engine" "$AUR_HELPER" -S --needed --noconfirm "${PKG_AUR_CORE[@]}" \
            && ok "theming engine up to date" \
            || warn "python-pywal16 could not be updated — continuing"
    else
        skip "no AUR helper — python-pywal16 left alone"
    fi

    if (( WANT_AUR )) && [[ -n "$AUR_HELPER" ]]; then
        phase 45 60 "AUR packages"
        step "AUR packages"
        run_logged "AUR packages" "$AUR_HELPER" -S --needed --noconfirm "${PKG_AUR[@]}" || {
            warn "one or more AUR builds failed — continuing"
            note "some AUR packages failed to build; retry: $AUR_HELPER -S ${PKG_AUR[*]}"
        }
        ok "done"
    elif (( WANT_AUR )); then
        skip "no AUR helper — AUR packages left alone"
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

# Browsers ask to stay awake at org.freedesktop.ScreenSaver. hypridle used to
# take that name and ignore it; its config now leaves it alone, and the stowed
# D-Bus service file starts `simplychit inhibitors` there. A running session
# needs the bus to see the new file and hypridle to restart without the name.
refresh_idle_requests() {
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 0
    step "Stay-awake requests from apps"
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
        ReloadConfig >/dev/null 2>&1 || true
    if pgrep -x hypridle >/dev/null; then
        pkill -x hypridle
        setsid -f hypridle >/dev/null 2>&1 </dev/null || true
    fi
    setsid -f "$HOME/.local/bin/simplychit" inhibitors >/dev/null 2>&1 </dev/null || true
    ok "videos in browsers now keep the screen awake"
}

run_update() {
    # Before the gauge, always: the password box is ours to draw, and after this
    # point sudo asks through the askpass helper instead of the terminal.
    sudo_askpass_setup
    sudo_authenticate

    gauge_open "Updating SimplyChit"

    local self_before
    self_before="$(sha256sum "$REPO_ROOT/install.sh" 2>/dev/null)"
    update_repo
    # The pull may have changed this script. bash is still running the old copy,
    # whose stages can be wrong for the new tree (the move to home/ is exactly
    # that case), so start again on the new one. SIMPLYCHIT_UPDATE_REEXEC stops a
    # loop (SIMPLYCHIT_REEXEC is the curl handover's, a different hop).
    if [[ -z "${SIMPLYCHIT_UPDATE_REEXEC:-}" ]] &&
        [[ "$(sha256sum "$REPO_ROOT/install.sh" 2>/dev/null)" != "$self_before" ]]; then
        say "install.sh changed in the pull — continuing with the new version"
        cleanup
        # --update too, in case this run's mode came from the menu, not the args
        SIMPLYCHIT_UPDATE_REEXEC=1 exec bash "$REPO_ROOT/install.sh" \
            ${ARGS_ORIGINAL+"${ARGS_ORIGINAL[@]}"} --update
    fi
    update_packages
    stage_stow          # picks up whatever the update added, moved or renamed
    stage_user_dir      # creates any user stub a newer version added
    retire_fabric       # leftovers of the shell before Quickshell, once
    retire_old_name     # archdots -> SimplyChit, once
    stage_wallpapers    # copies any new wallpapers into ~/Pictures/wallpapers
    stage_gtk4_base     # update_packages may have moved libadwaita under us
    stage_flatpak_theming
    stage_app_theming   # palette copies (hyprlock's file), apps the update added
    stage_shell_services  # hyprpolkitagent off (the shell is the agent), tlp-pd
    refresh_idle_requests # browsers' stay-awake requests reach the shell
    if [[ -d "$GREETER_DIR" ]]; then
        step "The greeter"
        # wlr-randr arrived with the primary-screen-only login; older greeters lack it
        pac_install "wlr-randr" wlr-randr || warn "no wlr-randr: the login screen will span every monitor"
        greeter_copy_files && ok "greeter refreshed (shell, palette, wallpaper)"
    fi
    # an existing install: no first-run welcome after this update (the
    # launcher's > Welcome still opens it)
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/simplychit" &&
        touch "${XDG_STATE_HOME:-$HOME/.local/state}/simplychit/welcomed"
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

    gauge_open "Installing SimplyChit"

    stage_packages
    (( DO_PACKAGES )) && install_sddm_theme
    stage_stow
    stage_user_dir
    stage_zsh
    retire_fabric
    retire_old_name
    phase 96 97 "Wallpapers"
    stage_wallpapers
    phase 97 98 "This machine's hardware"
    stage_machine
    phase 98 99 "Theming"
    stage_gtk4_base
    stage_flatpak_theming
    stage_theming
    stage_dconf
    phase 99 100 "Services"
    stage_services
    stage_greeter
    gauge_close

    step "Done"
    say "Log out and pick Hyprland at the ${DM_LABEL:-SDDM} login screen. The desktop starts itself."
    say "Press SUPER + / once you are in for the keybind cheatsheet."

    if (( ${#SUMMARY[@]} )); then
        printf '\n    %sWorth knowing:%s\n' "$B" "$R"
        printf '      • %s\n' "${SUMMARY[@]}"
    fi

    cat <<EOF

    ${B}What this machine got, and where it lives${R}
    None of it is in a tracked file, so \`git status\` stays clean and none of
    it can follow you onto another machine.
      monitors, input, autorun   ~/.config/simplychit/hypr/*.lua
      GPU order                  ~/.config/uwsm/env-hyprland.d/10-gpu.sh
      wallpaper                  $WALLPAPER_POINTER
    Anything else you want different goes in ~/.config/simplychit/ too — it is
    loaded after the defaults, so whatever it sets wins, and updates never
    touch it. See CUSTOMIZING.md.

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

$KEYS_LIST" 22 76 9 \
        packages "Install packages"                        "$(on_off $DO_PACKAGES)" \
        utils    "  the utility packages"                  "$(on_off $WANT_UTILS)" \
        apps     "  the applications (VLC, OBS, ...)"      "$(on_off $WANT_APPS)" \
        aur      "  paru and the AUR packages"             "$(on_off $WANT_AUR)" \
        flatpak  "  the flatpak applications"              "$(on_off $WANT_FLATPAK)" \
        stow     "Link the dotfiles into \$HOME"           "$(on_off $DO_STOW)" \
        machine  "Machine config: GPU, monitors, wallpaper" "$(on_off $DO_MACHINE)" \
        greeter  "Login screen: the greeter (off: SDDM)"   "$(on_off $WANT_GREETER)")" \
        || { say "cancelled"; exit 0; }

    # The tags are the same switches --help documents, so this checklist cannot
    # ask for anything the flags cannot. whiptail returns them quoted, space
    # separated.
    DO_PACKAGES=0; DO_STOW=0; DO_MACHINE=0
    WANT_UTILS=0; WANT_APPS=0; WANT_AUR=0; WANT_FLATPAK=0; WANT_GREETER=0
    for tag in ${sel//\"/}; do
        case "$tag" in
            packages) DO_PACKAGES=1 ;;
            utils)    WANT_UTILS=1 ;;
            apps)     WANT_APPS=1 ;;
            aur)      WANT_AUR=1 ;;
            flatpak)  WANT_FLATPAK=1 ;;
            stow)     DO_STOW=1 ;;
            machine)  DO_MACHINE=1 ;;
            greeter)  WANT_GREETER=1 ;;
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
    MODE="$(wt --title "SimplyChit" --default-item "$default" --menu \
        "Arch + Hyprland desktop.

Whatever you pick runs on its own from here. The output goes to
a log file and this screen keeps a progress bar instead; run it
with --no-gui to be asked about each step and watch it work.

$KEYS_MENU" 20 76 4 \
        install "Install: packages, dotfiles, shell, machine config" \
        update  "Update: pull, re-link, refresh packages, restart the shell" \
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
detect_system

case "$MODE" in
    update) run_update ;;
    *)      run_install ;;
esac
