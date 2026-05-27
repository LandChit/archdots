#!/usr/bin/env python3
"""
fabric-shell control script — sends commands to the running daemon.

Usage:
    ctl.py toggle|show|hide  launcher|powermenu|clipboard|emoji

Examples:
    ctl.py toggle launcher
    ctl.py show powermenu
    ctl.py hide emoji
"""
import socket
import sys

SOCKET_PATH = "/tmp/fabric-shell.sock"
VALID_ACTIONS = {"toggle", "show", "hide"}
VALID_WINDOWS = {"launcher", "powermenu", "clipboard", "emoji"}


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} toggle|show|hide launcher|powermenu|clipboard|emoji")
        sys.exit(1)

    action, name = sys.argv[1], sys.argv[2]

    if action not in VALID_ACTIONS:
        print(f"[ctl] unknown action: {action!r}  (choose: {', '.join(sorted(VALID_ACTIONS))})")
        sys.exit(1)
    if name not in VALID_WINDOWS:
        print(f"[ctl] unknown window: {name!r}  (choose: {', '.join(sorted(VALID_WINDOWS))})")
        sys.exit(1)

    cmd = f"{action} {name}"
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(SOCKET_PATH)
        s.sendall(cmd.encode())
        s.close()
    except FileNotFoundError:
        print(f"[ctl] daemon not running (socket not found: {SOCKET_PATH})")
        sys.exit(1)
    except Exception as e:
        print(f"[ctl] failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
