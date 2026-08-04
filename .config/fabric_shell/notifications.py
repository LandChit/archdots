#!/usr/bin/env python3
"""Notification daemon — stacked glass cards in the top-right corner."""

import os
import re

from fabric import Application
from fabric.notifications import Notifications, Notification
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.image import Image
from fabric.widgets.label import Label

from gi.repository import GLib, GdkPixbuf  # type: ignore

import common

WIDTH = 360
ICON_SIZE = 26
DEFAULT_TIMEOUT_MS = 5000
URGENCY_CLASSES = ("notif-low", "notif-normal", "notif-critical")
CRITICAL = 2

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


class NotificationDaemon(Window):
    def __init__(self):
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

        service = Notifications()
        service.connect("notification-added", self._on_added)
        service.connect("notification-removed", self._on_removed)
        self.hide()

    def _on_added(self, service: Notifications, notif_id: int) -> None:
        notif = service.get_notification_from_id(notif_id)
        if notif is None:
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


if __name__ == "__main__":
    app = Application("notifications", NotificationDaemon())
    common.style_application(app, "notifications.css")
    app.run()
