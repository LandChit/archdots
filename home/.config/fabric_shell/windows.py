"""The daemon's control protocol — the window names and the client that talks
to them. The one place either is spelled out.

Kept free of fabric imports on purpose: ctl.py runs on every keybind press, and
importing common would pull all of fabric and GTK into a process whose whole job
is to write one line to a socket. bar.py imports it too, to open the calendar
and the battery card from its islands.

daemon.py checks its window registry against WINDOWS at startup, so adding a
window in one place and forgetting the other is caught immediately.
"""

import socket

SOCKET_PATH = "/tmp/fabric-shell.sock"

WINDOWS = (
    "launcher",
    "powermenu",
    "clipboard",
    "emoji",
    "battery",
    "osd",
    "calendar",
    "notifications",
    "control",
    "wallpaper",
    "screenshot",
    "keybinds",
)

# Windows that take an argument after their name (`show osd volume`), mapped to
# the values they accept. Anything absent here is shown with no argument.
WINDOW_ARGS = {
    "osd": ("volume", "mic", "brightness"),
}


def send(action: str, window: str, argument: str | None = None) -> str | None:
    """Send one command to the daemon. Returns an error message, or None if sent.

    Callers decide what to do with a failure: ctl.py prints it and exits, the
    bar ignores it — a dead daemon should not take a click handler down with it.
    """
    command = f"{action} {window}" + (f" {argument}" if argument else "")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(2)
            client.connect(SOCKET_PATH)
            client.sendall(command.encode())
    except FileNotFoundError:
        return f"daemon not running (no socket at {SOCKET_PATH})"
    except Exception as e:
        return f"failed: {e}"
    return None
