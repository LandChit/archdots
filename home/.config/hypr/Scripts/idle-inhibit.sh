#!/bin/sh
# idle-inhibit.sh [toggle|on|off|status] — keep the machine awake.
#
# Holds a `systemd-inhibit --what=idle` lock, which hypridle respects
# (ignore_systemd_inhibit is off), so no dim, lock, screen-off or suspend
# while it is on. The lock dies with the session; nothing persists.

pidfile="${XDG_RUNTIME_DIR:-/tmp}/simplychit-idle-inhibit.pid"

running() {
    [ -r "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

on() {
    running && return 0
    systemd-inhibit --what=idle --who=simplychit --why="Idle inhibit toggle" \
        --mode=block sleep infinity &
    echo $! > "$pidfile"
    notify-send -t 2000 -a SimplyChit "Staying awake" "Idle lock and suspend are off"
}

off() {
    if running; then
        kill "$(cat "$pidfile")"
        notify-send -t 2000 -a SimplyChit "Idle back on" "The screen locks and suspends when idle again"
    fi
    rm -f "$pidfile"
}

case "${1:-toggle}" in
    toggle) if running; then off; else on; fi ;;
    on)     on ;;
    off)    off ;;
    status) if running; then echo on; else echo off; exit 1; fi ;;
    *)      echo "usage: ${0##*/} [toggle|on|off|status]" >&2; exit 2 ;;
esac
