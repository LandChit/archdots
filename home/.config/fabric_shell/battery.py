"""Low-battery warning — a centred dialog asking you to plug the charger in.

Unlike the other overlays this one is never opened from a keybind: it polls
the battery and reveals itself. Dismissing it snoozes the current level rather
than silencing it, so a warning waved away comes back while the charge falls.
"""

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import Overlay, battery_state, battery_time, find_battery

from gi.repository import GLib  # type: ignore

POLL_SECONDS = 30
SNOOZE_SECONDS = 300
# a low warning gets out of the way on its own; a critical one has to be seen
AUTO_DISMISS_MS = 20_000

# (upper bound, style class, glyph, title, body) — first match wins
LEVELS = [
    (10, "critical", "󰂃", "Battery critical", "Plug in now — the session is about to end."),
    (20, "low", "󰁺", "Battery low", "Time to charge."),
]

BATTERY = find_battery()

# (upper bound, glyph) for the neutral card — first match wins, mirrors bar.py
STATUS_ICONS = ((11, "󰂃"), (31, "󰁺"), (51, "󰁼"), (71, "󰁾"), (91, "󰂀"), (10_000, "󰁹"))


def _icon_for(percent: int) -> str:
    return next(icon for threshold, icon in STATUS_ICONS if percent < threshold)


def _level(percent: int) -> int | None:
    """Index into LEVELS for `percent`, or None while the charge is healthy."""
    for index, entry in enumerate(LEVELS):
        if percent <= entry[0]:
            return index
    return None


class BatteryWarning(Overlay):
    """Centred card revealed once the charge crosses a warning level."""

    # the daemon closes every other overlay when one opens; this is a
    # notification rather than a mode, so it stays out of that exchange
    exclusive = False

    def __init__(self):
        super().__init__(
            title="fabric-battery",
            layer="overlay",
            # no anchor — layer shell then centres the window on the output
            keyboard_mode="on-demand",
        )
        self.add_style_class("battery-window")

        self._shown_level: int | None = None
        self._snooze_until = 0
        self._auto_src: int | None = None

        self._icon = Label(label="󰁺", style_classes="battery-icon", v_align="center")
        self._title = Label(
            label="Battery low", style_classes="battery-title", h_align="start"
        )
        self._body = Label(
            label="Time to charge.", style_classes="battery-body", h_align="start"
        )

        dismiss = Button(
            child=Label(label="Dismiss", style_classes="battery-btn-label"),
            style_classes="battery-btn",
            v_align="center",
        )
        dismiss.connect("clicked", lambda *_: self.dismiss())

        self._card = Box(
            orientation="horizontal",
            spacing=16,
            style_classes="battery-card low",
            children=[
                self._icon,
                Box(
                    orientation="vertical",
                    spacing=4,
                    v_align="center",
                    h_expand=True,
                    children=[self._title, self._body],
                ),
                dismiss,
            ],
        )

        self.children = Box(
            orientation="vertical",
            h_align="center",
            v_align="center",
            style_classes="battery-root",
            children=[self._card],
        )
        self.show_all()
        self.hide()

        if BATTERY is not None:
            GLib.timeout_add_seconds(POLL_SECONDS, self._poll)

    # ── watching ────────────────────────────────────────────────────────────

    def _poll(self) -> bool:
        state = battery_state(BATTERY)
        if state is None:
            return True
        percent, status = state

        if status != "discharging":
            # back on mains — forget the warning so unplugging warns afresh
            self._reset()
            if self.get_visible():
                self.hide()
            return True

        level = _level(percent)
        if level is None:
            self._reset()
            return True

        if self.get_visible():
            self._fill(level, percent)  # keep the reading current
            return True

        # a drop to a worse level always shows; the same level waits out its snooze
        dropped = self._shown_level is None or level < self._shown_level
        if dropped or GLib.get_monotonic_time() >= self._snooze_until:
            self._shown_level = level
            self._fill(level, percent)
            self.reveal()
        return True

    def _reset(self) -> None:
        self._shown_level = None
        self._snooze_until = 0

    def _fill(self, level: int, percent: int) -> None:
        _, style, glyph, title, body = LEVELS[level]
        for name in ("low", "critical"):
            self._card.remove_style_class(name)
        self._card.add_style_class(style)
        self._icon.set_label(glyph)
        self._title.set_label(f"{title} · {percent}%")
        self._body.set_label(body + self._time_suffix())

    def _fill_status(self) -> None:
        """Neutral card for when the bar opens this by hand, with no warning."""
        for name in ("low", "critical"):
            self._card.remove_style_class(name)

        path = BATTERY
        state = battery_state(path) if path is not None else None
        if path is None or state is None:
            self._icon.set_label("󰂑")
            self._title.set_label("No battery")
            self._body.set_label("This machine runs on mains power.")
            return

        percent, status = state
        charging = status == "charging"
        self._icon.set_label("󰂄" if charging else _icon_for(percent))
        self._title.set_label(f"Battery · {percent}%")

        remaining = battery_time(path)
        if remaining is None:
            self._body.set_label(f"{status.capitalize()}.")
        elif charging:
            self._body.set_label(f"Charging — {remaining} until full.")
        else:
            self._body.set_label(f"{remaining} remaining.")

    @staticmethod
    def _time_suffix() -> str:
        remaining = battery_time(BATTERY) if BATTERY is not None else None
        return f" {remaining} left." if remaining else ""

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self) -> None:
        self._cancel_auto()
        # opened from the bar rather than by the watcher — the card would
        # otherwise still be showing whatever warning was last displayed
        if self._shown_level is None:
            self._fill_status()
        self.show()
        if self._shown_level is None or LEVELS[self._shown_level][1] != "critical":
            self._auto_src = GLib.timeout_add(AUTO_DISMISS_MS, self._on_timeout)

    def dismiss(self) -> None:
        self._cancel_auto()
        self._snooze_until = GLib.get_monotonic_time() + SNOOZE_SECONDS * 1_000_000
        self.hide()

    def _cancel_auto(self) -> None:
        if self._auto_src is not None:
            GLib.source_remove(self._auto_src)
            self._auto_src = None

    def _on_timeout(self) -> bool:
        self._auto_src = None
        self.dismiss()
        return False