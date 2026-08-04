#!/usr/bin/env python3
"""Status bar — one floating island row per monitor."""

import os

from fabric import Application
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.centerbox import CenterBox
from fabric.widgets.datetime import DateTime
from fabric.widgets.label import Label
from fabric.core.fabricator import Fabricator
from fabric.system_tray.widgets import SystemTray
from fabric.hyprland.widgets import HyprlandWorkspaces, HyprlandActiveWindow
from fabric.utils.helpers import FormattedString, truncate, exec_shell_command

import common

# 0-based index of the monitor that gets the system tray (eDP-1 is index 0)
TRAY_MONITOR = 0

# (upper bound, glyph) — first match wins, last entry catches everything
VOLUME_ICONS = ((34, "󰕿"), (67, "󰖀"), (10_000, "󰕾"))
BATTERY_ICONS = ((11, "󰂃"), (31, "󰁺"), (51, "󰁼"), (71, "󰁾"), (91, "󰂀"), (10_000, "󰁹"))
MUTED_ICON = "󰝟"


def _pick(icons, value: int) -> str:
    return next(icon for threshold, icon in icons if value < threshold)


def _find_battery() -> str | None:
    for index in range(5):
        path = f"/sys/class/power_supply/BAT{index}"
        if os.path.exists(path):
            return path
    return None


BATTERY = _find_battery()


class StatusBar(Window):
    def __init__(self, show_tray: bool = True, **kwargs):
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

        # the clock island is accent-tinted — it anchors the eye
        clock = DateTime()
        clock.add_style_class("island clock-island")

        resources = Box(
            orientation="horizontal",
            spacing=0,
            style_classes="island resources-island",
            children=[
                self._meter("󰕾 --%", self._poll_volume, 300),
                self._divider(),
                self._meter(" --°C", self._poll_cpu, 3000),
                self._divider(),
                self._meter(
                    "󰁹 --%", self._poll_battery, 30000, enabled=BATTERY is not None
                ),
            ],
        )

        end = [resources, clock]
        if show_tray:
            self._tray = SystemTray(icon_size=15)
            self._tray.add_style_class("island tray-island")
            # an empty tray still reserves its island, so fade it out instead
            self._tray_poll = Fabricator(poll_from=self._poll_tray, interval=3000)
            end.insert(0, self._tray)

        content = CenterBox(
            start_children=[title],
            center_children=[workspaces],
            end_children=end,
        )
        content.add_style_class("bar-content")
        self.children = content

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

    def _poll_tray(self, _fabricator) -> None:
        self._tray.set_style(
            "opacity:0;" if self._tray.children == [] else "opacity: 100;"
        )

    def _poll_volume(self, _fabricator) -> str:
        out = exec_shell_command("wpctl get-volume @DEFAULT_AUDIO_SINK@")
        if out is False:
            return f"{MUTED_ICON} --%"
        try:
            volume = round(float(out.split()[1]) * 100)
        except (IndexError, ValueError):
            return f"{MUTED_ICON} --%"
        if "[MUTED]" in out:
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
        capacity = exec_shell_command(f"cat {BATTERY}/capacity")
        status = exec_shell_command(f"cat {BATTERY}/status")
        if capacity is False or status is False:
            return "󰂃 --%"
        percent = int(capacity.strip())
        if status.strip().lower() == "charging":
            return f"󰂄 {percent}%"
        return f"{_pick(BATTERY_ICONS, percent)} {percent}%"


if __name__ == "__main__":
    from gi.repository import Gdk  # type: ignore

    monitors = Gdk.Display.get_default().get_n_monitors()
    bars = [
        StatusBar(monitor=index, show_tray=(index == TRAY_MONITOR))
        for index in range(monitors)
    ]
    app = Application("bar", *bars)
    common.style_application(app, "bar.css")
    app.run()
