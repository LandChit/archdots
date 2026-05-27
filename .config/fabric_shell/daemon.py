#!/usr/bin/env python3
"""
fabric-shell daemon — keeps all overlay windows alive in the background.
Windows are shown/hidden via Unix socket commands instead of being respawned.

Socket:   /tmp/fabric-shell.sock
Commands: toggle|show|hide  launcher|powermenu|clipboard|emoji

Autostart (add to autorun.lua):
    ~/.config/fabric_shell/.venv/bin/python ~/.config/fabric_shell/daemon.py &

Control via ctl.py:
    ~/.config/fabric_shell/.venv/bin/python ~/.config/fabric_shell/ctl.py toggle launcher
"""
import os
import socket as _socket

# fabric must be imported first — it calls gi.require_version("Gtk", "3.0")
# importing gi.repository before this causes a version conflict with GTK 4.0
from fabric.utils.helpers import monitor_file, compile_css

from launcher import Launcher
from powermenu import PowerMenu
from clipboard import ClipboardManager
from emoji import EmojiPicker, _ensure_cache, _check_and_update_cache

# safe to import now that fabric has locked in GTK 3.0
from gi.repository import GLib, Gtk, Gdk

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")
SOCKET_PATH = "/tmp/fabric-shell.sock"

_css_provider: Gtk.CssProvider | None = None


# ── CSS ────────────────────────────────────────────────────────────────────────

def load_css(*_) -> None:
    global _css_provider

    try:
        with open(os.path.join(CSS_DIR, "colors-fabric.css")) as f:
            color_css = "\n".join(
                line for line in f.read().splitlines() if "url(" not in line
            )
    except FileNotFoundError:
        color_css = ""

    parts = [color_css]
    for fname in ("launcher.css", "powermenu.css", "clipboard.css", "emoji.css"):
        try:
            with open(os.path.join(CSS_DIR, fname)) as f:
                parts.append(f.read())
        except FileNotFoundError:
            pass

    combined = "\n".join(parts)
    screen = Gdk.Screen.get_default()

    if _css_provider is not None:
        Gtk.StyleContext.remove_provider_for_screen(screen, _css_provider)

    _css_provider = Gtk.CssProvider()
    # Use bytearray + compile_css to match fabric's own CSS loading pipeline
    _css_provider.load_from_data(bytearray(compile_css(combined, base_path=CSS_DIR), "utf-8"))
    Gtk.StyleContext.add_provider_for_screen(
        screen,
        _css_provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER,
    )


# ── IPC socket ─────────────────────────────────────────────────────────────────

def setup_socket(windows: dict) -> None:
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(5)
    server.setblocking(False)

    def on_incoming(fd, condition, srv):
        try:
            conn, _ = srv.accept()
            cmd = conn.recv(128).decode().strip()
            conn.close()
            _handle(cmd, windows)
        except Exception as e:
            print(f"[daemon] socket error: {e}")
        return True  # keep watching

    GLib.io_add_watch(server.fileno(), GLib.IO_IN, on_incoming, server)
    print(f"[daemon] listening on {SOCKET_PATH}")


def _handle(cmd: str, windows: dict) -> None:
    parts = cmd.split(maxsplit=1)
    if len(parts) != 2:
        print(f"[daemon] bad command: {cmd!r}")
        return
    action, name = parts
    win = windows.get(name)
    if win is None:
        print(f"[daemon] unknown window: {name!r}")
        return

    if action == "toggle":
        if win.get_visible():
            win.dismiss()
        else:
            _show(name, win, windows)
    elif action == "show":
        _show(name, win, windows)
    elif action == "hide":
        win.dismiss()
    else:
        print(f"[daemon] unknown action: {action!r}")


def _show(name: str, win, windows: dict) -> None:
    """Dismiss any other visible overlay, then reveal the target."""
    for n, w in windows.items():
        if n != name and w.get_visible():
            w.dismiss()
    win.reveal()


# ── entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Ensure emoji cache exists before creating picker
    _ensure_cache()

    launcher = Launcher(daemon_mode=True)
    powermenu = PowerMenu(daemon_mode=True)
    clipboard = ClipboardManager(daemon_mode=True)
    emoji = EmojiPicker(daemon_mode=True)

    windows = {
        "launcher": launcher,
        "powermenu": powermenu,
        "clipboard": clipboard,
        "emoji": emoji,
    }

    load_css()
    monitor_file(os.path.join(CSS_DIR, "colors-fabric.css"), load_css)

    # Background emoji cache refresh
    _check_and_update_cache(on_updated=emoji.reload_emojis)

    setup_socket(windows)

    print("[daemon] all windows ready — entering main loop")
    GLib.MainLoop().run()
