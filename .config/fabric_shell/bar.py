import os
from fabric import Application
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.centerbox import CenterBox
from fabric.widgets.datetime import DateTime
from fabric.widgets.label import Label
from fabric.utils.helpers import (
    FormattedString,
    truncate,
    exec_shell_command,
    monitor_file,
)
from fabric.core.fabricator import Fabricator
from fabric.system_tray.widgets import SystemTray
from fabric.hyprland.widgets import HyprlandWorkspaces, HyprlandActiveWindow

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

# Monitor that gets the system tray (Hyprland connector name, e.g. "eDP-1", "HDMI-A-1")
MAIN_MONITOR = "eDP-1"


def _vol_icon(volume: int, muted: bool) -> str:
    if muted or volume == 0:
        return "󰝟"
    if volume < 34:
        return "󰕿"
    if volume < 67:
        return "󰖀"
    return "󰕾"


def _bat_icon(percent: int, charging: bool) -> str:
    if charging:
        return "󰂄"
    if percent > 90:
        return "󰁹"
    if percent > 70:
        return "󰂀"
    if percent > 50:
        return "󰁾"
    if percent > 30:
        return "󰁼"
    if percent > 10:
        return "󰁺"
    return "󰂃"


def _find_battery() -> str | None:
    for i in range(5):
        p = f"/sys/class/power_supply/BAT{i}"
        if os.path.exists(p):
            return p
    return None


BAT_PATH = _find_battery()


class StatusBar(Window):
    def __init__(self, show_tray: bool = True, **kwargs):
        super().__init__(
            layer="top", anchor="left top right", exclusivity="auto", **kwargs
        )
        self.add_style_class("window")

        # Active window
        self.active_window = HyprlandActiveWindow(
            FormattedString(
                "{'Chit' if not win_title else truncate(win_title, 20)}",
                truncate=truncate,
            )
        )
        self.active_window.add_style_class("module")

        # Workspaces
        self.workspaces = HyprlandWorkspaces()
        self.workspaces.add_style_class("module")
        self.workspaces.add_style_class("workspaces")

        # Clock
        self.date_time = DateTime()
        self.date_time.add_style_class("module")

        # System tray — only on the designated main monitor
        if show_tray:
            self.tray = SystemTray(icon_size=15)
            self.tray.add_style_class("module")
            self.tray.add_style_class("tray")
            self._tray_fab = Fabricator(
                poll_from=self._poll_tray,
                interval=3000,  # find a better way, can be resource intensive
            )  # Checks if tray has items, hides if it doesnt
        else:
            self.tray = None

        # Volume — polled via wpctl every 0.3 s
        self.volume_label = Label("󰕾 --%")
        self.volume_label.add_style_class("module")
        self._vol_fab = Fabricator(poll_from=self._poll_volume, interval=300)
        self._vol_fab.connect("changed", lambda _f, v: self.volume_label.set_label(v))

        # CPU temperature — polled every 3 s
        self.cpu_label = Label(" --°C")
        self.cpu_label.add_style_class("module")
        self._cpu_fab = Fabricator(poll_from=self._poll_cpu, interval=3000)
        self._cpu_fab.connect("changed", lambda _f, v: self.cpu_label.set_label(v))
        self._cpu_fab.start()

        # Battery — polled every 30 s
        self.bat_label = Label("󰁹 --%")
        self.bat_label.add_style_class("module")
        if BAT_PATH:
            # temp_fab = Fabricator(poll_from=self._poll_battery)
            self._bat_fab = Fabricator(
                poll_from=self._poll_battery,
                interval=30000,
            )
            self._bat_fab.connect("changed", lambda _f, v: self.bat_label.set_label(v))
            self._bat_fab.start()

        end = [self.tray] if self.tray else []
        end += [self.volume_label, self.cpu_label, self.bat_label, self.date_time]
        self.bar_content = CenterBox(
            start_children=[self.active_window],
            center_children=[self.workspaces],
            end_children=end,
        )
        self.bar_content.add_style_class("content")
        self.children = self.bar_content

    def _poll_tray(self, _fab):
        if self.tray.children == []:
            self.tray.set_style("opacity:0;")
        else:
            self.tray.set_style("opacity: 100;")
        # print(self.tray.get_signal_ids(), self.tray.get_signal_names())

    def _poll_volume(self, _fab) -> str:
        out = exec_shell_command("wpctl get-volume @DEFAULT_AUDIO_SINK@")
        if out is False:
            return "󰝟 --%"
        muted = "[MUTED]" in out
        try:
            vol = round(float(out.split()[1]) * 100)
        except (IndexError, ValueError):
            return "󰝟 --%"
        icon = _vol_icon(vol, muted)
        return f"{icon} Muted" if muted else f"{icon} {vol}%"

    def _poll_cpu(self, _fab) -> str:
        out = exec_shell_command(
            "awk '{printf \"%.0f\", $1/1000}' /sys/class/thermal/thermal_zone0/temp"
        )
        return f" {out.strip()}°C" if out is not False else " --°C"

    def _poll_battery(self, _fab) -> str:

        cap = exec_shell_command(f"cat {BAT_PATH}/capacity")
        sta = exec_shell_command(f"cat {BAT_PATH}/status")
        if cap is not False and sta is not False:
            pct = int(cap.strip())
            charging = sta.strip().lower() == "charging"
            return f"{_bat_icon(pct, charging)} {pct}%"
        return "󰂃 --%"


def load_css(app: Application) -> None:
    # fabric_color.css contains --wallpaper: url(...) which GTK @define-color
    # rejects as an invalid color value — strip those lines before compiling.
    try:
        with open(os.path.join(CSS_DIR, "colors-fabric.css")) as f:
            color_css = "\n".join(
                line for line in f.read().splitlines() if "url(" not in line
            )
    except FileNotFoundError:
        color_css = ""

    with open(os.path.join(CSS_DIR, "bar.css")) as f:
        bar_css = f.read()

    app.set_stylesheet_from_string(
        color_css + "\n" + bar_css,
        base_path=CSS_DIR,
    )


if __name__ == "__main__":
    import gi
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
    display = Gdk.Display.get_default()
    n_monitors = display.get_n_monitors()
    bars = [
        StatusBar(monitor=i, show_tray=(display.get_monitor(i).get_model() == MAIN_MONITOR))
        for i in range(n_monitors)
    ]
    app = Application("bar", *bars)
    load_css(app)
    # Reload all styles whenever pywal regenerates colors-fabric.css
    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )
    app.run()
