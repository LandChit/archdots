#!/usr/bin/env python3
"""fabric-shell daemon — keeps every overlay window alive in the background.

Windows are revealed and dismissed over a Unix socket rather than respawned,
so opening the launcher costs nothing more than a show().

    Socket:   /tmp/fabric-shell.sock
    Commands: toggle|show|hide  <window> [argument]

Window names live in windows.py, which ctl.py shares.
Started from Hyprland's autorun, driven by ctl.py from the keybinds.
"""

import os
import socket

import common
from windows import WINDOWS
from launcher import Launcher
from powermenu import PowerMenu
from clipboard import ClipboardManager
from emoji import EmojiPicker
from battery import BatteryWarning
from osd import OSD
from calendar_popup import CalendarPopup
from notifications import NotificationCenter, NotificationPopups, NotificationStore
from controlcenter import ControlCenter
from wallpapers import WallpaperPicker
from screenshot import ScreenshotMenu
from keybinds import KeybindsOverlay

from gi.repository import GLib  # type: ignore

SOCKET_PATH = "/tmp/fabric-shell.sock"


def serve(windows: dict) -> None:
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(5)
    server.setblocking(False)

    def on_incoming(_fd, _condition):
        try:
            conn, _ = server.accept()
            command = conn.recv(128).decode().strip()
            conn.close()
            handle(command, windows)
        except Exception as e:
            print(f"[daemon] socket error: {e}")
        return True  # keep watching

    GLib.io_add_watch(server.fileno(), GLib.IO_IN, on_incoming)
    print(f"[daemon] listening on {SOCKET_PATH}")


def handle(command: str, windows: dict) -> None:
    # a trailing argument is optional and window-specific: `show osd volume`
    parts = command.split()
    if len(parts) not in (2, 3):
        print(f"[daemon] bad command: {command!r}")
        return

    action, name, *args = parts
    window = windows.get(name)
    if window is None:
        print(f"[daemon] unknown window: {name!r}")
        return

    if action == "hide" or (action == "toggle" and window.get_visible()):
        window.dismiss()
    elif action in ("show", "toggle"):
        # only one mode is ever on screen at a time — non-exclusive windows
        # (the battery warning, the OSD) are feedback and are left alone
        if window.exclusive:
            for other in windows.values():
                if other is not window and other.exclusive and other.get_visible():
                    other.dismiss()
        try:
            window.reveal(*args)
        except TypeError:
            print(f"[daemon] {name!r} takes no argument: {command!r}")
    else:
        print(f"[daemon] unknown action: {action!r}")


if __name__ == "__main__":
    # the popups are not a ctl window — they show themselves when something
    # arrives — but they share the store with the centre and the control centre
    store = NotificationStore()
    popups = NotificationPopups(store)

    windows = {
        "launcher": Launcher(),
        "powermenu": PowerMenu(),
        "clipboard": ClipboardManager(),
        "emoji": EmojiPicker(),
        "battery": BatteryWarning(),
        "osd": OSD(),
        "calendar": CalendarPopup(),
        "notifications": NotificationCenter(store, popups),
        "control": ControlCenter(store),
        "wallpaper": WallpaperPicker(),
        "screenshot": ScreenshotMenu(),
        "keybinds": KeybindsOverlay(),
    }

    # ctl.py validates names against windows.WINDOWS before sending anything, so
    # a name listed there but missing here would be silently accepted and dropped
    missing = set(WINDOWS) - set(windows)
    if missing:
        print(f"[daemon] windows.py lists windows with no instance: {sorted(missing)}")

    common.style_screen(
        "launcher.css",
        "powermenu.css",
        "clipboard.css",
        "emoji.css",
        "battery.css",
        "osd.css",
        "calendar.css",
        "notifications.css",
        "controlcenter.css",
        "wallpapers.css",
        "screenshot.css",
        "keybinds.css",
    )
    serve(windows)

    print("[daemon] all windows ready — entering main loop")
    GLib.MainLoop().run()
