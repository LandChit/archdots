"""Shared plumbing for the fabric shell.

Holds the three things every module needs: stylesheet loading that follows
pywal, persisted usage counters, and the overlay/panel base classes the
launcher, clipboard, emoji picker and power menu are built on.
"""

import json
import os

# fabric must be imported before gi.repository — importing it calls
# gi.require_version("Gtk", "3.0"). Touching gi first pulls in GTK 4 instead.
from fabric import Application
from fabric.widgets.box import Box
from fabric.widgets.entry import Entry
from fabric.widgets.scrolledwindow import ScrolledWindow
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.utils.helpers import compile_css, monitor_file

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
    """Concatenate the pywal palette, the shared base sheet and `sheets`."""
    # pywal writes a `url(...)` wallpaper line into the palette that GTK cannot
    # resolve from here, so it is dropped before anything is concatenated.
    colors = "\n".join(
        line for line in _read(COLORS_CSS).splitlines() if "url(" not in line
    )
    return "\n".join([colors, _read("style.css"), *(_read(s) for s in sheets)])


def style_application(app: Application, *sheets: str) -> None:
    """Style `app` from `sheets`, restyling whenever pywal rewrites the palette."""
    def refresh(*_):
        app.set_stylesheet_from_string(build_css(*sheets), base_path=CSS_DIR)

    refresh()
    monitor_file(os.path.join(CSS_DIR, COLORS_CSS), refresh)


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
    monitor_file(os.path.join(CSS_DIR, COLORS_CSS), refresh)


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
