#!/usr/bin/env bash
#
# Runs INSIDE the test container. Mounted at /checks.sh by runscript.sh.
#
# Copies the read-only repo mount to a writable path, runs install.sh with
# whatever arguments were passed through, then verifies the result: that stow
# linked what it should, that Hyprland can parse the config, and — with
# ARCHDOTS_HYPR=1 — that the compositor and shell actually come up.
#
# Kept as a file rather than inlined into `docker run bash -c '...'` because
# these checks need both quote characters, and nesting them inside one shell
# string silently truncates the script.

set -uo pipefail

REPO=/home/tester/archdots

# ── stage the repo ──────────────────────────────────────────────────────────

cp -a /src "$REPO"
cd "$REPO" || exit 1

# A fresh clone has none of these. Without stripping them the test inherits the
# host's machine-specific files and reports "monitor.lua already exists", which
# is the opposite of what a new machine sees.
rm -f  .config/hypr/config/custom/*.lua
rm -rf .config/fabric_shell/.venv .omc .config/hypr/.omc

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
if [ "${ARCHDOTS_FAST:-}" = 1 ]; then
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

# stow folds: ~/.config is ONE symlink into the repo, so paths beneath it are
# the repo files themselves. Test that they resolve there, not that each leaf
# is individually a link.
resolves() {
    case "$(readlink -f "$1" 2>/dev/null)" in
        "$REPO"/*) echo "ok" ;;
        "")        echo "MISSING" ;;
        *)         echo "NOT IN REPO: $(readlink -f "$1")" ;;
    esac
}

echo
echo "===================== post-run checks ====================="
echo "  install.sh exit code:          $install_rc"
printf "  %-30s %s\n" ".zshrc -> repo:"        "$(resolves "$HOME/.zshrc")"
printf "  %-30s %s\n" "hypr config -> repo:"   "$(resolves "$HOME/.config/hypr/config/keybind.lua")"
printf "  %-30s %s\n" "fabric_shell -> repo:"  "$(resolves "$HOME/.config/fabric_shell/bar.py")"
printf "  %-30s %s\n" "install.sh NOT stowed:" "$([ -e "$HOME/install.sh" ] && echo LEAKED || echo ok)"
printf "  %-30s %s\n" "wallpapers NOT stowed:" "$([ -e "$HOME/wallpapers" ] && echo LEAKED || echo ok)"
printf "  %-30s %s\n" "wallpapers in Pictures:" "$(ls "$HOME/Pictures/wallpapers" 2>/dev/null | tr '\n' ' ')"
printf "  %-30s %s\n" "oh-my-zsh:"             "$([ -d "$HOME/.oh-my-zsh" ] && echo yes || echo NO)"
printf "  %-30s %s\n" "zsh plugin submodules:" "$(ls "$HOME/.ohmyzsh_custom/plugins/zsh-autosuggestions" 2>/dev/null | head -1 || echo EMPTY)"
printf "  %-30s %s\n" "venv python:"           "$([ -x "$HOME/.config/fabric_shell/.venv/bin/python" ] && echo yes || echo no)"
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

[ "${ARCHDOTS_HYPR:-}" = 1 ] || exit $install_rc

# ── actually run it ─────────────────────────────────────────────────────────

echo
echo "=============== nested hyprland session ==================="
export XDG_RUNTIME_DIR=/run/user/1000

# The host compositor consumes every SUPER combination before the nested one
# sees it, so the real binds are unreachable from inside. This makes Caps an
# additional Super *inside the container*, so every real bind works when pressed
# with Caps. custom/input.lua is gitignored and loaded after the defaults.
# Applied to every nested run, not just --ui: the host swallows SUPER in
# both cases, and a non-interactive run should verify the same setup.
if [ "${ARCHDOTS_HYPR:-}" = 1 ] && [ -r /ui-input.lua ]; then
    mkdir -p "$HOME/.config/hypr/config/custom"
    cp /ui-input.lua "$HOME/.config/hypr/config/custom/input.lua"
    echo "  Caps mapped to Super for the nested session"
fi

# Hyprland's nested Wayland backend hands its output a scale of 2, so every CSS
# pixel renders as two and the whole shell comes out twice the size it is on a
# real machine — which reads as a theming bug rather than a scaling one.
# install.sh only writes rules for the monitors it detected in /sys (the host's),
# and WAYLAND-1 is not among them, so pin it here. Later rules win.
mkdir -p "$HOME/.config/hypr/config/custom"
cat >> "$HOME/.config/hypr/config/custom/monitor.lua" <<'MON'

-- Added by the test harness: the nested output, at 1:1 so the shell renders at
-- the same size it would on real hardware.
hl.monitor({ output = "WAYLAND-1", mode = "preferred", position = "0x0", scale = 1.0 })
MON

echo "  palette in use: $(grep -E '^\s+--(background|color4):' \
    "$HOME/.config/fabric_shell/css/colors-fabric.css" 2>/dev/null | tr -d ' \n' || echo unknown)"

# dbus-run-session: the shell daemon claims org.freedesktop.Notifications, and
# a container has no session bus otherwise.
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
    pgrep -f "fabric_shell/bar.py" >/dev/null 2>&1 && break
    sleep 1
done
printf "  %-30s %s\n" "daemon.py:" "$(pgrep -f 'fabric_shell/daemon.py' >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"
printf "  %-30s %s\n" "bar.py:"    "$(pgrep -f 'fabric_shell/bar.py'    >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"

printf "  %-30s %s\n" "bar layer geometry:" "$(hyprctl layers -j | python3 -c 'import json,sys
d=json.load(sys.stdin)
for mon in d.values():
    for lvl in mon["levels"].values():
        for l in lvl:
            if "fabric" in l.get("namespace",""):
                print("%s %sx%s at %s,%s" % (l["namespace"], l["w"], l["h"], l["x"], l["y"]))' 2>/dev/null | head -2 | tr '\n' ' ')"
printf "  %-30s %s\n" "fabric layer surfaces:"  "$(hyprctl layers 2>/dev/null | grep -c fabric)"
# The session bus belongs to the dbus-run-session that Hyprland runs inside;
# this script is outside it, so it has to borrow that bus address from the
# daemon's own environment. Querying without this reports "unclaimed" for a bus
# that is in fact owned, which reads as a failure when nothing is wrong.
dpid="$(pgrep -f 'fabric_shell/daemon.py' | head -1)"
if [ -n "$dpid" ] && [ -r "/proc/$dpid/environ" ]; then
    bus="$(tr '\0' '\n' < "/proc/$dpid/environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)"
    # busctl prints "PID=1234", so the separator is '=' and not whitespace —
    # and the anchor has to be PID= or it also matches the PIDFD line.
    # Gio.bus_own_name is asynchronous — it returns immediately and the name is
    # acquired later on the main loop, so a single query right after startup can
    # miss it. Retry rather than declare failure on the first look.
    owner=""
    for _ in $(seq 15); do
        owner="$(DBUS_SESSION_BUS_ADDRESS="$bus" busctl --user status org.freedesktop.Notifications 2>/dev/null | awk -F= '/^PID=/{print $2}')"
        [ -n "$owner" ] && break
        sleep 1
    done
    if [ -n "$owner" ]; then
        printf "  %-30s %s\n" "notification bus owner:" "pid $owner$([ "$owner" = "$dpid" ] && echo ' (= daemon.py, correct)')"
    else
        printf "  %-30s %s\n" "notification bus owner:" "UNCLAIMED"
        echo "    bus address: ${bus:-EMPTY}"
        echo "    names on that bus matching 'otif':"
        DBUS_SESSION_BUS_ADDRESS="$bus" busctl --user list 2>&1 | grep -i otif | sed 's/^/      /' \
            || echo "      (none)"
        echo "    busctl list exit: $(DBUS_SESSION_BUS_ADDRESS="$bus" busctl --user list >/dev/null 2>&1; echo $?)"

    fi
else
    printf "  %-30s %s\n" "notification bus owner:" "n/a (no daemon to read the bus from)"
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
"$HOME/.config/fabric_shell/.venv/bin/python" - <<'GTKPY' 2>&1 | sed 's/^/    /'
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
# Exactly what the wallpaper picker does internally: regenerate the palette with
# pywal, then copy it into css/. Everything else is common._watch_palette's job.
# If the bar does not change colour after this, the Gio.FileMonitor is dead —
# which is the failure that used to require restarting the shell.
if [ -n "${nested:-}" ] && command -v grim >/dev/null; then
    echo "  --- live re-theme test ---"
    before="$(grep -E '^\s+--background:' "$HOME/.config/fabric_shell/css/colors-fabric.css" | tr -d ' ')"
    # install.sh's $WALLPAPER is not in scope here. The wallpaper pointer holds
    # what it actually chose — hyprpaper.conf names the pointer, not a picture —
    # so resolve that and pick a different file. Comparing a palette against
    # itself proves nothing.
    current="$(readlink -f "$HOME/.local/state/archdots/wallpaper" 2>/dev/null)"
    other="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f ! -name "$(basename "$current")" | head -1)"
    printf "    %-28s %s\n" "palette before:" "$before"
    printf "    %-28s %s\n" "switching to:" "$(basename "$other")"
    wal -i "$other" -n -q >/dev/null 2>&1
    cp "$HOME/.cache/wal/colors-fabric.css" "$HOME/.config/fabric_shell/css/colors-fabric.css"
    sleep 4
    after="$(grep -E '^\s+--background:' "$HOME/.config/fabric_shell/css/colors-fabric.css" | tr -d ' ')"
    printf "    %-28s %s\n" "palette after:" "$after"
    WAYLAND_DISPLAY="$nested" grim /artifacts/after-retheme.png 2>/dev/null \
        && printf "    %-28s %s\n" "second screenshot:" "artifacts/after-retheme.png"
    if [ "$before" != "$after" ]; then
        echo "    palette file DID change — if the two screenshots differ, the"
        echo "    shell re-themed in place with no restart."
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

if [ "${ARCHDOTS_UI:-}" = 1 ]; then
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
  Test a notification: notify-send archdots "hello"

  Type `exit` here to tear the whole thing down.

KEYS
    export HYPRLAND_INSTANCE_SIGNATURE
    exec bash
fi

hyprctl dispatch exit >/dev/null 2>&1 || kill "$hyprpid" 2>/dev/null
echo "==========================================================="
exit $install_rc
