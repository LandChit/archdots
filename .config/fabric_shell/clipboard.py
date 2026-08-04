"""Clipboard history browser backed by `cliphist`."""

import re
import subprocess

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label

from gi.repository import Gdk, GdkPixbuf  # type: ignore

from common import Panel, Selection, make_scroller

THUMB_SIZE = 48
ICON_SIZE = 20
WIDTH = 500
HEIGHT = 700
PREVIEW_CHARS = 120
# decoding a large entry just to draw a 48px thumbnail is not worth the stall
MAX_THUMB_BYTES = 300 * 1024

_BINARY_RE = re.compile(r"\[\[ binary data (\d+(?:\.\d+)?)\s*(B|KiB|MiB)\s+(\w+)")
_DIMS_RE = re.compile(r"(\d+x\d+)")
_UNITS = {"B": 1, "KiB": 1024, "MiB": 1024 * 1024}


class Clip:
    """One `cliphist list` row.

    `line` is the raw "id\\tpreview" text, which is what `cliphist decode`
    expects back on stdin — the id on its own is not enough.
    """

    def __init__(self, line: str, preview: str):
        self.line = line
        self.preview = preview
        match = _BINARY_RE.match(preview)
        self.is_image = match is not None
        self.format = match.group(3).lower() if match else ""
        self.size = int(float(match.group(1)) * _UNITS[match.group(2)]) if match else 0

    @property
    def label(self) -> str:
        if not self.is_image:
            return self.preview
        dims = _DIMS_RE.search(self.preview)
        return (
            f"[image/{self.format}  {dims.group(1)}]" if dims else f"[image/{self.format}]"
        )

    def decode(self) -> bytes | None:
        try:
            result = subprocess.run(
                ["cliphist", "decode"],
                input=self.line.encode(),
                capture_output=True,
                timeout=5,
            )
            return result.stdout if result.returncode == 0 else None
        except Exception:
            return None

    def copy(self) -> None:
        data = self.decode()
        if not data:
            return
        cmd = ["wl-copy", f"--type=image/{self.format}"] if self.is_image else ["wl-copy"]
        try:
            subprocess.Popen(cmd, stdin=subprocess.PIPE).communicate(data)
        except Exception:
            pass


def _history() -> list[Clip]:
    try:
        result = subprocess.run(
            ["cliphist", "list"], capture_output=True, text=True, timeout=5
        )
    except Exception:
        return []
    return [
        Clip(line, line.split("\t", 1)[1])
        for line in result.stdout.splitlines()
        if "\t" in line
    ]


class ClipboardManager(Panel):
    def __init__(self):
        super().__init__(
            title="fabric-clipboard",
            width=WIDTH,
            height=HEIGHT,
            icon=Image(icon_name="edit-paste", icon_size=ICON_SIZE),
            placeholder="Search clipboard…",
        )
        self._clips: list[Clip] = _history()

        self._list = Box(
            orientation="vertical",
            spacing=4,
            style_classes="clip-list",
            h_expand=True,
            v_expand=False,
            v_align="start",
        )
        scroller = make_scroller(self._list, WIDTH - 20, HEIGHT - 60)
        self._selection = Selection(scroller, "clip-selected")

        self.set_body(scroller)
        self.on_search("")
        self.show_all()
        self.hide()

    # ── list ────────────────────────────────────────────────────────────────

    def on_search(self, query: str) -> None:
        for child in self._list.get_children():
            self._list.remove(child)

        needle = query.strip().casefold()
        rows = [
            self._row(clip)
            for clip in self._clips
            if not needle or needle in clip.preview.casefold()
        ]
        for row in rows:
            self._list.add(row)
        self._list.show_all()
        self._selection.reset(rows)

    def _row(self, clip: Clip) -> Button:
        text = clip.label
        row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="clip-item",
            h_expand=True,
            v_align="center",
            children=[
                self._thumb(clip),
                Label(
                    label=text[:PREVIEW_CHARS]
                    + ("…" if len(text) > PREVIEW_CHARS else ""),
                    ellipsization="end",
                    h_align="start",
                    v_align="center",
                    style_classes="clip-label",
                    h_expand=True,
                ),
            ],
        )
        button = Button(child=row, style_classes="clip-button", h_expand=True)
        button._clip = clip  # type: ignore[attr-defined]
        button.connect("clicked", lambda *_: self._copy(button))
        return button

    def _thumb(self, clip: Clip) -> Image:
        if not clip.is_image:
            return self._glyph("edit-copy")
        if clip.size > MAX_THUMB_BYTES:
            return self._glyph("image-x-generic")
        try:
            data = clip.decode()
            if not data:
                return self._glyph("image-x-generic")
            loader = GdkPixbuf.PixbufLoader()
            loader.write(data)
            loader.close()
            pixbuf = loader.get_pixbuf()
            if pixbuf is None:
                return self._glyph("image-x-generic")
            width, height = pixbuf.get_width(), pixbuf.get_height()
            scale = THUMB_SIZE / max(width, height, 1)
            pixbuf = pixbuf.scale_simple(
                max(1, int(width * scale)),
                max(1, int(height * scale)),
                GdkPixbuf.InterpType.BILINEAR,
            )
            return Image(
                pixbuf=pixbuf,
                size=[THUMB_SIZE, THUMB_SIZE],
                v_align="center",
                style_classes="clip-thumb",
            )
        except Exception:
            return self._glyph("image-x-generic")

    @staticmethod
    def _glyph(name: str) -> Image:
        return Image(
            icon_name=name,
            icon_size=ICON_SIZE,
            v_align="center",
            style_classes="clip-text-icon",
        )

    # ── activation ──────────────────────────────────────────────────────────

    def on_key(self, event) -> bool:
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._copy(self._selection.current)
        elif event.keyval == Gdk.KEY_Up:
            self._selection.move(-1)
        elif event.keyval == Gdk.KEY_Down:
            self._selection.move(1)
        else:
            return False
        return True

    def _copy(self, button) -> None:
        if button is None:
            return
        button._clip.copy()
        self.dismiss()

    # ── panel hooks ─────────────────────────────────────────────────────────

    def on_reveal(self) -> None:
        self._clips = _history()
        self.on_search("")
