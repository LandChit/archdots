#!/usr/bin/env python3
"""fabric-shell control client — sends one command to the running daemon.

    ctl.py toggle|show|hide  launcher|powermenu|clipboard|emoji
"""

import socket
import sys

SOCKET_PATH = "/tmp/fabric-shell.sock"
ACTIONS = ("toggle", "show", "hide")
WINDOWS = ("launcher", "powermenu", "clipboard", "emoji")


def fail(message: str) -> None:
    print(f"[ctl] {message}")
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} {'|'.join(ACTIONS)} {'|'.join(WINDOWS)}")

    action, window = sys.argv[1], sys.argv[2]
    if action not in ACTIONS:
        fail(f"unknown action {action!r} (choose: {', '.join(ACTIONS)})")
    if window not in WINDOWS:
        fail(f"unknown window {window!r} (choose: {', '.join(WINDOWS)})")

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(2)
            client.connect(SOCKET_PATH)
            client.sendall(f"{action} {window}".encode())
    except FileNotFoundError:
        fail(f"daemon not running (no socket at {SOCKET_PATH})")
    except Exception as e:
        fail(f"failed: {e}")


if __name__ == "__main__":
    main()
