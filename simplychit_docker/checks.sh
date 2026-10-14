#!/usr/bin/env bash
#
# Runs INSIDE the test container. Mounted at /checks.sh by runscript.sh.
#
# Copies the read-only repo mount to a writable path, runs install.sh with
# whatever arguments were passed through, then verifies the result: that stow
# linked what it should, that Hyprland can parse the config, and — with
# SIMPLYCHIT_HYPR=1 — that the compositor and shell actually come up.
#
# Kept as a file rather than inlined into `docker run bash -c '...'` because
# these checks need both quote characters, and nesting them inside one shell
# string silently truncates the script.

set -uo pipefail

REPO=/home/tester/simplychit

# ── stage the repo ──────────────────────────────────────────────────────────

cp -a /src "$REPO"
cd "$REPO" || exit 1

# A fresh clone has none of these. Without stripping them the test inherits the
# host's machine-specific files and reports "monitor.lua already exists", which
# is the opposite of what a new machine sees.
rm -f  home/.config/hypr/config/custom/*.lua
rm -rf .omc home/.config/hypr/.omc

# Files flagged assume-unchanged (`git ls-files -v` prints those lowercase) are
# local-only by definition: git is told to ignore whatever the working tree
# says, so a clone gets the committed version instead. .zsh_custom is one of
# them — empty in the repo, full of personal aliases on the author's machine —
# and copying the working-tree version made the container's login shell throw
# errors no real install would ever produce. Restore what a clone would get.
if [ -d .git ]; then
    git ls-files -v | awk '/^[a-z]/ {print $2}' | while read -r f; do
        git update-index --no-assume-unchanged "$f" 2>/dev/null
        git checkout HEAD -- "$f" 2>/dev/null \
            && echo "==> [harness] reset local-only $f to its committed state"
    done
fi

# --skip-packages means install.sh installs nothing, so the stages after it have
# nothing to work with. Give them the bare minimum here rather than baking it
# into the image, which would stop --full testing it.
if [ "${SIMPLYCHIT_FAST:-}" = 1 ]; then
    echo "==> [harness] preinstalling stow/python/zsh for the structural run"
    sudo pacman -Sy --noconfirm --needed stow python zsh curl >/dev/null
fi

if [ "$#" -eq 0 ]; then
    echo "repo at $REPO — run ./install.sh yourself"
    exec bash
fi

./install.sh "$@"
install_rc=$?

# ── did stow link what it should? ───────────────────────────────────────────

# stow folds: ~/.config/hypr and friends are each ONE symlink into the repo's
# home/, so paths beneath them are the repo files themselves. Test that they
# resolve there, not that each leaf is individually a link.
resolves() {
    case "$(readlink -f "$1" 2>/dev/null)" in
        "$REPO"/home/*) echo "ok" ;;
        "")        echo "MISSING" ;;
        *)         echo "NOT IN REPO: $(readlink -f "$1")" ;;
    esac
}

echo
echo "===================== post-run checks ====================="
echo "  install.sh exit code:          $install_rc"
printf "  %-30s %s\n" ".zshrc -> repo:"        "$(resolves "$HOME/.zshrc")"
printf "  %-30s %s\n" "hypr config -> repo:"   "$(resolves "$HOME/.config/hypr/config/keybind.lua")"
printf "  %-30s %s\n" "quickshell -> repo:"    "$(resolves "$HOME/.config/quickshell/simplychit/shell.qml")"
printf "  %-30s %s\n" "install.sh NOT stowed:" "$([ -e "$HOME/install.sh" ] && echo LEAKED || echo ok)"
printf "  %-30s %s\n" "repo-only NOT stowed:"  "$(for f in home kvantum .themes_sddm README.md simplychit_docker; do [ -e "$HOME/$f" ] && printf 'LEAKED:%s ' "$f"; done; echo ok)"
printf "  %-30s %s\n" "wallpapers NOT stowed:" "$([ -e "$HOME/wallpapers" ] && echo LEAKED || echo ok)"
printf "  %-30s %s\n" "wallpapers in Pictures:" "$(ls "$HOME/Pictures/wallpapers" 2>/dev/null | tr '\n' ' ')"
printf "  %-30s %s\n" "oh-my-zsh:"             "$([ -d "$HOME/.oh-my-zsh" ] && echo yes || echo NO)"
printf "  %-30s %s\n" "zsh plugins (pacman):"  "$([ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && [ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && echo yes || echo MISSING)"
printf "  %-30s %s\n" "user folder files:"     "$(cd "$HOME/.config/simplychit" 2>/dev/null && find . -type f | sort | tr '\n' ' ' || echo MISSING)"
printf "  %-30s %s\n" "user folder in repo:"   "$([ -e "$REPO/.config/simplychit" ] && echo LEAKED || echo ok)"
printf "  %-30s %s\n" "no fabric_shell left:"  "$([ -e "$HOME/.config/fabric_shell" ] && echo LEFT || echo ok)"
printf "  %-30s %s\n" "settings schema current:" "$(python3 "$REPO/tools/gen-settings-schema.py" --check 2>&1 && echo ok)"
printf "  %-30s %s\n" "simplychit check-settings:" "$("$HOME/.local/bin/simplychit" check-settings 2>&1 | head -1)"
echo "  repo dirtied by machine config:"
git -C "$REPO" status --short 2>/dev/null | sed 's/^/    /' | head -8
echo "==========================================================="

command -v Hyprland >/dev/null || exit $install_rc

# ── can Hyprland even parse the config? ─────────────────────────────────────

echo
echo "================= hyprland config check ==================="
# No compositor and no display needed: this parses hyprland.lua and every
# config/*.lua it requires. That failure would otherwise only surface as a dead
# session at the login screen.
verify_out="$(Hyprland --verify-config 2>&1)"
echo "$verify_out" | grep -vE '^\[|^$' | tail -6 | sed 's/^/  /'
if echo "$verify_out" | grep -q "config ok"; then
    echo "  RESULT: config ok"
else
    echo "  RESULT: CONFIG ERRORS (above)"
fi
echo "==========================================================="

[ "${SIMPLYCHIT_HYPR:-}" = 1 ] || exit $install_rc

# ── actually run it ─────────────────────────────────────────────────────────

echo
echo "=============== nested hyprland session ==================="
export XDG_RUNTIME_DIR=/run/user/1000

# The host compositor consumes every SUPER combination before the nested one
# sees it, so the real binds are unreachable from inside. This makes Caps an
# additional Super *inside the container*, so every real bind works when pressed
# with Caps. ~/.config/simplychit/hypr/input.lua is loaded after the defaults.
# Applied to every nested run, not just --ui: the host swallows SUPER in
# both cases, and a non-interactive run should verify the same setup.
if [ "${SIMPLYCHIT_HYPR:-}" = 1 ] && [ -r /ui-input.lua ]; then
    mkdir -p "$HOME/.config/simplychit/hypr"
    cp /ui-input.lua "$HOME/.config/simplychit/hypr/input.lua"
    echo "  Caps mapped to Super for the nested session"
fi

# Hyprland's nested Wayland backend hands its output a scale of 2, so every CSS
# pixel renders as two and the whole shell comes out twice the size it is on a
# real machine — which reads as a theming bug rather than a scaling one.
# install.sh only writes rules for the monitors it detected in /sys (the host's),
# and WAYLAND-1 is not among them, so pin it here. Later rules win.
mkdir -p "$HOME/.config/simplychit/hypr"
cat >> "$HOME/.config/simplychit/hypr/monitor.lua" <<'MON'

-- Added by the test harness: the nested output, at 1:1 so the shell renders at
-- the same size it would on real hardware.
hl.monitor({ output = "WAYLAND-1", mode = "preferred", position = "0x0", scale = 1.0 })
MON

palette() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["special"]["background"], d["colors"]["color4"])' \
        "$HOME/.cache/wal/colors.json" 2>/dev/null || echo unknown
}
echo "  palette in use: $(palette)"

# dbus-run-session: the shell claims org.freedesktop.Notifications, and a
# container has no session bus otherwise.
dbus-run-session -- Hyprland > /tmp/hypr.log 2>&1 &
hyprpid=$!

echo "  waiting for the compositor..."
# hyprctl does NOT discover a running instance on its own — without
# HYPRLAND_INSTANCE_SIGNATURE it just prints "is hyprland running?" and exits 0.
# Hyprland only exports it to its own children, so a sibling process like this
# one has to read the signature back out of the runtime dir.
for _ in $(seq 40); do
    his="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
    if [ -n "$his" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$his"
        hyprctl monitors >/dev/null 2>&1 && break
    fi
    kill -0 "$hyprpid" 2>/dev/null || break
    sleep 1
done

if ! hyprctl monitors >/dev/null 2>&1; then
    echo "  COMPOSITOR DID NOT REACH A QUERYABLE STATE"
    printf "  %-30s %s\n" "process alive:" "$(kill -0 "$hyprpid" 2>/dev/null && echo yes || echo no)"
    printf "  %-30s %s\n" "instance dir:" "$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | tr '\n' ' ' || echo 'none created')"
    printf "  %-30s %s\n" "sockets:" "$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep wayland | tr '\n' ' ')"
    tail -30 /tmp/hypr.log | sed 's/^/    /'
    cp /tmp/hypr.log /artifacts/hypr.log 2>/dev/null
    exit 1
fi
echo "  compositor up (instance ${HYPRLAND_INSTANCE_SIGNATURE:0:12}...)"

printf "  %-30s " "monitors:"
hyprctl monitors -j | python3 -c 'import json,sys
m=json.load(sys.stdin)
print(", ".join("%s %sx%s scale=%s" % (x["name"],x["width"],x["height"],x["scale"]) for x in m) or "none")'
printf "  %-30s %s\n" "kb_options (Caps->Super):" \
    "$(hyprctl getoption input:kb_options 2>/dev/null | awk '/^str:/{print $2}')"
printf "  %-30s " "keybinds registered:"
hyprctl binds -j | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
printf "  %-30s " "binds with no desc:"
hyprctl binds -j | python3 -c 'import json,sys; print(sum(1 for b in json.load(sys.stdin) if not b.get("description")))'

echo "  waiting for the shell..."
for _ in $(seq 30); do
    pgrep -f "qs -c simplychit" >/dev/null 2>&1 && break
    sleep 1
done
qspid="$(pgrep -f 'qs -c simplychit' | head -1)"
printf "  %-30s %s\n" "shell (qs -c simplychit):" "$([ -n "$qspid" ] && echo "running, pid $qspid" || echo 'NOT RUNNING')"
# its own log, for anything QML refused to load
qs log -c simplychit 2>/dev/null | grep -E 'ERROR|WARN' | grep -vE 'textinput|PowerProfiles' | head -8 | sed 's/^/    log: /'

printf "  %-30s %s\n" "bar layer geometry:" "$(hyprctl layers -j | python3 -c 'import json,sys
d=json.load(sys.stdin)
for mon in d.values():
    for lvl in mon["levels"].values():
        for l in lvl:
            if l.get("namespace") == "simplychit-bar":
                print("%sx%s at %s,%s" % (l["w"], l["h"], l["x"], l["y"]))' 2>/dev/null | head -2 | tr '\n' ' ')"
printf "  %-30s %s\n" "shell layer surfaces:" "$(hyprctl layers 2>/dev/null | grep -o 'simplychit-[a-z-]*' | sort -u | tr '\n' ' ')"
# The session bus belongs to the dbus-run-session that Hyprland runs inside;
# this script is outside it, so it borrows that bus address from the shell's
# own environment. The name is claimed asynchronously, so retry a while.
if [ -n "$qspid" ] && [ -r "/proc/$qspid/environ" ]; then
    bus="$(tr '\0' '\n' < "/proc/$qspid/environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)"
    owner=""
    for _ in $(seq 15); do
        owner="$(DBUS_SESSION_BUS_ADDRESS="$bus" busctl --user status org.freedesktop.Notifications 2>/dev/null | awk -F= '/^PID=/{print $2}')"
        [ -n "$owner" ] && break
        sleep 1
    done
    if [ -n "$owner" ]; then
        printf "  %-30s %s\n" "notification bus owner:" "pid $owner$([ "$owner" = "$qspid" ] && echo ' (= the shell, correct)')"
    else
        printf "  %-30s %s\n" "notification bus owner:" "UNCLAIMED"
    fi
else
    printf "  %-30s %s\n" "notification bus owner:" "n/a (no shell to read the bus from)"
fi

# The nested compositor opened its own socket beside the host one we mounted in
# as wayland-host; grim has to be pointed at that, not at the host's.
sleep 3
nested="$(ls /run/user/1000 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)"
printf "  %-30s %s\n" "nested wayland socket:" "${nested:-none found}"
if [ -n "$nested" ] && command -v grim >/dev/null; then
    if WAYLAND_DISPLAY="$nested" grim /artifacts/hyprland.png 2>/tmp/grim.err; then
        printf "  %-30s %s\n" "screenshot:" "artifacts/hyprland.png ($(stat -c%s /artifacts/hyprland.png) bytes)"
    else
        printf "  %-30s %s\n" "screenshot:" "FAILED: $(head -1 /tmp/grim.err)"
    fi
fi

# ── is the GTK theme the one we asked for? ──────────────────────────────────
# If the named theme is missing, GTK silently falls back to Adwaita and paints
# its own opaque widget background behind the shell's semi-transparent islands
# — so the bar stops following the palette while the CSS itself is still fine.
echo "  --- gtk theme resolution ---"
# python-gobject is not a dependency any more (the fabric shell needed it);
# check only where it happens to be installed.
python3 -c 'import gi' 2>/dev/null || echo "    skipped: python-gobject not installed"
python3 -c 'import gi' 2>/dev/null && python3 - <<'GTKPY' 2>&1 | sed 's/^/    /'
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
s = Gtk.Settings.get_default()
print("theme in use:      %s" % s.get_property("gtk-theme-name"))
print("prefer-dark:       %s" % s.get_property("gtk-application-prefer-dark-theme"))
print("icon theme:        %s" % s.get_property("gtk-icon-theme-name"))
print("font:              %s" % s.get_property("gtk-font-name"))
import os
for p in (os.path.expanduser("~/.themes"), "/usr/share/themes"):
    print("%-18s %s" % (p + ":", ", ".join(sorted(os.listdir(p))[:4]) if os.path.isdir(p) else "MISSING"))
GTKPY

# ── does the shell re-theme in place? ───────────────────────────────────────
# What the wallpaper picker does: `wallpaper set` runs pywal16 and the shell
# reads ~/.cache/wal/colors.json live. If the bar keeps its colour, the shell's
# watch on that file is dead — which used to mean restarting it.
if [ -n "${nested:-}" ] && command -v grim >/dev/null; then
    echo "  --- live re-theme test ---"
    before="$(palette)"
    # The pointer holds what install.sh chose; pick a different file, since
    # comparing a palette against itself proves nothing.
    current="$(readlink -f "$HOME/.local/state/simplychit/wallpaper" 2>/dev/null)"
    other="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f ! -name "$(basename "$current")" | head -1)"
    printf "    %-28s %s\n" "palette before:" "$before"
    printf "    %-28s %s\n" "switching to:" "$(basename "$other")"
    qs -c simplychit ipc call wallpaper set "$other" >/dev/null 2>&1
    for _ in $(seq 20); do
        [ "$(palette)" != "$before" ] && break
        sleep 1
    done
    after="$(palette)"
    printf "    %-28s %s\n" "palette after:" "$after"
    sleep 2
    WAYLAND_DISPLAY="$nested" grim /artifacts/after-retheme.png 2>/dev/null \
        && printf "    %-28s %s\n" "second screenshot:" "artifacts/after-retheme.png"
    if [ "$before" != "$after" ]; then
        echo "    palette DID change — if the two screenshots differ, the shell"
        echo "    re-themed in place with no restart."
    else
        echo "    palette unchanged — test inconclusive (need a second wallpaper)"
    fi
fi

echo "  --- errors in the session log ---"
if grep -iqE 'traceback|error|critical' /tmp/hypr.log; then
    grep -iE 'traceback|error|critical' /tmp/hypr.log | head -12 | sed 's/^/    /'
else
    echo "    (clean)"
fi
cp /tmp/hypr.log /artifacts/hypr.log 2>/dev/null

if [ "${SIMPLYCHIT_UI:-}" = 1 ]; then
    cat <<'KEYS'

  ┌──────────────────────────────────────────────────────────────┐
  │  The desktop is running in the window on your screen.        │
  │  Click it to focus, then use CAPS LOCK as the SUPER key.     │
  │                                                              │
  │  Caps is remapped to an additional Super inside the          │
  │  container, so your real keybinds work unchanged — the host  │
  │  would otherwise swallow every SUPER press before it got     │
  │  here. Caps no longer latches capitals while in there.       │
  │                                                              │
  │    CAPS SPACE  app launcher       CAPS W    wallpapers       │
  │    CAPS C      control centre     CAPS PrtSc screenshot      │
  │    CAPS N      notifications      CAPS ESC  power menu       │
  │    CAPS V      clipboard          CAPS /    cheatsheet       │
  │    CAPS .      emoji picker       CAPS ⏎    terminal         │
  │                                                              │
  │  CAPS / shows the real cheatsheet — every bind, read live    │
  │  from Hyprland. That is the full list.                       │
  └──────────────────────────────────────────────────────────────┘

  Screenshot anytime:  grim /artifacts/shot.png
  Test a notification: notify-send simplychit "hello"

  Type `exit` here to tear the whole thing down.

KEYS
    export HYPRLAND_INSTANCE_SIGNATURE
    exec bash
fi

hyprctl dispatch exit >/dev/null 2>&1 || kill "$hyprpid" 2>/dev/null
echo "==========================================================="
exit $install_rc
