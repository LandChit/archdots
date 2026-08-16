"""Application launcher — app search with a web-search fallback row."""

import os
import re
import shlex
import subprocess
from urllib.parse import quote_plus

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import get_desktop_applications

from gi.repository import Gdk, GdkPixbuf, Gio  # type: ignore

from common import Panel, Selection, UsageCounts, make_scroller

COUNTS_PATH = "~/.local/share/fabric-launcher/counts.json"
SEARCH_URL = "https://www.google.com/search?q={}"

# Wrapper for .desktop entries marked Terminal=true. Kept here rather than
# inline so there is one place to change it.
TERMINAL = ("alacritty", "-e")

ICON_SIZE = 32
WIDTH = 540
HEIGHT = 580
LIST_HEIGHT = 460


def _pixbuf_icon(pixbuf) -> Image:
    return Image(
        pixbuf=pixbuf,
        size=[ICON_SIZE, ICON_SIZE],
        style_classes="app-icon",
        v_align="center",
    )


def _named_icon(name: str) -> Image:
    return Image(
        icon_name=name,
        icon_size=ICON_SIZE,
        style_classes="app-icon",
        v_align="center",
    )


class Launcher(Panel):
    def __init__(self):
        super().__init__(
            title="fabric-launcher",
            width=WIDTH,
            height=HEIGHT,
            icon=Label(label="", style_classes="search-icon"),
            placeholder="Search apps or type ? to search the web",
        )
        self._counts = UsageCounts(COUNTS_PATH)
        self._apps = self._sorted_apps()

        self._list = Box(
            orientation="vertical",
            spacing=3,
            style_classes="app-list",
            h_expand=True,
            v_expand=False,
            v_align="start",
        )
        scroller = make_scroller(self._list, WIDTH - 28, LIST_HEIGHT)
        self._selection = Selection(scroller, "app-selected")

        footer = Box(
            orientation="horizontal",
            spacing=20,
            style_classes="launcher-footer",
            h_expand=True,
            children=[
                Label(label=text, style_classes="hint")
                for text in ("↕  navigate", "↵  open", "?  web search", "esc  close")
            ],
        )

        self.set_body(scroller, footer)
        self.on_search("")
        self.show_all()
        self.hide()

    def _sorted_apps(self) -> list:
        return sorted(
            get_desktop_applications(),
            key=lambda app: (self._counts.rank(app.name), app.name.casefold()),
        )

    # ── list ────────────────────────────────────────────────────────────────

    def on_search(self, raw_query: str) -> None:
        query = raw_query.strip()
        is_web = query.startswith("?")
        term = query[1:].strip() if is_web else query

        for child in self._list.get_children():
            self._list.remove(child)

        rows = []
        if term:
            rows.append(self._web_row(term))
            needle = term.casefold()
            apps = [app for app in self._apps if self._matches(app, needle)]
        else:
            apps = self._apps
        rows += [self._app_row(app) for app in apps]

        for row in rows:
            self._list.add(row)
        self._list.show_all()

        self._selection.reset(rows)
        # Enter with nothing highlighted opens the first app, except for an
        # explicit "?" query where the web row is what the user asked for
        if term and not is_web and len(rows) > 1:
            self._selection.default_index = 1

    @staticmethod
    def _matches(app, needle: str) -> bool:
        return any(
            needle in (field or "").casefold()
            for field in (app.name, app.display_name, app.generic_name)
        )

    # ── rows ────────────────────────────────────────────────────────────────

    def _row(self, icon, title: str, subtitle: str, style_classes: str) -> Button:
        icon_tile = Box(
            orientation="vertical",
            h_align="center",
            v_align="center",
            style_classes="app-icon-tile",
            children=[icon],
        )
        text = Box(
            orientation="vertical",
            spacing=2,
            h_expand=True,
            v_align="center",
            children=[
                Label(label=title, ellipsization="end", h_align="start",
                      v_align="center", style_classes="app-name", h_expand=True),
                Label(label=subtitle, ellipsization="end", h_align="start",
                      v_align="center", style_classes="app-category", h_expand=True),
            ],
        )
        row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="app-row",
            h_expand=True,
            v_align="center",
            children=[
                icon_tile,
                text,
                Label(label="open ↵", style_classes="app-hint", v_align="center"),
            ],
        )
        return Button(child=row, style_classes=style_classes, h_expand=True)

    def _app_row(self, app) -> Button:
        button = self._row(
            self._app_icon(app),
            app.display_name or app.name or "",
            app.generic_name or "",
            "app-button",
        )
        button._activate = self._launcher_for(app)  # type: ignore[attr-defined]
        button._app_id = app.name  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_: self._run(button))
        return button

    def _web_row(self, query: str) -> Button:
        button = self._row(
            _named_icon("internet-web-browser"),
            f'Search for "{query}"',
            "Web search",
            "app-button web-button",
        )
        url = SEARCH_URL.format(quote_plus(query))
        button._activate = lambda: Gio.AppInfo.launch_default_for_uri(url)  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_: self._run(button))
        return button

    @staticmethod
    def _launcher_for(app):
        """Terminal apps need a terminal wrapper; everything else self-launches."""
        needs_terminal = getattr(app, "_app", None) and app._app.get_boolean("Terminal")
        if not needs_terminal:
            return app.launch
        # strip the %f/%U field codes a terminal command line cannot use
        cmd = shlex.split(re.sub(r"%[a-zA-Z]", "", app.command_line).strip())
        return lambda: subprocess.Popen([*TERMINAL, *cmd])

    def _app_icon(self, app) -> Image:
        """The app's own pixbuf, else an absolute icon path, else a themed name."""
        try:
            if pixbuf := app.get_icon_pixbuf(size=ICON_SIZE):
                return _pixbuf_icon(pixbuf)
        except Exception:
            pass

        icon_name = getattr(app, "icon_name", None) or ""
        if os.path.isabs(icon_name):
            try:
                return _pixbuf_icon(
                    GdkPixbuf.Pixbuf.new_from_file_at_size(
                        icon_name, ICON_SIZE, ICON_SIZE
                    )
                )
            except Exception:
                pass
        elif icon_name:
            return _named_icon(icon_name)

        return _named_icon("application-x-executable")

    # ── activation ──────────────────────────────────────────────────────────

    def on_key(self, event) -> bool:
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._run(self._selection.current)
        elif event.keyval == Gdk.KEY_Up:
            self._selection.move(-1)
        elif event.keyval == Gdk.KEY_Down:
            self._selection.move(1)
        else:
            return False
        return True

    def _run(self, button) -> None:
        if button is None:
            return
        if app_id := getattr(button, "_app_id", None):
            self._counts.bump(app_id)
        button._activate()
        self.dismiss()

    # ── panel hooks ─────────────────────────────────────────────────────────

    def on_reveal(self) -> None:
        self._counts.reload()
        self._apps.sort(key=lambda a: (self._counts.rank(a.name), a.name.casefold()))
        self.on_search("")

    def on_dismissed(self) -> None:
        # rescan while hidden so newly installed apps appear next time
        self._apps = self._sorted_apps()
