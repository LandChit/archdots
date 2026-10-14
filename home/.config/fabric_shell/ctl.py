#!/usr/bin/env python3
"""fabric-shell control client — sends one command to the running daemon.

    ctl.py toggle|show|hide  <window> [argument]

Windows are listed in windows.py; the few that take an argument are listed
there too — `ctl.py show osd volume`.
"""

import sys

from windows import WINDOWS, WINDOW_ARGS, send

ACTIONS = ("toggle", "show", "hide")


def fail(message: str) -> None:
    print(f"[ctl] {message}")
    raise SystemExit(1)


def main() -> None:
    if not 3 <= len(sys.argv) <= 4:
        fail(f"usage: {sys.argv[0]} {'|'.join(ACTIONS)} {'|'.join(WINDOWS)} [argument]")

    action, window = sys.argv[1], sys.argv[2]
    argument = sys.argv[3] if len(sys.argv) == 4 else None
    if action not in ACTIONS:
        fail(f"unknown action {action!r} (choose: {', '.join(ACTIONS)})")
    if window not in WINDOWS:
        fail(f"unknown window {window!r} (choose: {', '.join(WINDOWS)})")

    # catch a typo here rather than letting the daemon quietly do nothing
    allowed = WINDOW_ARGS.get(window)
    if argument is not None:
        if allowed is None:
            fail(f"{window!r} takes no argument")
        if argument not in allowed:
            fail(f"unknown {window} argument {argument!r} (choose: {', '.join(allowed)})")

    error = send(action, window, argument)
    if error is not None:
        fail(error)


if __name__ == "__main__":
    main()
