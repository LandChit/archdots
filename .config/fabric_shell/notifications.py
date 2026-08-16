#!/usr/bin/env python3
"""Notifications — popup cards in the top-right corner, plus their history.

Three pieces share one DBus service through `NotificationStore`:

    NotificationStore    the service, the history list and the DND flag
    NotificationPopups   the transient stack that appears as things arrive
    NotificationCenter   the scrollable history, opened from a keybind

All three live inside the daemon process, so the control centre can flip DND
by calling the store directly rather than inventing another socket message.
"""

import os
import re

from fabric.notifications import Notifications, Notification
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label

from gi.repository import GLib, GdkPixbuf  # type: ignore

from common import Overlay, make_scroller

WIDTH = 360
ICON_SIZE = 26
DEFAULT_TIMEOUT_MS = 5000
URGENCY_CLASSES = ("notif-low", "notif-normal", "notif-critical")
CRITICAL = 2

# history panel
CENTER_WIDTH = 400
CENTER_HEIGHT = 520
MAX_HISTORY = 50

_MARKUP_RE = re.compile(r"<[^>]+>")


def _plain(text: str) -> str:
    """Notification text may carry Pango markup the card does not render."""
    return _MARKUP_RE.sub("", text or "").strip()


def _scaled(pixbuf) -> Image:
    width, height = pixbuf.get_width(), pixbuf.get_height()
    scale = ICON_SIZE / max(width, height, 1)
    pixbuf = pixbuf.scale_simple(
        max(1, int(width * scale)),
        max(1, int(height * scale)),
        GdkPixbuf.InterpType.BILINEAR,
    )
    return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE], style_classes="notif-icon")


class NotificationCard(Box):
    def __init__(self, notif: Notification):
        super().__init__(
            orientation="vertical",
            spacing=6,
            style_classes=f"notif-card {URGENCY_CLASSES[min(notif.urgency, CRITICAL)]}",
            h_expand=True,
        )
        self.add(self._header(notif))

        if notif.body:
            self.add(
                Label(
                    label=_plain(notif.body),
                    h_align="start",
                    v_align="start",
                    style_classes="notif-body",
                    line_wrap="word-char",
                    h_expand=True,
                    x_align=0.0,
                )
            )

        # the "default" action fires on card click, so it gets no button
        actions = [a for a in notif.actions if a.identifier != "default"]
        if actions:
            row = Box(
                orientation="horizontal",
                spacing=4,
                style_classes="notif-actions",
                h_expand=True,
            )
            for action in actions:
                button = Button(label=action.label, style_classes="notif-action-btn")
                button.connect(
                    "clicked",
                    lambda *_, a=action: (a.invoke(), notif.close("dismissed-by-user")),
                )
                row.add(button)
            self.add(row)

    def _header(self, notif: Notification) -> Box:
        close = Button(label="×", style_classes="notif-close")
        close.connect("clicked", lambda *_: notif.close("dismissed-by-user"))

        return Box(
            orientation="horizontal",
            spacing=10,
            style_classes="notif-header",
            h_expand=True,
            children=[
                Box(
                    style_classes="notif-icon-tile",
                    v_align="start",
                    h_align="center",
                    children=[self._icon(notif)],
                ),
                Box(
                    orientation="vertical",
                    spacing=1,
                    h_expand=True,
                    v_align="center",
                    children=[
                        Label(
                            label=(notif.app_name or "").upper(),
                            h_align="start",
                            style_classes="notif-app-name",
                            h_expand=True,
                            x_align=0.0,
                        ),
                        Label(
                            label=_plain(notif.summary),
                            h_align="start",
                            style_classes="notif-summary",
                            ellipsization="end",
                            h_expand=True,
                        ),
                    ],
                ),
                close,
            ],
        )

    @staticmethod
    def _icon(notif: Notification) -> Image:
        """The notification's own image, else its app icon, else a generic glyph."""
        try:
            if pixbuf := notif.image_pixbuf:
                return _scaled(pixbuf)
        except Exception:
            pass

        name = notif.app_icon
        if name and os.path.isabs(name) and os.path.isfile(name):
            try:
                return _scaled(
                    GdkPixbuf.Pixbuf.new_from_file_at_size(name, ICON_SIZE, ICON_SIZE)
                )
            except Exception:
                pass
        elif name:
            return Image(icon_name=name, icon_size=ICON_SIZE, style_classes="notif-icon")

        return Image(
            icon_name="dialog-information",
            icon_size=ICON_SIZE,
            style_classes="notif-icon",
        )


class HistoryEntry:
    """One past notification, kept after the live Notification is closed."""

    def __init__(self, notif: Notification):
        self.app_name = (notif.app_name or "").upper()
        self.summary = _plain(notif.summary)
        self.body = _plain(notif.body)
        self.urgency = min(notif.urgency, CRITICAL)
        self.time = GLib.DateTime.new_now_local().format("%H:%M")


class NotificationStore:
    """The DBus service, the history and the DND flag, shared by both windows.

    DND is deliberately not persisted: a shell restart clears it, so a muted
    session can never outlive the reason it was muted.
    """

    def __init__(self):
        self.service = Notifications()
        self.history: list[HistoryEntry] = []
        self.dnd = False
        self._listeners: list = []

    def subscribe(self, callback) -> None:
        """Register a callback fired whenever the history or DND flag changes."""
        self._listeners.append(callback)

    def changed(self) -> None:
        for callback in self._listeners:
            callback()

    def remember(self, notif: Notification) -> None:
        self.history.insert(0, HistoryEntry(notif))
        del self.history[MAX_HISTORY:]
        self.changed()

    def clear(self) -> None:
        self.history.clear()
        self.changed()

    def set_dnd(self, value: bool) -> None:
        self.dnd = value
        self.changed()


class NotificationPopups(Window):
    """The transient stack — one card per live notification, top right."""

    def __init__(self, store: NotificationStore):
        super().__init__(
            title="fabric-notifications",
            layer="overlay",
            anchor="top right",
            margin="10px 10px 0px 0px",
            exclusivity="none",
            keyboard_mode="on-demand",
            visible=False,
        )
        self.add_style_class("notif-window")
        self.set_size_request(WIDTH, -1)

        self._store = store
        self._stack = Box(
            orientation="vertical",
            spacing=8,
            v_align="start",
            h_align="end",
            style_classes="notif-container",
        )
        self.children = self._stack

        self._cards: dict[int, NotificationCard] = {}
        self._timeouts: dict[int, int] = {}

        store.service.connect("notification-added", self._on_added)
        store.service.connect("notification-removed", self._on_removed)
        self.hide()

    def _on_added(self, service: Notifications, notif_id: int) -> None:
        notif = service.get_notification_from_id(notif_id)
        if notif is None:
            return

        # recorded even while silenced — DND hides the popup, it does not
        # throw the notification away
        self._store.remember(notif)
        if self._store.dnd:
            return

        # an app updating its own notification replaces the card in place
        if notif.replaces_id in self._cards:
            self._drop(notif.replaces_id)

        card = NotificationCard(notif)
        self._cards[notif_id] = card
        self._stack.add(card)
        card.show_all()
        self.show()

        # timeout: -1 means "use the default", 0 means "never expire"
        timeout = DEFAULT_TIMEOUT_MS if notif.timeout == -1 else notif.timeout
        if notif.urgency == CRITICAL:
            timeout = 0  # critical notifications wait for the user
        if timeout > 0:
            self._timeouts[notif_id] = GLib.timeout_add(
                timeout, lambda: self._expire(notif_id, notif)
            )

    def _expire(self, notif_id: int, notif: Notification) -> bool:
        if notif_id in self._cards:
            notif.close("expired")
        return False

    def _on_removed(self, _service, notif_id: int) -> None:
        if source := self._timeouts.pop(notif_id, None):
            GLib.source_remove(source)
        self._drop(notif_id)

    def _drop(self, notif_id: int) -> None:
        if card := self._cards.pop(notif_id, None):
            self._stack.remove(card)
        if not self._cards:
            self.hide()

    def dismiss_all(self) -> None:
        """Close every live popup — the centre is taking over the corner.

        Both windows live in the top right and the popups sit on the overlay
        layer, so without this they cover the centre the moment it opens.
        Nothing is lost: the store recorded each one as it arrived.
        """
        for notif_id in list(self._cards):
            notif = self._store.service.get_notification_from_id(notif_id)
            if notif is not None:
                notif.close("dismissed-by-user")
            else:
                self._drop(notif_id)


class HistoryRow(Box):
    """One entry in the notification centre — flatter than a live card."""

    def __init__(self, entry: HistoryEntry):
        super().__init__(
            orientation="vertical",
            spacing=2,
            style_classes=f"notif-history-row {URGENCY_CLASSES[entry.urgency]}",
            h_expand=True,
        )
        self.add(
            Box(
                orientation="horizontal",
                spacing=8,
                h_expand=True,
                children=[
                    # Not ellipsized: inside the scroller GTK hands an
                    # ellipsizing label its minimum width, which clips even a
                    # short app name. The spacer keeps the time pushed right.
                    Label(
                        label=entry.app_name or "NOTIFICATION",
                        style_classes="notif-app-name",
                        h_align="start",
                        x_align=0.0,
                    ),
                    Box(h_expand=True),
                    Label(
                        label=entry.time,
                        style_classes="notif-history-time",
                        h_align="end",
                    ),
                ],
            )
        )
        self.add(
            Label(
                label=entry.summary,
                style_classes="notif-summary",
                h_align="start",
                h_expand=True,
                x_align=0.0,
                ellipsization="end",
            )
        )
        if entry.body:
            self.add(
                Label(
                    label=entry.body,
                    style_classes="notif-body",
                    h_align="start",
                    v_align="start",
                    h_expand=True,
                    x_align=0.0,
                    # x_align places the block; justification aligns the lines
                    # inside it, and a wrapped body centres them without this
                    justification="left",
                    line_wrap="word-char",
                )
            )


class NotificationCenter(Overlay):
    """Scrollable history with a clear-all button and the DND switch."""

    def __init__(self, store: NotificationStore, popups: NotificationPopups):
        super().__init__(
            title="fabric-notification-center",
            layer="top",
            anchor="top right",
            margin="52px 14px 0px 0px",
            keyboard_mode="on-demand",
        )
        self.add_style_class("notif-center-window")

        self._store = store
        self._popups = popups
        self._anim_src: int | None = None

        self._title = Label(
            label="Notifications", style_classes="notif-center-title", h_align="start"
        )
        self._dnd = Button(style_classes="notif-center-toggle")
        self._dnd.connect("clicked", lambda *_: store.set_dnd(not store.dnd))
        self._clear = Button(
            child=Label(label="Clear", style_classes="notif-center-btn-label"),
            style_classes="notif-center-btn",
        )
        self._clear.connect("clicked", lambda *_: store.clear())

        header = Box(
            orientation="horizontal",
            spacing=8,
            style_classes="notif-center-header",
            h_expand=True,
            children=[self._title, self._dnd, self._clear],
        )

        self._list = Box(
            orientation="vertical",
            spacing=6,
            style_classes="notif-history",
            h_expand=True,
            v_align="start",
        )
        # the card's own padding sits outside the scroller, so the list has to
        # ask for less than the window width or the header gets squeezed
        scroller = make_scroller(self._list, CENTER_WIDTH - 64, CENTER_HEIGHT)

        self._card = Box(
            orientation="vertical",
            spacing=10,
            style_classes="notif-center-card",
            children=[header, scroller],
        )
        self.children = Box(
            orientation="vertical",
            style_classes="notif-center-root",
            children=[self._card],
        )

        store.subscribe(self._rebuild)
        self._rebuild()
        self.show_all()
        self.hide()

    # ── contents ────────────────────────────────────────────────────────────

    def _rebuild(self) -> None:
        for child in self._list.get_children():
            self._list.remove(child)

        if self._store.history:
            for entry in self._store.history:
                self._list.add(HistoryRow(entry))
        else:
            self._list.add(
                Label(label="Nothing to catch up on", style_classes="notif-empty")
            )
        self._list.show_all()

        count = len(self._store.history)
        self._title.set_label(f"Notifications · {count}" if count else "Notifications")
        # the toggle is its own status readout, so it says what is on, not what
        # clicking it would do
        self._dnd.set_label("󰂛 Silenced" if self._store.dnd else "󰂚 Alerts on")
        if self._store.dnd:
            self._dnd.add_style_class("active")
        else:
            self._dnd.remove_style_class("active")

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self) -> None:
        self._cancel_anim()
        self._popups.dismiss_all()
        self._rebuild()
        self.add_style_class("anim-out")
        self.show()
        self._anim_src = GLib.timeout_add(16, self._settle)

    def dismiss(self) -> None:
        self._cancel_anim()
        self.add_style_class("anim-out")
        self._anim_src = GLib.timeout_add(180, self._finish_dismiss)

    def _cancel_anim(self) -> None:
        if self._anim_src is not None:
            GLib.source_remove(self._anim_src)
            self._anim_src = None

    def _settle(self) -> bool:
        self._anim_src = None
        self.remove_style_class("anim-out")
        return False

    def _finish_dismiss(self) -> bool:
        self._anim_src = None
        self.hide()
        return False
