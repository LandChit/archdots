import os
import re
import subprocess

from fabric import Application
from fabric.widgets.scrolledwindow import ScrolledWindow
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.entry import Entry
from fabric.widgets.image import Image
from fabric.widgets.label import Label
from fabric.utils.helpers import monitor_file

from gi.repository import GdkPixbuf, GLib  # type: ignore

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

THUMB_SIZE = 48
ICON_SIZE = 20
WINDOW_WIDTH = 500
WINDOW_HEIGHT = 700
MAX_THUMB_BYTES = 300 * 1024  # skip thumbnail decoding for entries larger than 300 KB


def _parse_binary_meta(content: str) -> tuple[bool, str, int]:
    """Parse image format and byte size from a cliphist binary-data preview string."""
    m = re.match(r"\[\[ binary data (\d+(?:\.\d+)?)\s*(B|KiB|MiB)\s+(\w+)", content)
    if not m:
        return False, "", 0
    val, unit, fmt = float(m.group(1)), m.group(2), m.group(3).lower()
    size = int(val * {"B": 1, "KiB": 1024, "MiB": 1024 * 1024}[unit])
    return True, fmt, size


def _parse_image_dims(content: str) -> str:
    m = re.search(r"(\d+x\d+)", content)
    return m.group(1) if m else ""


def _load_cliphist() -> list[tuple[str, str, bool, str, int]]:
    """
    Returns list of (original_line, preview, is_image, img_format, size_bytes).
    original_line is the raw "id\\tpreview" line fed back to `cliphist decode`.
    """
    try:
        result = subprocess.run(
            ["cliphist", "list"],
            capture_output=True, text=True, timeout=5,
        )
        entries = []
        for line in result.stdout.splitlines():
            if "\t" not in line:
                continue
            _clip_id, content = line.split("\t", 1)
            is_image, fmt, size = _parse_binary_meta(content)
            entries.append((line, content, is_image, fmt, size))
        return entries
    except Exception:
        return []


def _decode_line(original_line: str) -> bytes | None:
    """Pipe the original cliphist list line to `cliphist decode` and return raw bytes."""
    try:
        result = subprocess.run(
            ["cliphist", "decode"],
            input=original_line.encode(),
            capture_output=True, timeout=5,
        )
        return result.stdout if result.returncode == 0 else None
    except Exception:
        return None


def _copy_entry(original_line: str, is_image: bool, img_format: str = "png"):
    """Decode a cliphist entry and send it to wl-copy."""
    try:
        data = _decode_line(original_line)
        if not data:
            return
        cmd = ["wl-copy", f"--type=image/{img_format}"] if is_image else ["wl-copy"]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        proc.communicate(data)
    except Exception:
        pass


class ClipboardManager(Window):
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
        self._dismiss_timer_id: int | None = None
        self.add_style_class("window")
        self.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT)
        self.set_resizable(False)

        self._all_entries = _load_cliphist()
        self._items: list[Button] = []
        self._entry_meta: list[tuple[str, bool, str]] = []  # (original_line, is_image, fmt)
        self._selected_index: int | None = None

        self._search_entry = Entry(
            placeholder="Search clipboard…",
            h_expand=True,
            style_classes="search-entry",
        )
        self._search_entry.set_can_focus(True)
        self._search_entry.connect("changed", self._on_search_changed)

        self._list_box = Box(
            orientation="vertical",
            spacing=4,
            style_classes="clip-list",
            h_expand=True,
            v_expand=False,
            v_align="start",
        )

        self._scroller = ScrolledWindow(
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            child=self._list_box,
            overlay_scroll=True,
            min_content_size=(WINDOW_WIDTH - 20, WINDOW_HEIGHT - 60),
            max_content_size=(WINDOW_WIDTH - 20, WINDOW_HEIGHT - 60),
            style_classes="app-scroll",
            h_align="fill",
            v_align="start",
            h_expand=True,
        )

        search_row = Box(
            spacing=12,
            orientation="horizontal",
            style_classes="search-row",
            children=[
                Image(icon_name="edit-paste", icon_size=ICON_SIZE),
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
        )

        self.connect("key-press-event", self._on_key_press)
        self._refresh_list("")
        self.show_all()
        if self._daemon_mode:
            self.hide()
        else:
            self._search_entry.grab_focus()

    # ── list management ────────────────────────────────────────────────────

    def _on_search_changed(self, *_):
        self._refresh_list(self._search_entry.get_text() or "")

    def _refresh_list(self, query: str):
        for child in self._list_box.get_children():
            self._list_box.remove(child)

        self._items = []
        self._entry_meta = []
        self._selected_index = None

        q = query.strip().casefold()
        for original_line, content, is_image, fmt, size in self._all_entries:
            if q and q not in content.casefold():
                continue
            btn = self._build_item(original_line, content, is_image, fmt, size)
            self._items.append(btn)
            self._entry_meta.append((original_line, is_image, fmt))
            self._list_box.add(btn)

        self._list_box.show_all()

    # ── item builders ──────────────────────────────────────────────────────

    def _build_item(self, original_line: str, content: str, is_image: bool, fmt: str, size: int) -> Button:
        if is_image:
            thumb = self._make_image_thumb(original_line, fmt, size)
            dims = _parse_image_dims(content)
            preview = f"[image/{fmt}  {dims}]" if dims else f"[image/{fmt}]"
        else:
            thumb = Image(
                icon_name="edit-copy",
                icon_size=ICON_SIZE,
                v_align="center",
                style_classes="clip-text-icon",
            )
            preview = content

        label = Label(
            label=preview[:120] + ("…" if len(preview) > 120 else ""),
            ellipsization="end",
            h_align="start",
            v_align="center",
            style_classes="clip-label",
            h_expand=True,
        )

        row = Box(
            orientation="horizontal",
            spacing=10,
            style_classes="clip-item",
            h_expand=True,
            v_align="center",
            children=[thumb, label],
        )

        btn = Button(child=row, style_classes="clip-button", h_expand=True)
        btn.connect("clicked", lambda *_: self._copy_and_close(original_line, is_image, fmt))
        return btn

    def _make_image_thumb(self, original_line: str, fmt: str, size: int) -> Image:
        if size <= MAX_THUMB_BYTES:
            try:
                data = _decode_line(original_line)
                if data:
                    loader = GdkPixbuf.PixbufLoader()
                    loader.write(data)
                    loader.close()
                    pixbuf = loader.get_pixbuf()
                    if pixbuf:
                        w, h = pixbuf.get_width(), pixbuf.get_height()
                        scale = THUMB_SIZE / max(w, h, 1)
                        pixbuf = pixbuf.scale_simple(
                            max(1, int(w * scale)),
                            max(1, int(h * scale)),
                            GdkPixbuf.InterpType.BILINEAR,
                        )
                        return Image(
                            pixbuf=pixbuf,
                            size=[THUMB_SIZE, THUMB_SIZE],
                            v_align="center",
                            style_classes="clip-thumb",
                        )
            except Exception:
                pass
        return Image(
            icon_name="image-x-generic",
            icon_size=ICON_SIZE,
            v_align="center",
            style_classes="clip-text-icon",
        )

    # ── keyboard navigation ────────────────────────────────────────────────

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
            self._items[self._selected_index].remove_style_class("clip-selected")
        self._selected_index = index
        self._items[index].add_style_class("clip-selected")
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

    # ── actions ────────────────────────────────────────────────────────────

    def _activate_selected(self):
        # No visual preselection on open — Enter falls back to the newest entry
        index = self._selected_index if self._selected_index is not None else 0
        if not self._entry_meta:
            return
        original_line, is_image, fmt = self._entry_meta[index]
        self._copy_and_close(original_line, is_image, fmt)

    def _copy_and_close(self, original_line: str, is_image: bool, fmt: str):
        _copy_entry(original_line, is_image, fmt)
        self._quit()

    # ── daemon support ─────────────────────────────────────────────────────────

    def dismiss(self) -> None:
        if self._dismiss_timer_id is not None:
            GLib.source_remove(self._dismiss_timer_id)
        self.add_style_class("anim-out")
        self._dismiss_timer_id = GLib.timeout_add(220, self._finish_dismiss)

    def _finish_dismiss(self) -> bool:
        self._dismiss_timer_id = None
        self.hide()
        return False

    def reveal(self) -> None:
        if self._dismiss_timer_id is not None:
            GLib.source_remove(self._dismiss_timer_id)
            self._dismiss_timer_id = None
        self._all_entries = _load_cliphist()
        self._search_entry.set_text("")
        self._refresh_list("")
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

    with open(os.path.join(CSS_DIR, "clipboard.css")) as f:
        clip_css = f.read()

    app.set_stylesheet_from_string(color_css + "\n" + clip_css, base_path=CSS_DIR)


if __name__ == "__main__":
    manager = ClipboardManager()
    app = Application("clipboard", manager)
    manager._app_ref = app
    load_css(app)

    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )

    app.run()
