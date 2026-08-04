#!/usr/bin/env python3
"""fabric-shell daemon — keeps every overlay window alive in the background.

Windows are revealed and dismissed over a Unix socket rather than respawned,
so opening the launcher costs nothing more than a show().

    Socket:   /tmp/fabric-shell.sock
    Commands: toggle|show|hide  launcher|powermenu|clipboard|emoji

Started from Hyprland's autorun, driven by ctl.py from the keybinds.
"""

import os
import socket

import common
from launcher import Launcher
from powermenu import PowerMenu
from clipboard import ClipboardManager
from emoji import EmojiPicker

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
    parts = command.split(maxsplit=1)
    if len(parts) != 2:
        print(f"[daemon] bad command: {command!r}")
        return

    action, name = parts
    window = windows.get(name)
    if window is None:
        print(f"[daemon] unknown window: {name!r}")
        return

    if action == "hide" or (action == "toggle" and window.get_visible()):
        window.dismiss()
    elif action in ("show", "toggle"):
        # only one overlay is ever on screen at a time
        for other in windows.values():
            if other is not window and other.get_visible():
                other.dismiss()
        window.reveal()
    else:
        print(f"[daemon] unknown action: {action!r}")


if __name__ == "__main__":
    windows = {
        "launcher": Launcher(),
        "powermenu": PowerMenu(),
        "clipboard": ClipboardManager(),
        "emoji": EmojiPicker(),
    }

    common.style_screen("launcher.css", "powermenu.css", "clipboard.css", "emoji.css")
    serve(windows)

    print("[daemon] all windows ready — entering main loop")
    GLib.MainLoop().run()
