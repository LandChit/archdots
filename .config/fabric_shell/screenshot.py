"""Screenshot menu — region, window, whole screen, or delayed.

Shaped like powermenu.py: a full-screen scrim with a row of cards, driven by
the arrow keys or the pointer.

Every shot lands in ~/Pictures/screenshots *and* on the clipboard, which is
what the old keybind one-liners in hypr/config/keybind.lua did.
"""

import os
import subprocess

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import Overlay

from gi.repository import Gdk, GLib, GtkLayerShell  # type: ignore

SAVE_DIR = os.path.expanduser("~/Pictures/screenshots")
FILENAME = "Screenshot-$(date +%F_%T).png"
DELAY_SECONDS = 5

# label, glyph, hint, kind
ACTIONS = [
    ("Region", "󰩭", "Drag a box", "region"),
    ("Window", "󰖯", "The focused window", "window"),
    ("Screen", "󰍹", "Everything", "full"),
    (f"Delay {DELAY_SECONDS}s", "󰔛", "Then the whole screen", "delay"),
]


def capture_command(kind: str) -> str:
    """One shell line: grab, save, copy, then say so.

    `wl-copy` reads the saved file rather than running grim twice, so the
    clipboard and the file are guaranteed to hold the same picture.

    The filename is expanded **once** into a shell variable. Repeating
    `$(date ...)` at each use looks harmless but re-runs the clock, so a
    capture that straddles a second would copy a file that does not exist.
    """
    target = '"$F"'
    setup = f'mkdir -p "{SAVE_DIR}"; F="{SAVE_DIR}/{FILENAME}"'

    if kind == "region":
        # slurp prints the selection; cancelling it exits non-zero, and a
        # cancelled screenshot should be silent rather than an error
        grab = 'REGION=$(slurp) || exit 0; grim -g "$REGION"'
    elif kind == "window":
        # hyprctl reports the focused window as at:[x,y] size:[w,h]; grim wants
        # "x,y wxh", so the four numbers are pulled out and reassembled
        grab = (
            "BOX=$(hyprctl activewindow -j | "
            "grep -oP '\"(at|size)\":\\s*\\[\\K[^]]+' | tr -d ' ' | paste -sd' '); "
            'set -- $BOX; grim -g "${1%,*},${1#*,} ${2%,*}x${2#*,}"'
        )
    elif kind == "delay":
        grab = f"sleep {DELAY_SECONDS}; grim"
    else:
        grab = "grim"

    return (
        f"{setup}; {grab} {target} && wl-copy < {target} && "
        f'notify-send -t 2500 "Screenshot saved" "$(basename {target})"'
    )


class ScreenshotMenu(Overlay):
    """Full-screen scrim with one card per capture mode."""

    def __init__(self):
        # anchored on all four edges so the scrim covers the whole screen
        # rather than shrinking to the size of the cards
        super().__init__(
            title="fabric-screenshot",
            layer="overlay",
            anchor="left top right bottom",
            keyboard_mode="exclusive",
        )
        # -1 ignores other windows' exclusive zones so the scrim also covers
        # the bar; fabric's exclusivity="none" maps to zone 0, which leaves
        # the bar's reserved strip uncovered
        GtkLayerShell.set_exclusive_zone(self, -1)
        self.add_style_class("shot-window")

        self._cards: list[Box] = []
        self._selected: int | None = None

        row = Box(
            orientation="horizontal",
            spacing=16,
            h_align="center",
            v_align="center",
            style_classes="shot-row",
            children=[
                self._build(index, *action) for index, action in enumerate(ACTIONS)
            ],
        )

        self.children = Box(
            orientation="vertical",
            spacing=20,
            h_align="center",
            v_align="center",
            h_expand=True,
            v_expand=True,
            style_classes="shot-root",
            children=[
                row,
                Label(
                    label="←→ navigate · ↵ capture · esc cancel",
                    style_classes="shot-hint",
                    h_align="center",
                ),
            ],
        )
        self.show_all()
        self.hide()

    def _build(
        self, index: int, label: str, icon: str, hint: str, _kind: str
    ) -> Button:
        card = Box(
            orientation="vertical",
            spacing=8,
            h_align="center",
            v_align="center",
            style_classes="shot-card",
            children=[
                Label(label=icon, style_classes="shot-icon", h_align="center"),
                Label(label=label, style_classes="shot-label", h_align="center"),
                Label(label=hint, style_classes="shot-hint-small", h_align="center"),
            ],
        )
        self._cards.append(card)
        button = Button(child=card, style_classes="shot-btn")
        button.connect("clicked", lambda *_: self._run(index))
        return button

    # ── selection ───────────────────────────────────────────────────────────

    def _highlight(self, index: int | None) -> None:
        for position, card in enumerate(self._cards):
            if position == index:
                card.add_style_class("shot-selected")
            else:
                card.remove_style_class("shot-selected")
        self._selected = index

    def _step(self, delta: int) -> None:
        self._highlight(
            0 if self._selected is None else (self._selected + delta) % len(self._cards)
        )

    def on_key(self, event) -> bool:
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if self._selected is not None:
                self._run(self._selected)
        elif event.keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self._step(-1)
        elif event.keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self._step(1)
        else:
            return False
        return True

    # ── capture ─────────────────────────────────────────────────────────────

    def _run(self, index: int) -> None:
        kind = ACTIONS[index][3]
        self.dismiss()
        # the menu has to be off screen before grim fires or it lands in the
        # shot; a couple of frames after hide() is enough
        GLib.timeout_add(120, lambda: self._launch(kind))

    @staticmethod
    def _launch(kind: str) -> bool:
        subprocess.Popen(capture_command(kind), shell=True)
        return False

    def reveal(self) -> None:
        self._highlight(None)  # open with nothing preselected
        self.show()
