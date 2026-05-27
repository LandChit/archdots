import json
import os
import re
import shlex
import subprocess
from urllib.parse import quote_plus

COUNTS_PATH = os.path.expanduser("~/.local/share/fabric-launcher/counts.json")


def _load_counts() -> dict[str, int]:
    try:
        with open(COUNTS_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_counts(counts: dict[str, int]) -> None:
    os.makedirs(os.path.dirname(COUNTS_PATH), exist_ok=True)
    with open(COUNTS_PATH, "w") as f:
        json.dump(counts, f, indent=2)

from fabric import Application
from fabric.widgets.scrolledwindow import ScrolledWindow
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.entry import Entry
from fabric.widgets.flowbox import FlowBox
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import get_desktop_applications, monitor_file

from gi.repository import GdkPixbuf, Gio  # type: ignore

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

ICON_SIZE = 30
GRID_GAP = 0
CARD_SIZE = 110
GRID_WIDTH = (CARD_SIZE * 3) + (GRID_GAP * 2)
WINDOW_WIDTH = GRID_WIDTH * 1.4 + 22
WINDOW_HEIGHT = 800
GRID_HEIGHT = WINDOW_HEIGHT


class Launcher(Window):
    def __init__(self, daemon_mode: bool = False, **kwargs):
        super().__init__(
            layer="top",
            anchor="top",
            margin="0px 0px 0px 0px",
            exclusivity="none",
            keyboard_mode="on-demand",
            visible=False,
            **kwargs,
        )
        self._daemon_mode = daemon_mode
        self.add_style_class("window")
        self.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_resizable(False)

        self._counts = _load_counts()
        self._apps = sorted(
            get_desktop_applications(),
            key=lambda app: (-self._counts.get(app.name, 0), app.name.casefold()),
        )
        self._items: list[Button] = []
        self._selected_index: int | None = None

        self._search_entry = Entry(
            placeholder="Search apps or type ? to search the web",
            h_expand=True,
            style_classes="search-entry",
        )
        self._search_entry.set_can_focus(True)
        self._search_entry.connect("changed", self._on_search_changed)

        self._flowbox = FlowBox(
            row_spacing=GRID_GAP,
            column_spacing=GRID_GAP,
            orientation="horizontal",
            style_classes="app-grid",
            h_align="start",
            v_align="start",
            h_expand=False,
            v_expand=False,
        )
        self._flowbox.set_max_children_per_line(3)
        self._flowbox.set_min_children_per_line(3)
        self._flowbox.set_homogeneous(False)
        self._flowbox.set_size_request(GRID_WIDTH, -1)

        self._scroller = ScrolledWindow(
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            child=self._flowbox,
            overlay_scroll=True,
            min_content_size=(GRID_WIDTH, GRID_HEIGHT),
            max_content_size=(GRID_WIDTH, GRID_HEIGHT),
            style_classes="app-scroll",
            h_align="fill",
            v_align="start",
            h_expand=True,
            # v_expand=True,
            # size=[GRID_WIDTH, GRID_HEIGHT],
        )
        # self._scroller.set_size_request(GRID_WIDTH, GRID_HEIGHT)

        search_row = Box(
            spacing=12,
            orientation="horizontal",
            style_classes="search-row",
            children=[
                Image(icon_name="system-search", icon_size=ICON_SIZE),
                self._search_entry,
            ],
            h_expand=True,
        )

        self.children = Box(
            orientation="vertical",
            spacing=0,
            style_classes="launcher-root",
            children=[search_row, self._scroller],
            h_expand=True,
            v_expand=True,
            v_align="start",
            # h_align="fill",
            # h_align="center",
        )

        self.connect("key-press-event", self._on_key_press)

        self._refresh_app_grid("")
        self.show_all()
        if self._daemon_mode:
            self.hide()
        else:
            self._search_entry.grab_focus()

    def _on_search_changed(self, *_):
        self._refresh_app_grid(self._search_entry.get_text() or "")

    def _refresh_app_grid(self, raw_query: str):
        query = raw_query.strip()
        web_query = query[1:].strip() if query.startswith("?") else query
        app_query = web_query if query.startswith("?") else query

        for child in self._flowbox.get_children():
            self._flowbox.remove(child)

        self._items = []
        self._selected_index = None

        if web_query:
            self._flowbox.add(
                self._register_item(self._build_web_search_item(web_query))
            )

        if app_query:
            normalized = app_query.casefold()
            apps = [
                app
                for app in self._apps
                if normalized in app.name.casefold()
                or (app.display_name or "").casefold().find(normalized) >= 0
                or (app.generic_name or "").casefold().find(normalized) >= 0
            ]
        else:
            apps = self._apps

        for app in apps:
            self._flowbox.add(self._register_item(self._build_app_item(app)))

        self._flowbox.show_all()

        if web_query and self._items:
            if query.startswith("?"):
                auto_idx = 0
            else:
                auto_idx = 1 if len(self._items) > 1 else 0
            self._select_index(auto_idx)

    def _make_icon(self, app) -> Image:
        # 1. Try fabric's built-in pixbuf loader
        try:
            pixbuf = app.get_icon_pixbuf(size=ICON_SIZE)
            if pixbuf is not None:
                return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE], style_classes="app-icon", v_align="center")
        except Exception:
            pass

        icon_name = getattr(app, "icon_name", None) or ""

        # 2. Absolute path — load the file directly (PNG or SVG via librsvg)
        if os.path.isabs(icon_name) and os.path.isfile(icon_name):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, ICON_SIZE, ICON_SIZE)
                if pixbuf is not None:
                    return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE], style_classes="app-icon", v_align="center")
            except Exception:
                pass

        # 3. Theme icon name (short name like "firefox" or "rustrover")
        if icon_name and not os.path.isabs(icon_name):
            return Image(icon_name=icon_name, icon_size=ICON_SIZE, style_classes="app-icon", v_align="center")

        # 4. Generic fallback
        return Image(icon_name="application-x-executable", icon_size=ICON_SIZE, v_align="center")

    def _build_app_item(self, app):
        icon = self._make_icon(app)

        label = Label(
            label=app.name,
            ellipsization="end",
            max_chars_width=16,
            justification="center",
            line_wrap="word-char",
            h_align="center",
            style_classes="app-label",
            v_align="center",
        )

        content = Box(
            orientation="vertical",
            spacing=6,
            style_classes="app-card",
            h_align="center",
            v_align="center",
            h_expand=False,
            v_expand=False,
            size=[CARD_SIZE, CARD_SIZE - 20],
            children=[Box(size=[0, 5]), icon, label],
        )

        needs_terminal = getattr(app, '_app', None) and app._app.get_boolean('Terminal')
        if needs_terminal:
            cmd = re.sub(r'%[a-zA-Z]', '', app.command_line).strip()
            launch_fn = lambda c=cmd: subprocess.Popen(["foot", "-e"] + shlex.split(c))
        else:
            launch_fn = app.launch

        button = Button(child=content, style_classes="app-button")
        button._launch_action = launch_fn  # type: ignore[attr-defined]
        button._app_id = app.name  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_, fn=launch_fn, aid=app.name: self._launch_and_close(fn, aid))
        return button

    def _build_web_search_item(self, query: str):
        label = Label(
            label=f'Search the web for "{query}"',
            ellipsization="end",
            max_chars_width=16,
            justification="center",
            line_wrap="word-char",
            h_align="center",
            style_classes="app-label",
            v_align="center",
        )

        content = Box(
            orientation="vertical",
            spacing=6,
            style_classes="app-card web-card",
            h_align="center",
            v_align="center",
            h_expand=False,
            v_expand=False,
            size=[CARD_SIZE, CARD_SIZE - 20],
            children=[
                Box(size=[0, 5]),
                Image(icon_name="internet-web-browser", icon_size=ICON_SIZE),
                label,
            ],
        )

        button = Button(child=content, style_classes="app-button web-button")
        button._launch_action = lambda: Gio.AppInfo.launch_default_for_uri(
            f"https://www.google.com/search?q={quote_plus(query)}"
        )  # type: ignore[attr-defined]
        button.connect(
            "clicked",
            lambda *_: self._launch_and_close(
                lambda: Gio.AppInfo.launch_default_for_uri(
                    f"https://www.google.com/search?q={quote_plus(query)}"
                )
            ),
        )
        return button

    def _register_item(self, button: Button) -> Button:
        self._items.append(button)
        return button

    def _on_key_press(self, _widget, event):
        keyval = event.keyval
        if keyval in (65307,):  # Escape
            self._quit()
            return True

        if keyval in (65293, 65421):  # Return, KP_Enter
            self._activate_selected()
            return True

        if keyval in (65362, 65364, 65361, 65363):  # Up, Down, Left, Right
            self._move_selection(keyval)
            return True

        return False

    def _move_selection(self, keyval: int):
        if not self._items:
            return
        columns = 3
        if self._selected_index is None:
            self._select_index(0)
            return

        delta = 0
        if keyval == 65362:  # Up
            delta = -columns
        elif keyval == 65364:  # Down
            delta = columns
        elif keyval == 65361:  # Left
            delta = -1
        elif keyval == 65363:  # Right
            delta = 1

        self._select_index(self._selected_index + delta)

    def _select_index(self, index: int):
        index = max(0, min(index, len(self._items) - 1))
        if self._selected_index is not None:
            self._items[self._selected_index].remove_style_class("app-selected")
        self._selected_index = index
        self._items[index].add_style_class("app-selected")
        self._scroll_to_item(index)

    def _scroll_to_item(self, index: int):
        button = self._items[index]
        adj = self._scroller.get_vadjustment()
        alloc = button.get_allocation()
        item_top = alloc.y
        item_bottom = alloc.y + alloc.height
        view_top = adj.get_value()
        view_bottom = view_top + adj.get_page_size()
        if item_top < view_top:
            adj.set_value(item_top)
        elif item_bottom > view_bottom:
            adj.set_value(item_bottom - adj.get_page_size())

    def _activate_selected(self):
        if self._selected_index is None:
            return
        button = self._items[self._selected_index]
        action = getattr(button, "_launch_action", None)
        app_id = getattr(button, "_app_id", None)
        if action is not None:
            self._launch_and_close(action, app_id)

    def _launch_and_close(self, launcher, app_id: str | None = None):
        if app_id:
            self._counts[app_id] = self._counts.get(app_id, 0) + 1
            _save_counts(self._counts)
        launcher()
        self._quit()

    # ── daemon support ─────────────────────────────────────────────────────────

    def dismiss(self) -> None:
        """Hide the window without quitting the process (daemon mode)."""
        self.hide()

    def reveal(self) -> None:
        """Refresh counts, reset search, and show the window."""
        self._counts = _load_counts()
        self._apps.sort(
            key=lambda a: (-self._counts.get(a.name, 0), a.name.casefold())
        )
        self._search_entry.set_text("")
        self._refresh_app_grid("")
        self.show()
        self._search_entry.grab_focus()

    def _quit(self) -> None:
        if self._daemon_mode:
            self.dismiss()
        else:
            app = getattr(self, "_app_ref", None) or self.get_application()
            if app is not None:
                app.quit()
            else:
                os._exit(0)


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

    with open(os.path.join(CSS_DIR, "launcher.css")) as f:
        bar_css = f.read()

    app.set_stylesheet_from_string(
        color_css + "\n" + bar_css,
        base_path=CSS_DIR,
    )


if __name__ == "__main__":
    launcher = Launcher()
    app = Application("launcher", launcher)
    launcher._app_ref = app
    load_css(app)

    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )

    app.run()
