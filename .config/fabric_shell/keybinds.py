"""Keybind cheatsheet — reads the live binds out of Hyprland.

Nothing here is hardcoded: it asks `hyprctl binds -j` every time it opens, so
binds added in hypr/config/custom/keybind.lua appear without touching this file.

Naming them is the awkward part. Under the Lua config provider every bind is
registered as a `__lua` callback, so hyprctl reports `dispatcher: "__lua"` with
an opaque index — the key combo is knowable, the action is not. The one field
that survives is `description`, set per bind with `desc` in Lua:

    hl.bind(mainMod .. "+ B", hl.dsp.exec_cmd(browser), { desc = "Launch: Browser" })

By convention a description reads "Group: Label"; the group becomes a heading
here. Binds without a description are still listed, under "Undescribed", so a
new bind shows up immediately even before it is named.
"""

import json

from fabric.widgets.box import Box
from fabric.widgets.label import Label
from fabric.utils.helpers import exec_shell_command

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import Overlay, make_scroller

from gi.repository import Gdk, GtkLayerShell  # type: ignore

COLUMNS = 3
COLUMN_WIDTH = 380
BODY_HEIGHT = 760

UNDESCRIBED = "Undescribed"

# Hyprland's modmask bits, in the order they should read on screen
MODS = (
    (64, "SUPER"),
    (4, "CTRL"),
    (8, "ALT"),
    (1, "SHIFT"),
)

# Keys whose raw name is unreadable, or just ugly on a cheatsheet
KEY_NAMES = {
    "RETURN": "Enter",
    "KP_ENTER": "Enter",
    "ESCAPE": "Esc",
    "PRINT": "PrtSc",
    "SLASH": "/",
    "PERIOD": ".",
    "COMMA": ",",
    "SPACE": "Space",
    "TAB": "Tab",
    "BACKSPACE": "Backspace",
    "DELETE": "Del",
    "left": "←",
    "right": "→",
    "up": "↑",
    "down": "↓",
    "mouse:272": "Left click",
    "mouse:273": "Right click",
    "mouse_up": "Scroll up",
    "mouse_down": "Scroll down",
}

# XF86 media keys, which otherwise read like XF86AudioRaiseVolume
XF86_NAMES = {
    "AudioRaiseVolume": "Vol +",
    "AudioLowerVolume": "Vol −",
    "AudioMute": "Mute",
    "AudioMicMute": "Mic mute",
    "MonBrightnessUp": "Bright +",
    "MonBrightnessDown": "Bright −",
    "AudioNext": "Next",
    "AudioPrev": "Prev",
    "AudioPlay": "Play",
    "AudioPause": "Pause",
}


def pretty_key(key: str) -> str:
    if key in KEY_NAMES:
        return KEY_NAMES[key]
    if key.startswith("XF86"):
        return XF86_NAMES.get(key[4:], key[4:])
    return key.upper() if len(key) == 1 else key


def combo(bind: dict) -> list[str]:
    """A bind's modifiers and key, as display tokens."""
    mask = bind.get("modmask", 0)
    tokens = [name for bit, name in MODS if mask & bit]
    tokens.append(pretty_key(bind.get("key", "")))
    return tokens


ARROWS = ("←", "→", "↑", "↓")


def _collapse(combos: list[list[str]]) -> list[list[str]]:
    """Fold binds that share a description into one readable row.

    Ten workspace binds share one description, and printing ten near-identical
    rows buries everything else on the sheet. Only two shapes are folded, both
    of which stay honest about which keys are bound:

        digits  SUPER+1 … SUPER+0   -> SUPER 1…0
        arrows  SUPER+← … SUPER+↓   -> SUPER ←→↑↓

    Anything else is left as separate combos. An earlier version folded *any*
    single-character key into a range, which turned the four focus binds into
    the nonsense "←…↓".
    """
    if len(combos) < 3:
        return combos

    mods = [c[:-1] for c in combos]
    if any(m != mods[0] for m in mods):
        return combos

    keys = [c[-1] for c in combos]
    if all(k.isdigit() for k in keys):
        return [mods[0] + [f"{keys[0]}…{keys[-1]}"]]
    if all(k in ARROWS for k in keys):
        return [mods[0] + ["".join(keys)]]
    return combos


def grouped_binds() -> tuple[list[tuple[str, list[tuple[str, list[list[str]]]]]], int]:
    """([(group, [(label, [combo, ...]), ...]), ...], total) from Hyprland.

    The total counts real binds, not rows: collapsing the ten workspace binds
    into one line must not make the sheet claim there are fewer binds.
    """
    out = exec_shell_command("hyprctl binds -j")
    if out is False:
        return [], 0
    try:
        binds = json.loads(out)
    except ValueError:
        return [], 0

    groups: dict[str, dict[str, list[list[str]]]] = {}
    order: list[str] = []
    total = 0

    for bind in binds:
        if bind.get("submap"):
            continue  # submaps are modal; they would need their own sheet

        description = (bind.get("description") or "").strip()
        if description:
            group, _, label = description.partition(":")
            group, label = group.strip(), label.strip()
            if not label:  # a description with no "Group:" prefix
                group, label = "Other", group
        else:
            group, label = UNDESCRIBED, "—"

        if group not in groups:
            groups[group] = {}
            order.append(group)
        # dict keeps insertion order, so rows stay in the order they were bound
        groups[group].setdefault(label, []).append(combo(bind))
        total += 1

    # Undescribed last: it is a prompt to add a desc, not a feature
    order.sort(key=lambda name: name == UNDESCRIBED)
    return [
        (name, [(label, _collapse(c)) for label, c in groups[name].items()])
        for name in order
    ], total


class KeybindsOverlay(Overlay):
    """Full-screen cheatsheet of every bind Hyprland currently has."""

    def __init__(self):
        # anchored on all four edges so the scrim covers the whole screen
        super().__init__(
            title="fabric-keybinds",
            layer="overlay",
            anchor="left top right bottom",
            keyboard_mode="exclusive",
        )
        # -1 ignores other windows' exclusive zones so the scrim also covers
        # the bar; fabric's exclusivity="none" maps to zone 0
        GtkLayerShell.set_exclusive_zone(self, -1)
        self.add_style_class("keys-window")

        self._columns = Box(
            orientation="horizontal",
            spacing=14,
            h_align="center",
            v_align="start",
            style_classes="keys-columns",
        )
        self._count = Label(label="", style_classes="keys-hint", h_align="center")

        # no h_align here: make_scroller already sets one, and passing it again
        # is a duplicate keyword argument
        scroller = make_scroller(
            self._columns, COLUMNS * COLUMN_WIDTH + 40, BODY_HEIGHT
        )

        self.children = Box(
            orientation="vertical",
            spacing=14,
            h_align="center",
            v_align="center",
            style_classes="keys-root",
            children=[
                Label(label="Keybinds", style_classes="keys-title", h_align="center"),
                scroller,
                self._count,
            ],
        )
        self.show_all()
        self.hide()

    # ── contents ────────────────────────────────────────────────────────────

    def _rebuild(self) -> None:
        for child in self._columns.get_children():
            self._columns.remove(child)

        groups, total = grouped_binds()
        columns = [
            Box(orientation="vertical", spacing=12, v_align="start")
            for _ in range(COLUMNS)
        ]

        # fill the shortest column each time, so one long group does not leave
        # a column towering over the others
        heights = [0] * COLUMNS
        for name, rows in groups:
            index = heights.index(min(heights))
            columns[index].add(self._group(name, rows))
            heights[index] += len(rows) + 2  # rows, plus the heading's weight

        for column in columns:
            self._columns.add(column)
        self._columns.show_all()

        self._count.set_label(f"{total} binds · read live from Hyprland · esc to close")

    def _group(self, name: str, rows: list[tuple[str, list[list[str]]]]) -> Box:
        card = Box(
            orientation="vertical",
            spacing=6,
            style_classes="keys-group"
            + (" undescribed" if name == UNDESCRIBED else ""),
            h_expand=True,
        )
        card.add(Label(label=name, style_classes="keys-group-title", h_align="start"))
        for label, combos in rows:
            card.add(self._row(label, combos))
        return card

    def _row(self, label: str, combos: list[list[str]]) -> Box:
        keys = Box(orientation="horizontal", spacing=4, h_align="end")
        for index, tokens in enumerate(combos):
            if index:
                keys.add(Label(label="/", style_classes="keys-or"))
            for position, token in enumerate(tokens):
                if position:
                    keys.add(Label(label="+", style_classes="keys-plus"))
                keys.add(Label(label=token, style_classes="keys-chip"))

        return Box(
            orientation="horizontal",
            spacing=10,
            h_expand=True,
            style_classes="keys-row",
            children=[
                Label(
                    label=label,
                    style_classes="keys-label",
                    h_align="start",
                    x_align=0.0,
                ),
                Box(h_expand=True),
                keys,
            ],
        )

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self) -> None:
        self._rebuild()  # always current, including custom/keybind.lua
        self.show()

    def on_key(self, event) -> bool:
        # Escape is handled by Overlay; the opening chord arrives here as SLASH
        if event.keyval in (Gdk.KEY_slash, Gdk.KEY_question):
            self.dismiss()
            return True
        return False
