"""Power menu — full-screen scrim with lock / logout / restart / shutdown cards."""

import subprocess

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import Overlay

from gi.repository import Gdk, GtkLayerShell  # type: ignore

# label, glyph, command, extra style class
ACTIONS = [
    ("Lock", "󰍁", ["loginctl", "lock-session"], ""),
    ("Logout", "󰍃", 'hyprctl dispatch "hl.dsp.exit()"', ""),
    ("Restart", "󰑙", ["systemctl", "reboot"], ""),
    ("Shutdown", "󰐥", ["systemctl", "poweroff"], "shutdown"),
]


class PowerMenu(Overlay):
    def __init__(self):
        # anchored on all four edges so the scrim covers the whole screen
        # instead of shrinking to the size of the cards
        super().__init__(
            title="fabric-powermenu",
            layer="overlay",
            anchor="left top right bottom",
            keyboard_mode="exclusive",
        )
        # -1 ignores other windows' exclusive zones so the scrim also covers
        # the bar; fabric's exclusivity="none" maps to zone 0, which leaves
        # the bar's reserved strip uncovered
        GtkLayerShell.set_exclusive_zone(self, -1)
        self.add_style_class("powermenu-window")

        self._cards: list[Box] = []
        self._selected: int | None = None

        row = Box(
            orientation="horizontal",
            spacing=16,
            h_align="center",
            v_align="center",
            style_classes="powermenu-row",
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
            style_classes="powermenu-root",
            children=[
                row,
                Label(
                    label="↑↓←→ navigate · ↵ confirm · esc cancel",
                    style_classes="powermenu-hint",
                    h_align="center",
                ),
            ],
        )
        self.show_all()
        self.hide()

    def _build(self, index: int, label: str, icon: str, _cmd, extra: str) -> Button:
        card = Box(
            orientation="vertical",
            spacing=10,
            h_align="center",
            v_align="center",
            style_classes=f"powermenu-card {extra}".strip(),
            children=[
                Label(label=icon, style_classes="powermenu-icon", h_align="center"),
                Label(label=label, style_classes="powermenu-label", h_align="center"),
            ],
        )
        self._cards.append(card)
        button = Button(child=card, style_classes="powermenu-btn")
        button.connect("clicked", lambda *_: self._run(index))
        return button

    # ── selection ───────────────────────────────────────────────────────────

    def _highlight(self, index: int | None) -> None:
        for position, card in enumerate(self._cards):
            if position == index:
                card.add_style_class("powermenu-selected")
            else:
                card.remove_style_class("powermenu-selected")
        self._selected = index

    def _step(self, delta: int) -> None:
        self._highlight(
            0
            if self._selected is None
            else (self._selected + delta) % len(self._cards)
        )

    def on_key(self, event) -> bool:
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            # only ever fire on an explicit selection — never guess a power action
            if self._selected is not None:
                self._run(self._selected)
        elif event.keyval in (Gdk.KEY_Left, Gdk.KEY_Up):
            self._step(-1)
        elif event.keyval in (Gdk.KEY_Right, Gdk.KEY_Down):
            self._step(1)
        else:
            return False
        return True

    # ── actions ─────────────────────────────────────────────────────────────

    def _run(self, index: int) -> None:
        cmd = ACTIONS[index][2]
        self.dismiss()
        subprocess.Popen(cmd, shell=isinstance(cmd, str))

    def reveal(self) -> None:
        self._highlight(None)  # open with nothing preselected
        self.show()
