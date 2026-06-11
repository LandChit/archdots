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
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import get_desktop_applications, monitor_file

from gi.repository import GdkPixbuf, Gio, GLib  # type: ignore

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

ICON_SIZE = 32
WINDOW_WIDTH = 540
WINDOW_HEIGHT = 580
LIST_HEIGHT = 460


class Launcher(Window):
    def __init__(self, daemon_mode: bool = False, **kwargs):
        super().__init__(
            layer="top",
            anchor="top",
            margin="18px 0px 0px 0px",
            exclusivity="none",
            keyboard_mode="on-demand",
            visible=False,
            **kwargs,
        )
        self._daemon_mode = daemon_mode
        self._dismiss_timer_id: int | None = None
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

        self._list_box = Box(
            orientation="vertical",
            spacing=3,
            style_classes="app-list",
            h_expand=True,
            v_expand=False,
            v_align="start",
        )

        self._scroller = ScrolledWindow(
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            child=self._list_box,
            overlay_scroll=True,
            min_content_size=(WINDOW_WIDTH - 28, LIST_HEIGHT),
            max_content_size=(WINDOW_WIDTH - 28, LIST_HEIGHT),
            style_classes="app-scroll",
            h_align="fill",
            v_align="start",
            h_expand=True,
        )

        search_row = Box(
            spacing=10,
            orientation="horizontal",
            style_classes="search-row",
            children=[
                Label(label="", style_classes="search-icon"),
                self._search_entry,
            ],
            h_expand=True,
        )

        footer = Box(
            orientation="horizontal",
            spacing=20,
            style_classes="launcher-footer",
            h_expand=True,
            children=[
                Label(label="↕  navigate", style_classes="hint"),
                Label(label="↵  open", style_classes="hint"),
                Label(label="?  web search", style_classes="hint"),
                Label(label="esc  close", style_classes="hint"),
            ],
        )

        self.children = Box(
            orientation="vertical",
            spacing=0,
            style_classes="launcher-root",
            children=[search_row, self._scroller, footer],
            h_expand=True,
            v_expand=True,
            v_align="start",
        )

        self.connect("key-press-event", self._on_key_press)
        self._refresh_app_list("")
        self.show_all()
        if self._daemon_mode:
            self.hide()
        else:
            self._search_entry.grab_focus()

    # ── search ──────────────────────────────────────────────────────────────

    def _on_search_changed(self, *_):
        self._refresh_app_list(self._search_entry.get_text() or "")

    def _refresh_app_list(self, raw_query: str):
        query = raw_query.strip()
        web_query = query[1:].strip() if query.startswith("?") else query
        app_query = web_query if query.startswith("?") else query

        for child in self._list_box.get_children():
            self._list_box.remove(child)

        self._items = []
        self._selected_index = None

        if web_query:
            self._list_box.add(self._register_item(self._build_web_row(web_query)))

        if app_query:
            normalized = app_query.casefold()
            apps = [
                app for app in self._apps
                if normalized in app.name.casefold()
                or (app.display_name or "").casefold().find(normalized) >= 0
                or (app.generic_name or "").casefold().find(normalized) >= 0
            ]
        else:
            apps = self._apps

        for app in apps:
            self._list_box.add(self._register_item(self._build_app_row(app)))

        self._list_box.show_all()

        # No visual preselection — this is only the Enter fallback target
        # (first app result, or the web row for explicit "?" queries)
        if self._items:
            self._default_index = (
                0 if query.startswith("?")
                else (1 if web_query and len(self._items) > 1 else 0)
            )
        else:
            self._default_index = None

    # ── row builders ─────────────────────────────────────────────────────────

    def _make_icon(self, app) -> Image:
        try:
            pixbuf = app.get_icon_pixbuf(size=ICON_SIZE)
            if pixbuf is not None:
                return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE],
                             style_classes="app-icon", v_align="center")
        except Exception:
            pass

        icon_name = getattr(app, "icon_name", None) or ""

        if os.path.isabs(icon_name) and os.path.isfile(icon_name):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, ICON_SIZE, ICON_SIZE)
                if pixbuf is not None:
                    return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE],
                                 style_classes="app-icon", v_align="center")
            except Exception:
                pass

        if icon_name and not os.path.isabs(icon_name):
            return Image(icon_name=icon_name, icon_size=ICON_SIZE,
                         style_classes="app-icon", v_align="center")

        return Image(icon_name="application-x-executable", icon_size=ICON_SIZE, v_align="center")

    def _build_app_row(self, app) -> Button:
        icon_tile = Box(
            orientation="vertical",
            h_align="center",
            v_align="center",
            style_classes="app-icon-tile",
            children=[self._make_icon(app)],
        )

        name_label = Label(
            label=app.display_name or app.name or "",
            ellipsization="end",
            h_align="start",
            v_align="center",
            style_classes="app-name",
            h_expand=True,
        )
        cat_label = Label(
            label=app.generic_name or "",
            ellipsization="end",
            h_align="start",
            v_align="center",
            style_classes="app-category",
            h_expand=True,
        )
        text_box = Box(
            orientation="vertical",
            spacing=2,
            h_expand=True,
            v_align="center",
            children=[name_label, cat_label],
        )

        hint = Label(label="open ↵", style_classes="app-hint", v_align="center")

        row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="app-row",
            h_expand=True,
            v_align="center",
            children=[icon_tile, text_box, hint],
        )

        needs_terminal = getattr(app, "_app", None) and app._app.get_boolean("Terminal")
        if needs_terminal:
            cmd = re.sub(r"%[a-zA-Z]", "", app.command_line).strip()
            launch_fn = lambda c=cmd: subprocess.Popen(["foot", "-e"] + shlex.split(c))
        else:
            launch_fn = app.launch

        button = Button(child=row, style_classes="app-button", h_expand=True)
        button._launch_action = launch_fn  # type: ignore[attr-defined]
        button._app_id = app.name  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_, fn=launch_fn, aid=app.name: self._launch_and_close(fn, aid))
        return button

    def _build_web_row(self, query: str) -> Button:
        icon_tile = Box(
            orientation="vertical",
            h_align="center",
            v_align="center",
            style_classes="app-icon-tile",
            children=[Image(icon_name="internet-web-browser", icon_size=ICON_SIZE, v_align="center")],
        )

        text_box = Box(
            orientation="vertical",
            spacing=2,
            h_expand=True,
            v_align="center",
            children=[
                Label(label=f'Search for "{query}"', ellipsization="end",
                      h_align="start", v_align="center", style_classes="app-name",
                      h_expand=True),
                Label(label="Web search", h_align="start", v_align="center",
                      style_classes="app-category", h_expand=True),
            ],
        )

        hint = Label(label="open ↵", style_classes="app-hint", v_align="center")

        row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="app-row",
            h_expand=True,
            v_align="center",
            children=[icon_tile, text_box, hint],
        )

        url = f"https://www.google.com/search?q={quote_plus(query)}"
        launch_fn = lambda u=url: Gio.AppInfo.launch_default_for_uri(u)

        button = Button(child=row, style_classes="app-button web-button", h_expand=True)
        button._launch_action = launch_fn  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_, fn=launch_fn: self._launch_and_close(fn))
        return button

    def _register_item(self, button: Button) -> Button:
        self._items.append(button)
        return button

    # ── keyboard ─────────────────────────────────────────────────────────────

    def _on_key_press(self, _widget, event):
        keyval = event.keyval
        if keyval == 65307:  # Escape
            self._quit()
            return True
        if keyval in (65293, 65421):  # Return / KP_Enter
            self._activate_selected()
            return True
        if keyval == 65362:  # Up
            self._move_selection(-1)
            return True
        if keyval == 65364:  # Down
            self._move_selection(1)
            return True
        return False

    def _move_selection(self, delta: int):
        if not self._items:
            return
        if self._selected_index is None:
            self._select_index(0)
            return
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

    # ── actions ──────────────────────────────────────────────────────────────

    def _activate_selected(self):
        index = (
            self._selected_index
            if self._selected_index is not None
            else self._default_index
        )
        if index is None:
            return
        button = self._items[index]
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

    # ── daemon support ────────────────────────────────────────────────────────

    def dismiss(self) -> None:
        if self._dismiss_timer_id is not None:
            GLib.source_remove(self._dismiss_timer_id)
        self.add_style_class("anim-out")
        self._dismiss_timer_id = GLib.timeout_add(220, self._finish_dismiss)

    def _finish_dismiss(self) -> bool:
        self._dismiss_timer_id = None
        self.hide()
        self._apps = sorted(
            get_desktop_applications(),
            key=lambda app: (-self._counts.get(app.name, 0), app.name.casefold()),
        )
        return False

    def reveal(self) -> None:
        if self._dismiss_timer_id is not None:
            GLib.source_remove(self._dismiss_timer_id)
            self._dismiss_timer_id = None
        self._counts = _load_counts()
        self._apps.sort(key=lambda a: (-self._counts.get(a.name, 0), a.name.casefold()))
        self._search_entry.set_text("")
        self._refresh_app_list("")
        self.add_style_class("anim-out")
        self.show()
        GLib.timeout_add(16, self._finish_reveal)
        self._search_entry.grab_focus()

    def _finish_reveal(self) -> bool:
        self.remove_style_class("anim-out")
        return False

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
    try:
        with open(os.path.join(CSS_DIR, "colors-fabric.css")) as f:
            color_css = "\n".join(
                line for line in f.read().splitlines() if "url(" not in line
            )
    except FileNotFoundError:
        color_css = ""

    with open(os.path.join(CSS_DIR, "launcher.css")) as f:
        launcher_css = f.read()

    app.set_stylesheet_from_string(
        color_css + "\n" + launcher_css,
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
