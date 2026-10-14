#!/bin/sh
# hypridle's lock_cmd: lock with the shell's lock screen when it is enabled
# (lock.enabled in ~/.config/archdots/settings.json) and answering, and with
# hyprlock otherwise. Anything but a clear "ok" from the shell means hyprlock,
# so a shell that is down or broken can never leave the screen unlocked.

answer=$(timeout 3 qs -c archdots ipc call lock lock 2>/dev/null)
[ "$answer" = ok ] && exit 0

pidof hyprlock >/dev/null || exec hyprlock
