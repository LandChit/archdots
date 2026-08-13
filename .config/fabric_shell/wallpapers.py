"""Wallpaper picker — sets the wallpaper and repaints the shell to match.

Picking one does three things:

    1. tells hyprpaper to show it, on every monitor
    2. runs pywal over it and copies the palette into css/, which every window
       is already watching, so the whole shell recolours without a restart
    3. rewrites hyprpaper.conf so the choice survives a reboot

hyprpaper 0.8.4 rejects the `preload` request, but `wallpaper "MONITOR,PATH"`
loads the file itself — so there is nothing to preload first.
"""

import json
import os
import re
import shutil

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import exec_shell_command, exec_shell_command_async

from gi.repository import Gdk, GdkPixbuf, GLib  # type: ignore

from common import COLORS_CSS, CSS_DIR, Panel, Selection, UsageCounts, make_scroller

WALLPAPER_DIR = os.path.expanduser("~/Pictures/wallpapers")
HYPRPAPER_CONF = os.path.expanduser("~/.config/hypr/hyprpaper.conf")
HYPRLOCK_CONF = os.path.expanduser("~/.config/hypr/hyprlock.conf")
WAL_CACHE = os.path.expanduser("~/.cache/wal/" + COLORS_CSS)
COUNTS_PATH = "~/.local/share/fabric-launcher/wallpaper-counts.json"

EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".bmp")

WIDTH = 540
HEIGHT = 580
LIST_HEIGHT = 460
THUMB_WIDTH = 96
THUMB_HEIGHT = 54

# pywal has to finish writing before the palette is worth copying
COLOR_SYNC_DELAY_MS = 900


def wallpapers() -> list[str]:
    """Every image in the wallpaper directory, newest first."""
    try:
        names = [
            name
            for name in os.listdir(WALLPAPER_DIR)
            if name.lower().endswith(EXTENSIONS)
        ]
    except OSError:
        return []
    paths = [os.path.join(WALLPAPER_DIR, name) for name in names]
    return sorted(paths, key=lambda p: -os.path.getmtime(p))


def monitors() -> list[str]:
    """Connected monitor names, so every screen gets the same wallpaper.

    Parsed properly rather than grepped: each monitor carries a nested
    `activeWorkspace` with its own `name`, so a regex over the whole document
    returns workspace names ("1", "2") alongside the real outputs.
    """
    out = exec_shell_command("hyprctl monitors -j")
    if out is False:
        return []
    try:
        return [m["name"] for m in json.loads(out) if m.get("name")]
    except (ValueError, TypeError, AttributeError):
        return []


def current() -> str | None:
    """The wallpaper hyprpaper is showing, or None if it is not running."""
    out = exec_shell_command("hyprctl hyprpaper listactive")
    if out is False:
        return None
    for line in out.splitlines():
        if ":" in line:
            return line.split(":", 1)[1].strip()
    return None


class WallpaperPicker(Panel):
    """Searchable list of wallpapers with thumbnails."""

    def __init__(self):
        super().__init__(
            title="fabric-wallpaper",
            width=WIDTH,
            height=HEIGHT,
            # the fa picture glyph — the material one (U+F0E09) is missing
            # from JetBrainsMono NF and renders as a box
            icon=Label(label="", style_classes="search-icon"),
            placeholder="Search wallpapers",
        )
        self._counts = UsageCounts(COUNTS_PATH)
        self._paths = wallpapers()
        self._current = current()
        self._thumbs: dict[str, GdkPixbuf.Pixbuf] = {}

        self._list = Box(
            orientation="vertical",
            spacing=3,
            style_classes="wall-list",
            h_expand=True,
            v_align="start",
        )
        scroller = make_scroller(self._list, WIDTH - 28, LIST_HEIGHT)
        self._selection = Selection(scroller, "wall-selected")

        footer = Box(
            orientation="horizontal",
            spacing=20,
            style_classes="launcher-footer",
            h_expand=True,
            children=[
                Label(label=text, style_classes="hint")
                for text in ("↕  navigate", "↵  apply", "esc  close")
            ],
        )

        self.set_body(scroller, footer)
        self.on_search("")
        self.show_all()
        self.hide()

    # ── list ────────────────────────────────────────────────────────────────

    def on_search(self, raw_query: str) -> None:
        needle = raw_query.strip().casefold()
        for child in self._list.get_children():
            self._list.remove(child)

        rows = [
            self._row(path)
            for path in self._paths
            if needle in os.path.basename(path).casefold()
        ]
        for row in rows:
            self._list.add(row)
        self._list.show_all()
        self._selection.reset(rows)

    def on_reveal(self) -> None:
        # a wallpaper dropped in since the last open should show up
        self._paths = wallpapers()
        self._current = current()
        self.on_search("")

    def _thumb(self, path: str) -> Image:
        """Scaled preview, cached — rescaling on every keystroke is visible."""
        pixbuf = self._thumbs.get(path)
        if pixbuf is None:
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    path, THUMB_WIDTH, THUMB_HEIGHT, True
                )
            except Exception:
                return Image(
                    icon_name="image-missing",
                    icon_size=THUMB_HEIGHT,
                    style_classes="wall-thumb",
                )
            self._thumbs[path] = pixbuf
        return Image(pixbuf=pixbuf, style_classes="wall-thumb", v_align="center")

    def _row(self, path: str) -> Button:
        name = os.path.splitext(os.path.basename(path))[0]
        active = path == self._current

        card = Box(
            orientation="horizontal",
            spacing=12,
            style_classes="wall-row" + (" active" if active else ""),
            h_expand=True,
            children=[
                self._thumb(path),
                Box(
                    orientation="vertical",
                    spacing=1,
                    v_align="center",
                    h_expand=True,
                    children=[
                        Label(
                            label=name,
                            style_classes="wall-name",
                            h_align="start",
                            x_align=0.0,
                        ),
                        Label(
                            label="Current" if active else os.path.basename(path),
                            style_classes="wall-meta",
                            h_align="start",
                            x_align=0.0,
                        ),
                    ],
                ),
            ],
        )
        button = Button(child=card, style_classes="wall-button")
        button.connect("clicked", lambda *_, p=path: self._apply(p))
        button._path = path  # type: ignore[attr-defined]
        return button

    # ── keys ────────────────────────────────────────────────────────────────

    def on_key(self, event) -> bool:
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            selected = self._selection.current
            if selected is not None:
                self._apply(selected._path)
        elif event.keyval == Gdk.KEY_Up:
            self._selection.move(-1)
        elif event.keyval == Gdk.KEY_Down:
            self._selection.move(1)
        else:
            return False
        return True

    # ── applying ────────────────────────────────────────────────────────────

    def _apply(self, path: str) -> None:
        self._counts.bump(path)
        self.dismiss()

        for monitor in monitors() or [""]:
            # an empty monitor name means "every monitor" to hyprpaper
            exec_shell_command_async(f'hyprctl hyprpaper wallpaper "{monitor},{path}"')

        # pywal regenerates the palette; the copy is what the shell watches
        exec_shell_command_async(f'wal -i "{path}" -n -q')
        GLib.timeout_add(COLOR_SYNC_DELAY_MS, self._sync_colors)

        self._persist(path)
        self._current = path

    @staticmethod
    def _sync_colors() -> bool:
        """Copy pywal's palette into css/, which every window is watching."""
        try:
            shutil.copyfile(WAL_CACHE, os.path.join(CSS_DIR, COLORS_CSS))
        except OSError as e:
            print(f"[wallpaper] could not sync colours: {e}")
        return False

    @staticmethod
    def _persist(path: str) -> None:
        """Point the desktop and the lock screen at `path` so the choice sticks.

        hyprpaper draws the desktop and hyprlock draws the lock screen, each
        from its own config with its own `path =`. Updating only the first
        leaves the lock screen on whatever was set at install time, which reads
        as a stale cache rather than two files quietly disagreeing.

        Only the `path =` lines are touched — everything else in either file is
        left exactly as it was written.
        """
        for conf in (HYPRPAPER_CONF, HYPRLOCK_CONF):
            try:
                with open(conf, encoding="utf-8") as f:
                    original = f.read()
            except OSError:
                continue  # no config to keep in step with

            updated, count = re.subn(
                r"(?m)^(\s*path\s*=\s*).*$", lambda m: m.group(1) + path, original
            )
            if count == 0 or updated == original:
                continue
            try:
                with open(conf, "w", encoding="utf-8") as f:
                    f.write(updated)
            except OSError as e:
                print(f"[wallpaper] could not update {os.path.basename(conf)}: {e}")
