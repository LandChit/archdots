"""Calendar popup — drops out of the clock island at the right of the bar.

Named calendar_popup rather than calendar so it cannot shadow the standard
library's `calendar` module, which fabric's dependencies import.
"""

from fabric.widgets.box import Box
from fabric.widgets.label import Label

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import Overlay

from gi.repository import GLib, Gtk  # type: ignore

ANIM_MS = 180

# clears the bar: 6px top margin + the island row + a little breathing room.
# The right margin lines the card up with the bar's own 14px edge.
MARGIN = "52px 14px 0px 0px"


class CalendarPopup(Overlay):
    """Month grid under the clock, opened by clicking the clock island."""

    def __init__(self):
        super().__init__(
            title="fabric-calendar",
            layer="top",
            anchor="top right",
            margin=MARGIN,
            keyboard_mode="on-demand",
        )
        self.add_style_class("calendar-window")

        self._anim_src: int | None = None

        self._weekday = Label(
            label="", style_classes="calendar-weekday", h_align="start"
        )
        self._date = Label(label="", style_classes="calendar-date", h_align="start")

        # Gtk.Calendar draws the whole month grid itself; css/calendar.css
        # restyles its header, day names and selection to match the shell
        self._calendar = Gtk.Calendar(
            show_day_names=True, show_heading=True, no_month_change=False
        )
        self._calendar.get_style_context().add_class("calendar-grid")

        self._card = Box(
            orientation="vertical",
            spacing=2,
            style_classes="calendar-card",
            children=[self._weekday, self._date, self._calendar],
        )

        self.children = Box(
            orientation="vertical",
            style_classes="calendar-root",
            children=[self._card],
        )
        self.show_all()
        self.hide()

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self) -> None:
        self._cancel_anim()
        self._go_to_today()
        # start off-screen, then drop the class one frame later so GTK has a
        # state to transition *from* — otherwise the animation never plays
        self.add_style_class("anim-out")
        self.show()
        self._anim_src = GLib.timeout_add(16, self._settle)

    def dismiss(self) -> None:
        self._cancel_anim()
        self.add_style_class("anim-out")
        self._anim_src = GLib.timeout_add(ANIM_MS, self._finish_dismiss)

    # ── internals ───────────────────────────────────────────────────────────

    def _go_to_today(self) -> None:
        """Reset to today — a month browsed last time should not persist."""
        now = GLib.DateTime.new_now_local()
        self._weekday.set_label(now.format("%A"))
        self._date.set_label(now.format("%-d %B %Y"))
        # Set the three properties rather than stepping through select_month()
        # and select_day(): those leave the widget on an intermediate date
        # between the two calls, which once rendered the following year.
        # Gtk.Calendar counts months from 0, unlike every other date API here.
        self._calendar.set_property("year", now.get_year())
        self._calendar.set_property("month", now.get_month() - 1)
        self._calendar.set_property("day", now.get_day_of_month())

    def _cancel_anim(self) -> None:
        if self._anim_src is not None:
            GLib.source_remove(self._anim_src)
            self._anim_src = None

    def _settle(self) -> bool:
        self._anim_src = None
        self.remove_style_class("anim-out")
        return False

    def _finish_dismiss(self) -> bool:
        self._anim_src = None
        self.hide()
        return False
