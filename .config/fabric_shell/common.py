"""Shared plumbing for the fabric shell.

Holds the three things every module needs: stylesheet loading that follows
pywal16, persisted usage counters, and the overlay/panel base classes the
launcher, clipboard, emoji picker and power menu are built on.
"""

import glob
import json
import os

# fabric must be imported before gi.repository — importing it calls
# gi.require_version("Gtk", "3.0"). Touching gi first pulls in GTK 4 instead.
from fabric import Application
from fabric.widgets.box import Box
from fabric.widgets.entry import Entry
from fabric.widgets.scrolledwindow import ScrolledWindow
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.utils.helpers import (
    compile_css,
    exec_shell_command,
    exec_shell_command_async,
    monitor_file,
)

from gi.repository import Gdk, GLib, Gtk  # type: ignore

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")
COLORS_CSS = "colors-fabric.css"


# ── stylesheets ────────────────────────────────────────────────────────────────

def _read(name: str) -> str:
    try:
        with open(os.path.join(CSS_DIR, name), encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def build_css(*sheets: str) -> str:
    """Concatenate the pywal16 palette, the shared base sheet and `sheets`."""
    # pywal16 writes a `url(...)` wallpaper line into the palette that GTK cannot
    # resolve from here, so it is dropped before anything is concatenated.
    colors = "\n".join(
        line for line in _read(COLORS_CSS).splitlines() if "url(" not in line
    )
    return "\n".join([colors, _read("style.css"), *(_read(s) for s in sheets)])


# A Gio.FileMonitor stops watching the moment it is garbage collected, and
# monitor_file() hands its monitor back with nobody holding it. Dropping that
# return value is why a wallpaper change only recoloured the shell after a
# restart: the watch was collected almost immediately. These live for the
# lifetime of the process.
_MONITORS: list = []


def _watch_palette(refresh) -> None:
    _MONITORS.append(monitor_file(os.path.join(CSS_DIR, COLORS_CSS), refresh))


def style_application(app: Application, *sheets: str) -> None:
    """Style `app` from `sheets`, restyling whenever pywal16 rewrites the palette."""
    def refresh(*_):
        app.set_stylesheet_from_string(build_css(*sheets), base_path=CSS_DIR)

    refresh()
    _watch_palette(refresh)


def style_screen(*sheets: str) -> None:
    """Style every window on the screen — the daemon has no single Application."""
    provider: Gtk.CssProvider | None = None

    def refresh(*_):
        nonlocal provider
        screen = Gdk.Screen.get_default()
        if provider is not None:
            Gtk.StyleContext.remove_provider_for_screen(screen, provider)
        provider = Gtk.CssProvider()
        # bytearray + compile_css mirrors fabric's own CSS loading pipeline
        css = compile_css(build_css(*sheets), base_path=CSS_DIR)
        provider.load_from_data(bytearray(css, "utf-8"))
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )

    refresh()
    _watch_palette(refresh)


# ── cpu temperature ────────────────────────────────────────────────────────────

# hwmon drivers that read the CPU die directly, best first. Everything else on a
# machine — nvme, wifi, the battery, the charger — also registers as an hwmon,
# so the driver name is the only thing that identifies the right one.
_HWMON_CPU = ("coretemp", "k10temp", "zenpower", "cpu_thermal")

# Fallback: thermal zones, by `type`. x86_pkg_temp is the package sensor;
# cpu-thermal and soc_thermal are what ARM boards call it; acpitz is a generic
# chassis probe that is merely better than nothing.
_ZONE_TYPES = ("x86_pkg_temp", "cpu-thermal", "soc_thermal", "acpitz")


def find_cpu_temp() -> str | None:
    """Sysfs file holding the CPU temperature in millidegrees, or None.

    thermal_zone0 is *not* portable, which was the original bug here: on this
    laptop zone0 is `acpitz` (a chassis probe) while the CPU package is zone3,
    and elsewhere zone0 is `INT3400`, which reports a constant 20°C. Pick by
    driver name and zone type rather than by index.
    """
    for wanted in _HWMON_CPU:
        for hwmon in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            try:
                with open(os.path.join(hwmon, "name"), encoding="utf-8") as f:
                    if f.read().strip() != wanted:
                        continue
            except OSError:
                continue
            # temp1_input is the package sensor on coretemp; the per-core ones
            # that follow it would each report a different number.
            for entry in ("temp1_input", "temp2_input"):
                path = os.path.join(hwmon, entry)
                if os.path.exists(path):
                    return path

    for wanted in _ZONE_TYPES:
        for zone in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
            try:
                with open(os.path.join(zone, "type"), encoding="utf-8") as f:
                    if f.read().strip() != wanted:
                        continue
            except OSError:
                continue
            path = os.path.join(zone, "temp")
            if os.path.exists(path):
                return path

    return None


def cpu_temp(path: str) -> int | None:
    """Whole degrees Celsius from `path`, or None if it cannot be read."""
    try:
        with open(path, encoding="utf-8") as f:
            return round(int(f.read().strip()) / 1000)
    except (OSError, ValueError):
        return None


# ── battery ────────────────────────────────────────────────────────────────────

def find_battery() -> str | None:
    """Sysfs path of the first battery present, or None on a desktop.

    Matched on `type`, not on the name: BAT0/BAT1 is the usual ACPI naming but
    not a rule — some boards expose CMB0, and the same directory also holds the
    AC adapter and any wireless peripheral that reports a charge level, which a
    name-agnostic glob would otherwise pick up.
    """
    for path in sorted(glob.glob("/sys/class/power_supply/*")):
        try:
            with open(os.path.join(path, "type"), encoding="utf-8") as f:
                if f.read().strip() != "Battery":
                    continue
        except OSError:
            continue
        # Peripherals (mice, headsets) are Batteries too, but carry a scope of
        # Device; the system battery either says System or omits the file.
        try:
            with open(os.path.join(path, "scope"), encoding="utf-8") as f:
                if f.read().strip() == "Device":
                    continue
        except OSError:
            pass
        return path
    return None


def _read_battery(path: str, name: str) -> str | None:
    try:
        with open(os.path.join(path, name), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def battery_state(path: str) -> tuple[int, str] | None:
    """(percent, lowercased status) for the battery at `path`, None if unreadable."""
    capacity = _read_battery(path, "capacity")
    status = _read_battery(path, "status")
    if capacity is None or not capacity.isdigit() or status is None:
        return None
    return int(capacity), status.lower()


def battery_time(path: str) -> str | None:
    """How long until the battery at `path` is empty (or full), as `3h 12m`.

    sysfs reports energy in µWh and draw in µW, so the division is just hours.
    Returns None while idle, on a full battery, or on hardware that reports
    charge/current instead — a missing estimate is a normal state, not an error.
    """
    status = _read_battery(path, "status")
    energy = _read_battery(path, "energy_now")
    power = _read_battery(path, "power_now")
    if status is None or energy is None or power is None:
        return None
    if not energy.isdigit() or not power.isdigit() or int(power) == 0:
        return None

    status = status.lower()
    if status == "charging":
        full = _read_battery(path, "energy_full")
        if full is None or not full.isdigit():
            return None
        remaining = int(full) - int(energy)
    elif status == "discharging":
        remaining = int(energy)
    else:
        return None  # full, or idle on mains — nothing to count down to

    minutes = round(remaining / int(power) * 60)
    if minutes <= 0:
        return None
    return f"{minutes // 60}h {minutes % 60:02d}m" if minutes >= 60 else f"{minutes}m"


# ── audio & backlight ──────────────────────────────────────────────────────────

SINK = "@DEFAULT_AUDIO_SINK@"
SOURCE = "@DEFAULT_AUDIO_SOURCE@"

# how long to wait for the burst of pactl events one change produces to settle
AUDIO_DEBOUNCE_MS = 60


def audio_state(node: str = SINK) -> tuple[int, bool] | None:
    """(percent, muted) for a wpctl node, or None if wpctl cannot be reached.

    wpctl prints `Volume: 0.45` — or `Volume: 0.45 [MUTED]` — as a 0–1 fraction
    that can exceed 1.0 when the sink is boosted past 100%.
    """
    out = exec_shell_command(f"wpctl get-volume {node}")
    if out is False:
        return None
    try:
        percent = round(float(out.split()[1]) * 100)
    except (IndexError, ValueError):
        return None
    return percent, "[MUTED]" in out


def watch_audio(callback) -> object:
    """Call `callback` when PipeWire reports a sink or source change.

    `pactl subscribe` prints one line per event and a single key press produces
    several, so the calls are coalesced into one after a short quiet period.

    Returns the subprocess — the caller has to keep a reference to it, or it is
    collected and the subscription dies with it.
    """
    pending: list[int] = []

    def fire() -> bool:
        pending.clear()
        callback()
        return False

    def on_line(line: str) -> None:
        # every line reads `Event 'change' on sink #52`; server events cover the
        # default sink being switched, which changes what the bar should show
        if not any(word in line for word in ("sink", "source", "server")):
            return
        if pending:
            GLib.source_remove(pending.pop())
        pending.append(GLib.timeout_add(AUDIO_DEBOUNCE_MS, fire))

    process, _stdout = exec_shell_command_async("pactl subscribe", on_line)
    return process


def backlight_state() -> int | None:
    """Backlight brightness as a percent, or None without a backlight device.

    `brightnessctl -m` prints one machine-readable line:
    `amdgpu_bl1,backlight,128,50%,255`.
    """
    out = exec_shell_command("brightnessctl -m")
    if out is False:
        return None
    fields = out.strip().split(",")
    if len(fields) < 4 or not fields[3].rstrip("%").isdigit():
        return None
    return int(fields[3].rstrip("%"))


# ── usage counters ─────────────────────────────────────────────────────────────

class UsageCounts:
    """Persisted pick tallies, used to float frequent entries to the top."""

    def __init__(self, path: str):
        self.path = os.path.expanduser(path)
        self._counts: dict[str, int] = {}
        self.reload()

    def reload(self) -> None:
        try:
            with open(self.path) as f:
                self._counts = json.load(f)
        except (OSError, json.JSONDecodeError):
            self._counts = {}

    def bump(self, key: str) -> None:
        self._counts[key] = self._counts.get(key, 0) + 1
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w") as f:
            json.dump(self._counts, f, indent=2)

    def rank(self, key: str) -> int:
        """Sort key — negated so the most used entry sorts first."""
        return -self._counts.get(key, 0)


# ── keyboard selection ─────────────────────────────────────────────────────────

class Selection:
    """Keyboard selection over a list of widgets, with scroll-into-view.

    Nothing is highlighted until an arrow key is pressed; until then `current`
    resolves to `default_index` so Enter still activates the obvious entry.
    """

    def __init__(self, scroller: ScrolledWindow, style_class: str, target=None):
        self._scroller = scroller
        self._style_class = style_class
        # emoji cells sit inside a FlowBoxChild — that wrapper carries the
        # allocation the scroll maths needs, not the button itself
        self._target = target or (lambda widget: widget)
        self.items: list = []
        self.index: int | None = None
        self.default_index = 0

    def reset(self, items) -> None:
        for item in self.items:
            item.remove_style_class(self._style_class)
        self.items = list(items)
        self.index = None
        self.default_index = 0

    def move(self, delta: int) -> None:
        if self.items:
            self.select(0 if self.index is None else self.index + delta)

    def select(self, index: int) -> None:
        index = max(0, min(index, len(self.items) - 1))
        if self.index is not None:
            self.items[self.index].remove_style_class(self._style_class)
        self.index = index
        item = self.items[index]
        item.add_style_class(self._style_class)
        self._scroll_into_view(item)

    @property
    def current(self):
        if not self.items:
            return None
        return self.items[self.index if self.index is not None else self.default_index]

    def _scroll_into_view(self, item) -> None:
        target = self._target(item)
        if target is None:
            return
        alloc = target.get_allocation()
        adj = self._scroller.get_vadjustment()
        view_top = adj.get_value()
        view_bottom = view_top + adj.get_page_size()
        if alloc.y < view_top:
            adj.set_value(alloc.y)
        elif alloc.y + alloc.height > view_bottom:
            adj.set_value(alloc.y + alloc.height - adj.get_page_size())


# ── windows ────────────────────────────────────────────────────────────────────

class Overlay(Window):
    """Layer-shell window the daemon reveals and dismisses over the socket."""

    # exclusive windows are modes: opening one closes every other exclusive
    # window. Notifications set this False so they survive a launcher opening.
    exclusive = True

    def __init__(self, **kwargs):
        super().__init__(exclusivity="none", visible=False, **kwargs)
        self.connect("key-press-event", self._on_key_press)

    def reveal(self) -> None:
        self.show()

    def dismiss(self) -> None:
        self.hide()

    def _on_key_press(self, _widget, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self.dismiss()
            return True
        return self.on_key(event)

    def on_key(self, event) -> bool:
        """Handle a non-Escape key. Return True once the key is consumed."""
        return False


def make_scroller(child, width: int, height: int, **kwargs) -> ScrolledWindow:
    """Fixed-size, scrollbar-less scroll area — the body of every panel."""
    return ScrolledWindow(
        child=child,
        v_scrollbar_policy="always",
        h_scrollbar_policy="never",
        overlay_scroll=True,
        min_content_size=(width, height),
        max_content_size=(width, height),
        style_classes="app-scroll",
        h_align="fill",
        v_align="start",
        h_expand=True,
        **kwargs,
    )


class Panel(Overlay):
    """Top-anchored search panel that slides and fades in and out.

    Subclasses supply their body with `set_body()` and refresh their contents
    from `on_reveal()`; the search entry, animation and focus are handled here.
    """

    ANIM_MS = 220

    def __init__(self, title: str, width: int, height: int, icon, placeholder: str):
        super().__init__(
            title=title,
            layer="top",
            anchor="top",
            margin="18px 0px 0px 0px",
            keyboard_mode="on-demand",
        )
        self._anim_src: int | None = None
        self._muted = False
        self.add_style_class("window")
        self.set_default_size(width, height)
        self.set_size_request(width, height)
        self.set_resizable(False)

        self.search = Entry(
            placeholder=placeholder, h_expand=True, style_classes="search-entry"
        )
        self.search.set_can_focus(True)
        self.search.connect("changed", self._on_search_changed)
        self._search_row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="search-row",
            h_expand=True,
            children=[icon, self.search],
        )

    def set_body(self, *children) -> None:
        self.children = Box(
            orientation="vertical",
            spacing=0,
            style_classes="launcher-root",
            children=[self._search_row, *children],
            h_expand=True,
            v_expand=True,
            v_align="start",
        )

    def _on_search_changed(self, *_) -> None:
        if not self._muted:
            self.on_search(self.search.get_text() or "")

    def on_search(self, query: str) -> None:
        """Called on every keystroke in the search entry."""

    def on_reveal(self) -> None:
        """Called just before the panel is shown, to refresh its contents."""

    def on_dismissed(self) -> None:
        """Called once the panel is fully hidden — a good time to rescan data."""

    # ── show / hide ────────────────────────────────────────────────────────

    def reveal(self) -> None:
        self._cancel_anim()
        # clear without firing on_search — on_reveal rebuilds the list anyway
        self._muted = True
        self.search.set_text("")
        self._muted = False
        self.on_reveal()
        # start off-screen, then drop the class one frame later so GTK has a
        # state to transition *from* — otherwise the animation never plays
        self.add_style_class("anim-out")
        self.show()
        GLib.timeout_add(16, self._settle)
        self.search.grab_focus()

    def dismiss(self) -> None:
        self._cancel_anim()
        self.add_style_class("anim-out")
        self._anim_src = GLib.timeout_add(self.ANIM_MS, self._finish_dismiss)

    def _cancel_anim(self) -> None:
        if self._anim_src is not None:
            GLib.source_remove(self._anim_src)
            self._anim_src = None

    def _settle(self) -> bool:
        self.remove_style_class("anim-out")
        return False

    def _finish_dismiss(self) -> bool:
        self._anim_src = None
        self.hide()
        self.on_dismissed()
        return False
