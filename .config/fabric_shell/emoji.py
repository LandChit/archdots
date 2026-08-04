"""Emoji picker — searchable grid with a group rail, backed by a cached JSON set."""

import json
import os
import subprocess
import threading
import urllib.request

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.flowbox import FlowBox
from fabric.widgets.label import Label
from fabric.widgets.scrolledwindow import ScrolledWindow

from gi.repository import Gdk, GLib  # type: ignore

from common import Panel, Selection, UsageCounts, make_scroller

EMOJI_URL = "https://raw.githubusercontent.com/LandChit/unicode-emoji-json/refs/heads/main/data-by-emoji.json"
CACHE_FILE = os.path.expanduser("~/.cache/emoji-picker/data-by-emoji.json")
COUNTS_PATH = "~/.local/share/fabric-launcher/emoji-counts.json"

COLUMNS = 7
CELL_SIZE = 46
GRID_WIDTH = COLUMNS * CELL_SIZE
RAIL_WIDTH = 52
WIDTH = GRID_WIDTH + RAIL_WIDTH + 36
HEIGHT = 540

# Icon-only rail buttons — fixed-width glyphs keep the window width independent
# of how long the group names are. The full name lives in the tooltip.
GROUP_ICONS = {
    "All": "▦",
    "Smileys & Emotion": "🙂",
    "People & Body": "👤",
    "Animals & Nature": "🐾",
    "Food & Drink": "🍴",
    "Travel & Places": "✈",
    "Activities": "⚽",
    "Objects": "💡",
    "Symbols": "🔣",
    "Flags": "🚩",
    "Component": "🖐",
}


# ── cache ──────────────────────────────────────────────────────────────────────

def _write_cache(data: bytes) -> None:
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    tmp = CACHE_FILE + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, CACHE_FILE)  # atomic, so a torn download is never read


def _fetch() -> bytes:
    with urllib.request.urlopen(EMOJI_URL, timeout=20) as response:
        data = response.read()
    json.loads(data)  # validate the whole payload before it touches the cache
    return data


def _ensure_cache() -> None:
    """Blocking first-run download. No-op once the cache exists."""
    if os.path.isfile(CACHE_FILE):
        return
    try:
        _write_cache(_fetch())
    except Exception as e:
        print(f"[emoji] could not download emoji data: {e}")


def _refresh_cache(on_updated) -> None:
    """Re-fetch in the background, notifying only if the data actually changed."""
    def run():
        try:
            data = _fetch()
            try:
                with open(CACHE_FILE, "rb") as f:
                    if f.read() == data:
                        return
            except FileNotFoundError:
                pass
            _write_cache(data)
            GLib.idle_add(on_updated)
        except Exception:
            pass

    threading.Thread(target=run, daemon=True).start()


def _load() -> list[tuple[str, str, str]]:
    """Cached emoji as (char, name, group)."""
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []
    return [(char, info["name"], info.get("group", "")) for char, info in data.items()]


# ── picker ─────────────────────────────────────────────────────────────────────

class EmojiPicker(Panel):
    def __init__(self):
        super().__init__(
            title="fabric-emoji",
            width=WIDTH,
            height=HEIGHT,
            icon=Label(label="😀", style_classes="emoji-search-icon"),
            placeholder="Search emoji…",
        )
        _ensure_cache()
        self._counts = UsageCounts(COUNTS_PATH)
        self._emojis = self._sorted_emojis()
        self._cells: list[Button] = []
        self._rail_buttons: dict[str, Button] = {}
        self._query = ""
        self._group = "All"

        self._grid = FlowBox(
            row_spacing=2,
            column_spacing=2,
            orientation="horizontal",
            style_classes="emoji-grid",
            h_align="start",
            v_align="start",
            h_expand=False,
            v_expand=False,
        )
        self._grid.set_max_children_per_line(COLUMNS)
        self._grid.set_min_children_per_line(COLUMNS)
        self._grid.set_homogeneous(True)
        self._grid.set_size_request(GRID_WIDTH, -1)
        self._grid.set_filter_func(lambda child: self._matches(child.get_child()))

        scroller = make_scroller(self._grid, GRID_WIDTH, HEIGHT - 60)
        # every cell is wrapped in a FlowBoxChild — that wrapper carries the
        # allocation the scroll maths needs, not the button
        self._selection = Selection(
            scroller, "emoji-selected", target=lambda cell: cell.get_parent()
        )

        self._section = Label(
            label="ALL", h_align="start", style_classes="section-label"
        )
        grid_column = Box(
            orientation="vertical", spacing=0, children=[self._section, scroller]
        )
        content = Box(
            orientation="horizontal",
            spacing=6,
            h_expand=True,
            v_expand=True,
            children=[grid_column, self._build_rail()],
        )

        self.set_body(content)
        self._populate()
        self._apply_filter()
        self.show_all()
        self.hide()

        _refresh_cache(self._reload)

    def _sorted_emojis(self) -> list[tuple[str, str, str]]:
        return sorted(_load(), key=lambda e: (self._counts.rank(e[0]), e[1]))

    # ── group rail ──────────────────────────────────────────────────────────

    def _build_rail(self) -> ScrolledWindow:
        groups = ["All"] + list(dict.fromkeys(g for _, _, g in self._emojis if g))
        for group in groups:
            button = Button(
                label=GROUP_ICONS.get(group, group[:1]),
                style_classes="group-button group-active"
                if group == "All"
                else "group-button",
            )
            button.set_tooltip_text(group)
            button.connect("clicked", lambda _, g=group: self._set_group(g))
            self._rail_buttons[group] = button

        return ScrolledWindow(
            child=Box(
                orientation="vertical",
                spacing=4,
                style_classes="group-inner",
                children=list(self._rail_buttons.values()),
                v_align="start",
            ),
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            overlay_scroll=True,
            style_classes="group-scroll",
            v_expand=True,
            min_content_size=(RAIL_WIDTH, HEIGHT - 60),
            max_content_size=(RAIL_WIDTH, HEIGHT - 60),
        )

    def _set_group(self, group: str) -> None:
        if previous := self._rail_buttons.get(self._group):
            previous.remove_style_class("group-active")
        self._group = group
        if button := self._rail_buttons.get(group):
            button.add_style_class("group-active")
        self._section.set_label(group.split(" & ")[0].upper())
        self._apply_filter()

    # ── grid ────────────────────────────────────────────────────────────────

    def _populate(self) -> None:
        for char, name, group in self._emojis:
            cell = Button(
                child=Label(
                    label=char,
                    h_align="center",
                    v_align="center",
                    style_classes="emoji-char",
                ),
                style_classes="emoji-button",
                h_expand=False,
                v_expand=False,
            )
            cell.set_tooltip_text(name)
            cell.char = char  # type: ignore[attr-defined]
            cell.term = name.casefold()  # type: ignore[attr-defined]
            cell.group = group  # type: ignore[attr-defined]
            cell.connect("clicked", lambda _, c=cell: self._pick(c))
            self._cells.append(cell)
            self._grid.add(cell)
        self._grid.show_all()

    def _reload(self) -> None:
        """Runs on the main loop once a background cache refresh has landed."""
        emojis = self._sorted_emojis()
        if len(emojis) == len(self._emojis):
            return  # same size — treat as no meaningful change
        for child in self._grid.get_children():
            self._grid.remove(child)
        self._cells.clear()
        self._emojis = emojis
        self._populate()
        self._apply_filter()

    def _matches(self, cell) -> bool:
        return (not self._query or self._query in cell.term) and (
            self._group == "All" or self._group == cell.group
        )

    def _apply_filter(self) -> None:
        self._grid.invalidate_filter()
        self._selection.reset(cell for cell in self._cells if self._matches(cell))

    def on_search(self, query: str) -> None:
        self._query = query.strip().casefold()
        self._apply_filter()

    # ── activation ──────────────────────────────────────────────────────────

    def on_key(self, event) -> bool:
        # up/down step a whole row, left/right step one cell
        moves = {
            Gdk.KEY_Up: -COLUMNS,
            Gdk.KEY_Down: COLUMNS,
            Gdk.KEY_Left: -1,
            Gdk.KEY_Right: 1,
        }
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._pick(self._selection.current)
        elif event.keyval in moves:
            self._selection.move(moves[event.keyval])
        else:
            return False
        return True

    def _pick(self, cell) -> None:
        if cell is None:
            return
        self._counts.bump(cell.char)
        subprocess.run(["wl-copy"], input=cell.char.encode("utf-8"), check=False)
        self.dismiss()

    # ── panel hooks ─────────────────────────────────────────────────────────

    def on_reveal(self) -> None:
        self._counts.reload()
        self._query = ""
        if self._group != "All":
            self._set_group("All")
        else:
            self._apply_filter()
