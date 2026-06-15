import os
import re

from fabric import Application
from fabric.notifications import Notifications, Notification, NotificationCloseReason
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label
from fabric.widgets.image import Image
from fabric.utils.helpers import monitor_file

from gi.repository import GLib, GdkPixbuf  # type: ignore

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

NOTIF_WIDTH = 360
ICON_SIZE = 26
DEFAULT_TIMEOUT_MS = 5000

_MARKUP_RE = re.compile(r"<[^>]+>")


def _plain(text: str) -> str:
    return _MARKUP_RE.sub("", text).strip()


# ── notification card ──────────────────────────────────────────────────────────

class NotificationCard(Box):
    def __init__(self, notif: Notification):
        urgency_class = ("notif-low", "notif-normal", "notif-critical")[min(notif.urgency, 2)]
        super().__init__(
            orientation="vertical",
            spacing=6,
            style_classes=f"notif-card {urgency_class}",
            h_expand=True,
        )
        self._notif = notif
        self._build()

    def _build(self):
        n = self._notif
        icon_tile = Box(
            style_classes="notif-icon-tile",
            v_align="start",
            h_align="center",
            children=[self._make_icon()],
        )

        app_name = Label(
            label=(n.app_name or "").upper(),
            h_align="start",
            style_classes="notif-app-name",
            h_expand=True,
            x_align=0.0,
        )
        summary = Label(
            label=_plain(n.summary or ""),
            h_align="start",
            style_classes="notif-summary",
            ellipsization="end",
            h_expand=True,
        )
        title_col = Box(
            orientation="vertical",
            spacing=1,
            h_expand=True,
            v_align="center",
            children=[app_name, summary],
        )

        close_btn = Button(label="×", style_classes="notif-close")
        close_btn.connect("clicked", lambda *_: n.close("dismissed-by-user"))

        self.add(Box(
            orientation="horizontal",
            spacing=10,
            style_classes="notif-header",
            h_expand=True,
            children=[icon_tile, title_col, close_btn],
        ))

        if n.body:
            self.add(Label(
                label=_plain(n.body),
                h_align="start",
                v_align="start",
                style_classes="notif-body",
                line_wrap="word-char",
                h_expand=True,
                x_align=0.0,
            ))

        visible_actions = [a for a in n.actions if a.identifier != "default"]
        if visible_actions:
            action_row = Box(
                orientation="horizontal",
                spacing=4,
                style_classes="notif-actions",
                h_expand=True,
            )
            for action in visible_actions:
                btn = Button(label=action.label, style_classes="notif-action-btn")
                btn.connect(
                    "clicked",
                    lambda *_, a=action: (a.invoke(), n.close("dismissed-by-user")),
                )
                action_row.add(btn)
            self.add(action_row)

    def _make_icon(self) -> Image:
        try:
            pixbuf = self._notif.image_pixbuf
            if pixbuf:
                w, h = pixbuf.get_width(), pixbuf.get_height()
                scale = ICON_SIZE / max(w, h, 1)
                pixbuf = pixbuf.scale_simple(
                    max(1, int(w * scale)),
                    max(1, int(h * scale)),
                    GdkPixbuf.InterpType.BILINEAR,
                )
                return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE], style_classes="notif-icon")
        except Exception:
            pass

        icon_name = self._notif.app_icon
        if icon_name:
            if os.path.isabs(icon_name) and os.path.isfile(icon_name):
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, ICON_SIZE, ICON_SIZE)
                    return Image(pixbuf=pixbuf, size=[ICON_SIZE, ICON_SIZE], style_classes="notif-icon")
                except Exception:
                    pass
            else:
                return Image(icon_name=icon_name, icon_size=ICON_SIZE, style_classes="notif-icon")

        return Image(icon_name="dialog-information", icon_size=ICON_SIZE, style_classes="notif-icon")


# ── daemon window ──────────────────────────────────────────────────────────────

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
        self.set_size_request(NOTIF_WIDTH, -1)

        self._container = Box(
            orientation="vertical",
            spacing=8,
            v_align="start",
            h_align="end",
            style_classes="notif-container",
        )
        self.children = self._container

        self._active_cards: dict[int, NotificationCard] = {}
        self._timeout_srcs: dict[int, int] = {}

        self._service = Notifications()
        self._service.connect("notification-added", self._on_notif_added)
        self._service.connect("notification-removed", self._on_notif_removed)

        self.hide()

    def _on_notif_added(self, service: Notifications, notif_id: int):
        notif = service.get_notification_from_id(notif_id)
        if notif is None:
            return

        # replace if replaces_id targets an existing card
        if notif.replaces_id and notif.replaces_id in self._active_cards:
            self._remove_card(notif.replaces_id)

        card = NotificationCard(notif)
        self._active_cards[notif_id] = card
        self._container.add(card)
        card.show_all()
        self.show()

        # determine timeout: -1 = use default, 0 = never, >0 = use value (ms)
        timeout = notif.timeout if notif.timeout != -1 else DEFAULT_TIMEOUT_MS
        if notif.urgency == 2:  # critical — never auto-expire
            timeout = 0
        if timeout > 0:
            src = GLib.timeout_add(timeout, self._make_expire_cb(notif_id, notif))
            self._timeout_srcs[notif_id] = src

    def _make_expire_cb(self, notif_id: int, notif: Notification):
        def _cb():
            if notif_id in self._active_cards:
                notif.close("expired")
            return False
        return _cb

    def _on_notif_removed(self, _service, notif_id: int):
        if src := self._timeout_srcs.pop(notif_id, None):
            GLib.source_remove(src)
        self._remove_card(notif_id)

    def _remove_card(self, notif_id: int):
        card = self._active_cards.pop(notif_id, None)
        if card:
            self._container.remove(card)
        if not self._active_cards:
            self.hide()


# ── css + entry point ──────────────────────────────────────────────────────────

def load_css(app: Application) -> None:
    try:
        with open(os.path.join(CSS_DIR, "colors-fabric.css")) as f:
            color_css = "\n".join(
                line for line in f.read().splitlines() if "url(" not in line
            )
    except FileNotFoundError:
        color_css = ""

    with open(os.path.join(CSS_DIR, "notifications.css")) as f:
        notif_css = f.read()

    app.set_stylesheet_from_string(color_css + "\n" + notif_css, base_path=CSS_DIR)


if __name__ == "__main__":
    daemon = NotificationDaemon()
    app = Application("notifications", daemon)
    load_css(app)

    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )

    app.run()
