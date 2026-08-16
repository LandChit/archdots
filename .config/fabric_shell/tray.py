"""System tray that does not vandalise the process-wide icon theme.

fabric's tray resolves an item's icon through `SystemTrayItemService.icon_theme`,
which does this (`fabric/system_tray/service.py`):

    self._icon_theme = Gtk.IconTheme.get_default()
    self._icon_theme.set_search_path([search_path])   # if the item ships one

That is the **shared, process-wide** icon theme, and `set_search_path` *replaces*
the search path rather than adding to it. So a single tray item advertising its
own `IconThemePath` — spotify does — leaves the whole daemon with an icon theme
that can only see that one directory. Every icon lookup afterwards fails: the
tray, the launcher's app icons, notification icons. They all fall back to a
placeholder, which looks exactly like "everything reverted to default", and it
comes straight back after a restart because the same item re-registers.

So this module resolves icons itself and never calls fabric's `icon_theme`:

    1. the item's own pixmap, if it sent one (nothing to look up)
    2. its icon name, in a PRIVATE theme built from the pristine search path
       plus the item's own directory
    3. a generic glyph, so an item with no usable icon is still clickable

`_PRISTINE_SEARCH_PATH` is captured at import, before any item can register, so
a theme already clobbered by an earlier fabric call cannot poison it.
"""

from fabric.system_tray.widgets import SystemTray, SystemTrayItem

from gi.repository import GdkPixbuf, Gtk  # type: ignore

FALLBACK_ICON = "application-x-executable"

# Captured before any tray item exists — see the module docstring.
_PRISTINE_SEARCH_PATH: list[str] = list(
    Gtk.IconTheme.get_default().get_search_path() or []
)


def _theme_for(extra_path: str | None) -> Gtk.IconTheme:
    """A private icon theme: the real search path, plus the item's own."""
    theme = Gtk.IconTheme.new()

    settings = Gtk.Settings.get_default()
    if settings is not None:
        name = settings.get_property("gtk-icon-theme-name")
        if name:
            theme.set_custom_theme(name)

    paths = list(_PRISTINE_SEARCH_PATH)
    if extra_path and extra_path not in paths:
        paths.insert(0, extra_path)  # the item's own directory wins
    theme.set_search_path(paths)
    return theme


def restore_default_search_path() -> None:
    """Undo the damage if something has already clobbered the shared theme.

    Nothing in this module causes it, but fabric will the moment any other code
    touches `item.icon_theme`, and the launcher's icons share that theme.
    """
    theme = Gtk.IconTheme.get_default()
    if list(theme.get_search_path() or []) != _PRISTINE_SEARCH_PATH:
        theme.set_search_path(_PRISTINE_SEARCH_PATH)


class SafeTrayItem(SystemTrayItem):
    """A tray item that renders without touching the shared icon theme."""

    def do_update_properties(self, *_):
        item = self._item

        # NeedsAttention swaps in the attention icon, as fabric's own code does
        try:
            attention = item.status == "NeedsAttention"
        except Exception:
            attention = False

        name = pixmap = None
        try:
            if attention and (item.attention_icon_name or item.attention_icon_pixmap):
                name, pixmap = item.attention_icon_name, item.attention_icon_pixmap
            else:
                name, pixmap = item.icon_name, item.icon_pixmap
        except Exception:
            pass

        pixbuf = self._pixbuf(name, pixmap)
        if pixbuf is not None:
            self._image.set_from_pixbuf(pixbuf)
        else:
            self._image.set_from_icon_name(FALLBACK_ICON, self._icon_size)

        self.set_tooltip_markup(self._label())
        return None

    def _pixbuf(self, name, pixmap) -> GdkPixbuf.Pixbuf | None:
        # an embedded pixmap needs no theme at all, so it is tried first
        if pixmap is not None:
            try:
                pixbuf = pixmap.as_pixbuf(self._icon_size, "bilinear")
                if pixbuf is not None:
                    return pixbuf
            except Exception:
                pass

        if not name:
            return None

        # an absolute path is a file, not a theme name
        if name.startswith("/"):
            try:
                return GdkPixbuf.Pixbuf.new_from_file_at_size(
                    name, self._icon_size, self._icon_size
                )
            except Exception:
                return None

        try:
            theme = _theme_for(self._item.icon_theme_path)
            return theme.load_icon(name, self._icon_size, Gtk.IconLookupFlags.FORCE_SIZE)
        except Exception as e:
            print(f"[tray] {self._label()}: no icon for {name!r} ({e})")
            return None

    def _label(self) -> str:
        try:
            return self._item.title or self._item.identifier or "Unknown"
        except Exception:
            return "Unknown"


class SafeSystemTray(SystemTray):
    """SystemTray that builds SafeTrayItems instead of the fragile ones."""

    def on_item_added(self, _watcher, identifier: str):
        item = self._watcher.items.get(identifier)
        if not item:
            return

        try:
            button = SafeTrayItem(item, self._icon_size)
        except Exception as e:
            # nothing else should be able to take the rest of the tray down
            print(f"[tray] could not add {identifier}: {e}")
            return

        self.add(button)
        button.show_all()
        self._items[item.identifier] = button
        # belt and braces: if anything did reach fabric's icon_theme, put the
        # shared search path back before the launcher needs it
        restore_default_search_path()
