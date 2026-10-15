#!/bin/sh
# shell-watchdog.sh — run the shell (qs -c simplychit) and start it again when
# it crashes. Started by shell.restart() (hypr/config/helpers/shell.lua).
#
# How qs ends tells a crash from a stop: `qs kill` and a refused second
# instance exit 0, the end of the session sends SIGTERM (143), and a crash
# goes through Quickshell's crash handler (255). Only a crash, while
# Hyprland is still running, starts it again. The restarted shell finds the
# note left here and says so in a toast (services/Events.qml). Three crashes
# within a minute and it gives up, with a Hyprland notification instead,
# since the shell that would show anything is the thing that keeps failing.

lock="${XDG_RUNTIME_DIR:-/tmp}/simplychit-shell.lock"
note="${XDG_STATE_HOME:-$HOME/.local/state}/simplychit/shell-crashed"

# One watchdog at a time. A restart starts the new one right after `qs kill`;
# it waits here for the old one, which leaves once its shell has exited.
exec 9>"$lock"
flock -w 10 9 || exit 1

# A shell started without a watchdog (before an update, or by hand) may still
# be on its way out, and -n refuses to start next to it.
i=0
while [ $i -lt 50 ] && qs -c simplychit list 2>/dev/null | grep -q 'Process ID'; do
    sleep 0.1
    i=$((i + 1))
done

recent=""
while :; do
    # 9>&-: the shell must not hold the lock after the watchdog is gone
    qs -c simplychit -n >/dev/null 2>&1 9>&-
    status=$?
    case $status in
    0 | 129 | 130 | 143) exit 0 ;; # stopped, or the session is ending
    esac
    hyprctl version >/dev/null 2>&1 || exit 0 # Hyprland is gone too

    now=$(date +%s)
    kept=""
    for t in $recent; do
        [ $((now - t)) -lt 60 ] && kept="$kept $t"
    done
    recent="$kept $now"
    if [ "$(echo $recent | wc -w)" -ge 3 ]; then
        rm -f "$note"
        hyprctl eval 'hl.notification.create({ text = "The shell keeps crashing and was not restarted. Super+Shift+Ctrl+Alt+R starts it; qs log -c simplychit shows why.", timeout = 20000, icon = "error" })' >/dev/null 2>&1
        exit 1
    fi

    mkdir -p "$(dirname "$note")"
    echo "$status" >"$note"
    sleep 1
done
