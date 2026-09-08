"""Wallpaper picker — sets the wallpaper and repaints the shell to match.

Picking one does three things:

    1. tells hyprpaper to show it, on every monitor
    2. runs pywal16 over it and copies the palette into css/, which every window
       is already watching, so the whole shell recolours without a restart
    3. re-points ~/.local/state/archdots/wallpaper at it, so the choice survives
       a reboot

hyprpaper 0.8.4 rejects the `preload` request, but `wallpaper "MONITOR,PATH"`
loads the file itself — so there is nothing to preload first.
"""

import json
import os
import shutil

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import exec_shell_command, exec_shell_command_async

from gi.repository import Gdk, GdkPixbuf, GLib  # type: ignore

from common import COLORS_CSS, CSS_DIR, Panel, Selection, UsageCounts, make_scroller

WALLPAPER_DIR = os.path.expanduser("~/Pictures/wallpapers")
# hyprpaper.conf and hyprlock.conf both name this symlink rather than a picture,
# so the choice made here is the only thing that has to change — and it changes
# outside the repo, where it belongs.
WALLPAPER_POINTER = os.path.expanduser("~/.local/state/archdots/wallpaper")
WAL_CACHE = os.path.expanduser("~/.cache/wal/" + COLORS_CSS)

# Palette generation flags, kept identical to install.sh's WAL_ARGS.
# --cols16 dual makes colors 8-15 distinct colours instead of copies of 0-7.
WAL_ARGS = "--cols16 dual"
COUNTS_PATH = "~/.local/share/fabric-launcher/wallpaper-counts.json"

# The GTK theme follows the wallpaper the same way the shell does, only it
# cannot read colors-fabric.css: GTK's CSS has no var(), so pywal16 renders a
# second template using @define-color instead. Both halves of the theme import
# a colors.css sitting next to their gtk.css, and these are those two copies.
#
# There are three copies, not two, because GTK resolves a nested @import
# against the *entry* file's directory rather than the importing file's. The
# GTK 4 sheet is reached through ~/.config/gtk-4.0/gtk.css — the only file
# libadwaita apps read — so its `@import url("colors.css")` looks for the
# palette next to *that*, and the theme's own copy is never consulted.
GTK_WAL_CACHE = os.path.expanduser("~/.cache/wal/colors-gtk.css")
GTK_COLOR_TARGETS = (
    os.path.expanduser("~/.themes/archdots/gtk-3.0/colors.css"),
    os.path.expanduser("~/.themes/archdots/gtk-4.0/colors.css"),
    os.path.expanduser("~/.config/gtk-4.0/colors.css"),
)

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

        # pywal16 regenerates the palette; the copy is what the shell watches.
        # Flags have to stay in step with install.sh's WAL_ARGS.
        exec_shell_command_async(f'wal -i "{path}" {WAL_ARGS} -n -q')
        GLib.timeout_add(COLOR_SYNC_DELAY_MS, self._sync_colors)

        self._persist(path)
        self._current = path

    @staticmethod
    def _sync_colors() -> bool:
        """Copy pywal16's palettes to everything that reads them.

        Two consumers, two formats. css/ is watched live by every shell window;
        the GTK theme's colors.css is only re-read when an app starts or the
        theme is re-selected, so GTK apps already open keep their old colours
        until they are restarted. Each copy is reported separately — a missing
        GTK theme should not stop the shell from recolouring itself.
        """
        for src, dest in (
            (WAL_CACHE, os.path.join(CSS_DIR, COLORS_CSS)),
            *((GTK_WAL_CACHE, t) for t in GTK_COLOR_TARGETS),
        ):
            try:
                shutil.copyfile(src, dest)
            except OSError as e:
                print(f"[wallpaper] could not sync colours to {dest}: {e}")
        return False

    @staticmethod
    def _persist(path: str) -> None:
        """Point the desktop and the lock screen at `path` so the choice sticks.

        hyprpaper draws the desktop and hyprlock draws the lock screen, each
        from its own config — and both of those configs name WALLPAPER_POINTER
        rather than a picture, so moving the one symlink keeps the two in step
        by construction. They cannot drift apart the way they could when this
        rewrote a `path =` line in each of them.

        It also stops the picker from writing into the repo. Both configs are
        stowed symlinks, so editing them in place edited the tracked files and
        every wallpaper change turned up in `git status`.
        """
        try:
            os.makedirs(os.path.dirname(WALLPAPER_POINTER), exist_ok=True)
            # os.symlink cannot replace an existing link, so aim at a temporary
            # name and rename over it — atomic, and never leaves the pointer
            # missing if this is interrupted.
            staging = WALLPAPER_POINTER + ".new"
            if os.path.lexists(staging):
                os.remove(staging)
            os.symlink(path, staging)
            os.replace(staging, WALLPAPER_POINTER)
        except OSError as e:
            print(f"[wallpaper] could not update {WALLPAPER_POINTER}: {e}")
