#!/usr/bin/env python3
"""Status bar — one floating island row per monitor."""

from fabric import Application
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.centerbox import CenterBox
from fabric.widgets.datetime import DateTime
from fabric.widgets.eventbox import EventBox
from fabric.widgets.label import Label
from fabric.core.fabricator import Fabricator
from fabric.hyprland.widgets import HyprlandWorkspaces, HyprlandActiveWindow
from fabric.utils.helpers import (
    FormattedString,
    truncate,
    exec_shell_command,
    exec_shell_command_async,
)

import common
import media
import windows

from gi.repository import Gdk, GLib  # type: ignore

# safety net behind the pactl subscription, not the primary source of updates
VOLUME_FALLBACK_SECONDS = 10

# percentage points per scroll notch over the volume meter
VOLUME_STEP = 5

# how much of "title · artist" the media island shows before truncating
MEDIA_TITLE_CHARS = 28

# a single format: see the clock in __init__ for why it must stay single
CLOCK_FORMAT = "%I:%M %p"

# safety net behind the playerctl subscription, as with the volume meter
MEDIA_FALLBACK_SECONDS = 10

# (upper bound, glyph) — first match wins, last entry catches everything
VOLUME_ICONS = ((34, "󰕿"), (67, "󰖀"), (10_000, "󰕾"))
BATTERY_ICONS = ((11, "󰂃"), (31, "󰁺"), (51, "󰁼"), (71, "󰁾"), (91, "󰂀"), (10_000, "󰁹"))
MUTED_ICON = "󰝟"


def _pick(icons, value: int) -> str:
    return next(icon for threshold, icon in icons if value < threshold)


BATTERY = common.find_battery()


class StatusBar(Window):
    def __init__(self, **kwargs):
        super().__init__(
            title="fabric-bar",
            layer="top",
            anchor="left top right",
            margin="6px 14px 0px 14px",
            exclusivity="auto",
            **kwargs,
        )
        self.add_style_class("bar-window")

        title = HyprlandActiveWindow(
            FormattedString(
                "{'Chit' if not win_title else truncate(win_title, 20)}",
                truncate=truncate,
            )
        )
        title.add_style_class("island title-island")

        workspaces = HyprlandWorkspaces()
        workspaces.add_style_class("island workspaces-island")

        # the clock island is accent-tinted — it anchors the eye.
        # One formatter on purpose: DateTime defaults to three and *cycles them
        # on click and scroll*, so clicking the clock turned it into "Wednesday"
        # and then "08-13-2026". With a single format its own handler is a
        # no-op, and the click is free to mean "open the calendar".
        clock = DateTime(formatters=CLOCK_FORMAT)
        clock.add_style_class("island clock-island")
        clock.connect("button-press-event", self._on_clock_click)
        clock.connect("realize", self._set_hand_cursor)

        battery = self._meter(
            "󰁹 --%", self._poll_battery, 30000, enabled=BATTERY is not None
        )

        resources = Box(
            orientation="horizontal",
            spacing=0,
            style_classes="island resources-island",
            children=[
                self._clickable(
                    self._volume_meter(),
                    on_click=self._on_volume_click,
                    on_scroll=self._on_volume_scroll,
                ),
                self._divider(),
                self._meter(" --°C", self._poll_cpu, 3000),
                self._divider(),
                self._clickable(battery, on_click=self._on_battery_click),
            ],
        )

        # the island hides itself when no player is running, so the bar does
        # not carry an empty gap around
        self._media = media.MediaControls(MEDIA_TITLE_CHARS, "island media-island")
        self._media.set_state(media.current())
        self._media_watch = media.watch(self._media.set_state)
        # `--follow` says nothing when a player quits, so the island would keep
        # showing a track that stopped existing; this re-reads occasionally
        self._media_fallback = GLib.timeout_add_seconds(
            MEDIA_FALLBACK_SECONDS, self._refresh_media
        )

        # the system tray lives in the control centre now — its icons often
        # fail to resolve in the GTK icon theme, which left an island that was
        # either blank or invisible taking up bar width
        end = [self._media, resources, clock]

        # workspaces sit left of the title rather than in the centre: on a
        # narrow screen the centre slot squeezes everything else, and the two
        # left-hand islands read as one group anyway
        content = CenterBox(
            start_children=[workspaces, title],
            end_children=end,
        )
        content.add_style_class("bar-content")
        self.children = content

    # ── pointer ─────────────────────────────────────────────────────────────

    @staticmethod
    def _set_hand_cursor(widget) -> None:
        """Point at a widget that does something. The Gdk window only exists
        once the widget is realized, so this is a "realize" handler."""
        window = widget.get_window()
        if window is not None:
            window.set_cursor(Gdk.Cursor.new_from_name(widget.get_display(), "pointer"))

    @classmethod
    def _clickable(cls, child, on_click=None, on_scroll=None) -> EventBox:
        """Wrap a meter so it answers the pointer, with a hand cursor to say so.

        For a plain Label. A Button (the clock) already takes clicks itself and
        is wired directly rather than wrapped.
        """
        events = ["button-press"]
        if on_scroll is not None:
            # touchpads send smooth deltas, mice send discrete notches
            events += ["scroll", "smooth-scroll"]

        box = EventBox(events=events, child=child, style_classes="island-hot")
        if on_click is not None:
            box.connect("button-press-event", on_click)
        if on_scroll is not None:
            box.connect("scroll-event", on_scroll)

        box.connect("realize", cls._set_hand_cursor)
        return box

    def _on_volume_scroll(self, _widget, event) -> bool:
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            step = -event.delta_y  # scrolling up gives a negative delta
        elif event.direction == Gdk.ScrollDirection.UP:
            step = 1
        elif event.direction == Gdk.ScrollDirection.DOWN:
            step = -1
        else:
            return True

        if step == 0:
            return True  # a smooth event carrying only horizontal movement
        sign = "+" if step > 0 else "-"
        # -l 2 matches the keybind's ceiling, so both routes agree on the limit
        exec_shell_command_async(
            f"wpctl set-volume -l 2 {common.SINK} {VOLUME_STEP}%{sign}"
        )
        # no manual refresh — the pactl subscription updates the label for us
        return True

    def _on_volume_click(self, _widget, event) -> bool:
        if event.button == 1:
            exec_shell_command_async(f"wpctl set-mute {common.SINK} toggle")
        return True

    @staticmethod
    def _on_battery_click(_widget, event) -> bool:
        if event.button == 1:
            # a failure here means the daemon is down; the bar carries on
            windows.send("show", "battery")
        return True

    @staticmethod
    def _on_clock_click(_widget, event) -> bool:
        if event.button == 1:
            windows.send("toggle", "calendar")
        return True

    def _refresh_media(self) -> bool:
        self._media.set_state(media.current())
        return True  # keep the fallback timer running

    # ── meters ──────────────────────────────────────────────────────────────

    @staticmethod
    def _divider() -> Label:
        divider = Label("·")
        divider.add_style_class("res-divider")
        return divider

    @staticmethod
    def _meter(initial: str, poll, interval: int, enabled: bool = True) -> Label:
        """A label kept up to date by its own polling Fabricator."""
        label = Label(initial)
        if enabled:
            fabricator = Fabricator(poll_from=poll, interval=interval)
            fabricator.connect("changed", lambda _f, value: label.set_label(value))
            fabricator.start()
            # keep a reference alive for as long as the label exists
            label._fabricator = fabricator  # type: ignore[attr-defined]
        return label

    # ── polls ───────────────────────────────────────────────────────────────

    def _volume_meter(self) -> Label:
        """Volume label driven by PipeWire events instead of a fast poll.

        pactl only speaks when something changes, so a slow poll runs alongside
        it purely to recover if the subscription dies with pipewire.
        """
        label = Label(self._volume_text())

        def update(*_) -> bool:
            label.set_label(self._volume_text())
            return True  # keep the fallback timer running

        # both references are kept alive for as long as the label exists — the
        # subscription is a subprocess and is collected the moment it is dropped
        label._audio_watch = common.watch_audio(update)  # type: ignore[attr-defined]
        label._audio_fallback = GLib.timeout_add_seconds(  # type: ignore[attr-defined]
            VOLUME_FALLBACK_SECONDS, update
        )
        return label

    @staticmethod
    def _volume_text() -> str:
        state = common.audio_state()
        if state is None:
            return f"{MUTED_ICON} --%"
        volume, muted = state
        if muted:
            return f"{MUTED_ICON} Muted"
        if volume == 0:
            return f"{MUTED_ICON} 0%"
        return f"{_pick(VOLUME_ICONS, volume)} {volume}%"

    def _poll_cpu(self, _fabricator) -> str:
        out = exec_shell_command(
            "awk '{printf \"%.0f\", $1/1000}' /sys/class/thermal/thermal_zone0/temp"
        )
        return f" {out.strip()}°C" if out is not False else " --°C"

    def _poll_battery(self, _fabricator) -> str:
        state = common.battery_state(BATTERY)
        if state is None:
            return "󰂃 --%"
        percent, status = state
        if status == "charging":
            return f"󰂄 {percent}%"
        return f"{_pick(BATTERY_ICONS, percent)} {percent}%"


if __name__ == "__main__":
    monitors = Gdk.Display.get_default().get_n_monitors()
    bars = [
        StatusBar(monitor=index)
        for index in range(monitors)
    ]
    app = Application("bar", *bars)
    common.style_application(app, "bar.css")
    app.run()
