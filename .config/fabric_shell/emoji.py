import json
import os
import subprocess
import threading
import urllib.request

from fabric import Application
from fabric.widgets.scrolledwindow import ScrolledWindow
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.entry import Entry
from fabric.widgets.label import Label
from fabric.widgets.flowbox import FlowBox
from fabric.utils.helpers import monitor_file

from gi.repository import GLib  # type: ignore

EMOJI_URL = "https://raw.githubusercontent.com/LandChit/unicode-emoji-json/refs/heads/main/data-by-emoji.json"
CACHE_DIR = os.path.expanduser("~/.cache/emoji-picker")
CACHE_FILE = os.path.join(CACHE_DIR, "data-by-emoji.json")

EMOJI_COUNTS_PATH = os.path.expanduser("~/.local/share/fabric-launcher/emoji-counts.json")


def _load_emoji_counts() -> dict[str, int]:
    try:
        with open(EMOJI_COUNTS_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_emoji_counts(counts: dict[str, int]) -> None:
    os.makedirs(os.path.dirname(EMOJI_COUNTS_PATH), exist_ok=True)
    with open(EMOJI_COUNTS_PATH, "w") as f:
        json.dump(counts, f, indent=2)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

COLUMNS = 7
CELL_SIZE = 46
GRID_WIDTH = COLUMNS * CELL_SIZE
GROUP_COL_WIDTH = 52
WINDOW_WIDTH = GRID_WIDTH + GROUP_COL_WIDTH + 36
WINDOW_HEIGHT = 540
ICON_SIZE = 18

# Icon-only rail buttons (full group name lives in the tooltip) — fixed-size
# glyphs keep the window width independent of group label text
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


# ── cache management ───────────────────────────────────────────────────────────

def _atomic_write(data: bytes):
    tmp = CACHE_FILE + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, CACHE_FILE)


def _ensure_cache():
    """Synchronous first-run download. No-op if cache already exists."""
    if os.path.isfile(CACHE_FILE):
        return
    os.makedirs(CACHE_DIR, exist_ok=True)
    try:
        with urllib.request.urlopen(EMOJI_URL, timeout=20) as resp:
            data = resp.read()
        json.loads(data)  # validate before writing
        _atomic_write(data)
    except Exception as e:
        print(f"[emoji] Failed to download emoji data: {e}")


def _check_and_update_cache(on_updated=None):
    """Background thread: fetch remote JSON and atomically replace cache if changed."""
    def _run():
        try:
            with urllib.request.urlopen(EMOJI_URL, timeout=20) as resp:
                new_data = resp.read()
            json.loads(new_data)  # validate entire payload before touching cache

            try:
                with open(CACHE_FILE, "rb") as f:
                    if f.read() == new_data:
                        return  # identical — nothing to do
            except FileNotFoundError:
                pass

            _atomic_write(new_data)
            if on_updated:
                GLib.idle_add(on_updated)
        except Exception:
            pass

    threading.Thread(target=_run, daemon=True).start()


def _load_emojis() -> list[tuple[str, str, str]]:
    """Returns list of (char, name, group) from cache."""
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            data = json.load(f)
        return [
            (char, info["name"], info.get("group", ""))
            for char, info in data.items()
        ]
    except Exception:
        return []


# ── picker window ──────────────────────────────────────────────────────────────

class EmojiPicker(Window):
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

        self._emoji_counts = _load_emoji_counts()
        raw_emojis = _load_emojis()
        self._all_emojis: list[tuple[str, str, str]] = sorted(
            raw_emojis,
            key=lambda e: (-self._emoji_counts.get(e[0], 0), e[1]),
        )
        self._all_buttons: list[Button] = []
        self._visible_items: list[Button] = []
        self._selected_index: int | None = None
        self._current_query: str = ""
        self._current_group: str = "All"

        # derive ordered group list from data
        seen: dict[str, None] = {}
        for _, _, g in self._all_emojis:
            if g and g not in seen:
                seen[g] = None
        self._groups: list[str] = ["All"] + list(seen.keys())
        self._group_buttons: dict[str, Button] = {}

        self._search_entry = Entry(
            placeholder="Search emoji…",
            h_expand=True,
            style_classes="search-entry",
        )
        self._search_entry.set_can_focus(True)
        self._search_entry.connect("changed", self._on_search_changed)

        self._flowbox = FlowBox(
            row_spacing=2,
            column_spacing=2,
            orientation="horizontal",
            style_classes="emoji-grid",
            h_align="start",
            v_align="start",
            h_expand=False,
            v_expand=False,
        )
        self._flowbox.set_max_children_per_line(COLUMNS)
        self._flowbox.set_min_children_per_line(COLUMNS)
        self._flowbox.set_homogeneous(True)
        self._flowbox.set_size_request(GRID_WIDTH, -1)
        self._flowbox.set_filter_func(self._filter_func)

        self._scroller = ScrolledWindow(
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            child=self._flowbox,
            overlay_scroll=True,
            min_content_size=(GRID_WIDTH, WINDOW_HEIGHT - 60),
            max_content_size=(GRID_WIDTH, WINDOW_HEIGHT - 60),
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
                Label(label="😀", style_classes="emoji-search-icon"),
                self._search_entry,
            ],
            h_expand=True,
        )

        self._section_label = Label(
            label="ALL",
            h_align="start",
            style_classes="section-label",
        )
        grid_col = Box(
            orientation="vertical",
            spacing=0,
            children=[self._section_label, self._scroller],
        )

        content_row = Box(
            orientation="horizontal",
            spacing=6,
            h_expand=True,
            v_expand=True,
            children=[grid_col, self._build_group_col()],
        )

        self.children = Box(
            orientation="vertical",
            spacing=0,
            style_classes="launcher-root",
            children=[search_row, content_row],
            h_expand=True,
            v_expand=True,
            v_align="start",
        )

        self.connect("key-press-event", self._on_key_press)
        self._populate_grid()
        self._apply_filter()
        self.show_all()
        if self._daemon_mode:
            self.hide()
        else:
            self._search_entry.grab_focus()

    # ── group bar ──────────────────────────────────────────────────────────

    def _build_group_col(self) -> ScrolledWindow:
        children = []
        for group in self._groups:
            icon = GROUP_ICONS.get(group, group[:1])
            btn = Button(
                label=icon,
                style_classes="group-button group-active" if group == "All" else "group-button",
            )
            btn.set_tooltip_text(group)
            btn.connect("clicked", lambda _, g=group: self._set_group(g))
            self._group_buttons[group] = btn
            children.append(btn)

        inner = Box(
            orientation="vertical",
            spacing=4,
            style_classes="group-inner",
            children=children,
            v_align="start",
        )
        return ScrolledWindow(
            v_scrollbar_policy="always",
            h_scrollbar_policy="never",
            child=inner,
            overlay_scroll=True,
            style_classes="group-scroll",
            v_expand=True,
            min_content_size=(GROUP_COL_WIDTH, WINDOW_HEIGHT - 60),
            max_content_size=(GROUP_COL_WIDTH, WINDOW_HEIGHT - 60),
        )

    # ── grid population ────────────────────────────────────────────────────

    def _populate_grid(self):
        for char, name, group in self._all_emojis:
            cell = Label(
                label=char,
                h_align="center",
                v_align="center",
                style_classes="emoji-char",
            )
            btn = Button(
                child=cell,
                style_classes="emoji-button",
                h_expand=False,
                v_expand=False,
            )
            btn.set_tooltip_text(name)
            btn._data = {"char": char, "name": name, "group": group}  # type: ignore[attr-defined]
            btn.connect("clicked", lambda _, b=btn: self._copy_and_close(b._data["char"]))
            self._all_buttons.append(btn)
            self._flowbox.add(btn)

        self._flowbox.show_all()

    def reload_emojis(self):
        """Called via GLib.idle_add after background cache update."""
        new_emojis = _load_emojis()
        if len(new_emojis) == len(self._all_emojis):
            return  # same size — treat as no meaningful change
        for child in self._flowbox.get_children():
            self._flowbox.remove(child)
        self._all_buttons.clear()
        self._all_emojis = new_emojis
        self._populate_grid()
        self._apply_filter()

    # ── filtering ──────────────────────────────────────────────────────────

    def _filter_func(self, flowbox_child) -> bool:
        btn = flowbox_child.get_child()
        d = getattr(btn, "_data", {})
        return self._matches(d.get("name", ""), d.get("group", ""))

    def _matches(self, name: str, group: str) -> bool:
        q = self._current_query
        g = self._current_group
        return (not q or q in name) and (g == "All" or g == group)

    def _apply_filter(self):
        for btn in self._all_buttons:
            btn.remove_style_class("emoji-selected")
        self._selected_index = None

        self._flowbox.invalidate_filter()
        self._visible_items = [
            btn for btn in self._all_buttons
            if self._matches(btn._data["name"], btn._data["group"])
        ]

    def _on_search_changed(self, *_):
        self._current_query = self._search_entry.get_text().strip().casefold()
        self._apply_filter()

    def _set_group(self, group: str):
        if old := self._group_buttons.get(self._current_group):
            old.remove_style_class("group-active")
        self._current_group = group
        if btn := self._group_buttons.get(group):
            btn.add_style_class("group-active")
        self._section_label.set_label(group.split(" & ")[0].upper())
        self._apply_filter()

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
            self._move_selection(-COLUMNS)
            return True
        if keyval == 65364:  # Down
            self._move_selection(COLUMNS)
            return True
        if keyval == 65361:  # Left
            self._move_selection(-1)
            return True
        if keyval == 65363:  # Right
            self._move_selection(1)
            return True

        return False

    def _move_selection(self, delta: int):
        if not self._visible_items:
            return
        if self._selected_index is None:
            self._select_index(0)
            return
        self._select_index(self._selected_index + delta)

    def _select_index(self, index: int):
        index = max(0, min(index, len(self._visible_items) - 1))
        if self._selected_index is not None:
            self._visible_items[self._selected_index].remove_style_class("emoji-selected")
        self._selected_index = index
        btn = self._visible_items[index]
        btn.add_style_class("emoji-selected")
        self._scroll_to_button(btn)

    def _scroll_to_button(self, btn: Button):
        fbc = btn.get_parent()  # FlowBoxChild wrapper
        if fbc is None:
            return
        adj = self._scroller.get_vadjustment()
        alloc = fbc.get_allocation()
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
        # No visual preselection on open — Enter falls back to the first match
        index = self._selected_index if self._selected_index is not None else 0
        if not self._visible_items:
            return
        char = self._visible_items[index]._data["char"]
        self._copy_and_close(char)

    def _copy_and_close(self, char: str):
        self._emoji_counts[char] = self._emoji_counts.get(char, 0) + 1
        _save_emoji_counts(self._emoji_counts)
        subprocess.run(["wl-copy"], input=char.encode("utf-8"), check=False)
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
        self._emoji_counts = _load_emoji_counts()
        self._search_entry.set_text("")
        self._current_query = ""
        if self._current_group != "All":
            self._set_group("All")
        else:
            self._apply_filter()
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


# ── css + entry point ──────────────────────────────────────────────────────────

def load_css(app: Application) -> None:
    try:
        with open(os.path.join(CSS_DIR, "colors-fabric.css")) as f:
            color_css = "\n".join(
                line for line in f.read().splitlines() if "url(" not in line
            )
    except FileNotFoundError:
        color_css = ""

    with open(os.path.join(CSS_DIR, "emoji.css")) as f:
        emoji_css = f.read()

    app.set_stylesheet_from_string(color_css + "\n" + emoji_css, base_path=CSS_DIR)


if __name__ == "__main__":
    _ensure_cache()

    picker = EmojiPicker()
    app = Application("emoji-picker", picker)
    picker._app_ref = app

    _check_and_update_cache(on_updated=picker.reload_emojis)

    load_css(app)
    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )

    app.run()
