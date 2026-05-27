import os
import subprocess

from fabric import Application
from fabric.widgets.wayland import WaylandWindow as Window
from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label
from fabric.utils.helpers import monitor_file

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSS_DIR = os.path.join(BASE_DIR, "css")

ACTIONS = [
    {"label": "Lock", "icon": "󰍁", "cmd": ["loginctl", "lock-session"], "style": ""},
    {
        "label": "Logout",
        "icon": "󰍃",
        "cmd": ["hyprctl", "dispatch", '"hl.dsp.exit()"'],
        "style": "",
    },
    {"label": "Restart", "icon": "󰑙", "cmd": ["systemctl", "reboot"], "style": ""},
    {
        "label": "Shutdown",
        "icon": "󰐥",
        "cmd": ["systemctl", "poweroff"],
        "style": "shutdown",
    },
]


class PowerMenu(Window):
    def __init__(self, **kwargs):
        super().__init__(
            layer="overlay",
            anchor="",
            exclusivity="none",
            keyboard_mode="exclusive",
            visible=False,
            **kwargs,
        )
        self.add_style_class("powermenu-window")

        self._buttons: list[Button] = []
        self._selected: int = 0

        buttons_row = Box(
            orientation="horizontal",
            spacing=16,
            h_align="center",
            v_align="center",
            style_classes="powermenu-row",
        )

        for action in ACTIONS:
            btn = self._build_button(action)
            self._buttons.append(btn)
            buttons_row.add(btn)

        hint = Label(
            label="↑↓←→ navigate   ↵ confirm   esc cancel",
            style_classes="powermenu-hint",
            h_align="center",
        )

        self.children = Box(
            orientation="vertical",
            spacing=20,
            h_align="center",
            v_align="center",
            style_classes="powermenu-root",
            children=[buttons_row, hint],
        )

        self.connect("key-press-event", self._on_key_press)
        self.show_all()
        self._highlight(0)

    def _build_button(self, action: dict) -> Button:
        icon = Label(
            label=action["icon"],
            style_classes="powermenu-icon",
            h_align="center",
        )
        text = Label(
            label=action["label"],
            style_classes="powermenu-label",
            h_align="center",
        )
        card = Box(
            orientation="vertical",
            spacing=10,
            h_align="center",
            v_align="center",
            style_classes=f"powermenu-card {action['style']}".strip(),
            children=[icon, text],
        )
        btn = Button(child=card, style_classes="powermenu-btn")
        btn._action = action  # type: ignore[attr-defined]
        btn.connect("clicked", lambda _, a=action: self._execute(a))
        return btn

    def _highlight(self, index: int):
        for i, btn in enumerate(self._buttons):
            card = btn.get_child()
            if i == index:
                card.add_style_class("powermenu-selected")
            else:
                card.remove_style_class("powermenu-selected")
        self._selected = index

    def _on_key_press(self, _widget, event):
        keyval = event.keyval
        if keyval == 65307:  # Escape
            self._quit()
            return True
        if keyval in (65293, 65421):  # Return / KP_Enter
            self._execute(ACTIONS[self._selected])
            return True
        if keyval in (65361, 65362):  # Left / Up
            self._highlight((self._selected - 1) % len(self._buttons))
            return True
        if keyval in (65363, 65364):  # Right / Down
            self._highlight((self._selected + 1) % len(self._buttons))
            return True
        return False

    def _execute(self, action: dict):
        self._quit()
        subprocess.Popen(action["cmd"])

    def _quit(self):
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

    with open(os.path.join(CSS_DIR, "powermenu.css")) as f:
        pm_css = f.read()

    app.set_stylesheet_from_string(color_css + "\n" + pm_css, base_path=CSS_DIR)


if __name__ == "__main__":
    menu = PowerMenu()
    app = Application("powermenu", menu)
    menu._app_ref = app
    load_css(app)

    monitor_file(
        os.path.join(CSS_DIR, "colors-fabric.css"),
        lambda *_: load_css(app),
    )

    app.run()
