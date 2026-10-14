"""On-screen display — the card that appears when you press a media key.

Unlike the panels this window is never toggled from a menu: the keybind changes
the volume or the backlight and then asks the daemon to show the OSD, which
reads the new value back itself and fades away on its own a moment later.

    ctl.py show osd volume|mic|brightness
"""

from fabric.widgets.box import Box
from fabric.widgets.label import Label

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import SINK, SOURCE, Overlay, audio_state, backlight_state

from gi.repository import GLib, Gtk  # type: ignore

# long enough to read, short enough to stay out of the way while you hold a key
DISMISS_MS = 1600
ANIM_MS = 180

# (upper bound, glyph) — first match wins, last entry catches everything
VOLUME_ICONS = ((34, "󰕿"), (67, "󰖀"), (10_000, "󰕾"))
BRIGHTNESS_ICONS = ((34, "󰃞"), (67, "󰃟"), (10_000, "󰃠"))
MUTED_ICON = "󰝟"
MIC_ICON = "󰍬"
MIC_MUTED_ICON = "󰍭"


def _pick(icons, value: int) -> str:
    return next(icon for threshold, icon in icons if value < threshold)


# ── readers ────────────────────────────────────────────────────────────────────
# Each returns (glyph, text, percent, muted); None when the device is absent.


def _read_volume() -> tuple[str, str, int, bool] | None:
    state = audio_state(SINK)
    if state is None:
        return None
    percent, muted = state
    if muted:
        return MUTED_ICON, "Muted", percent, True
    return _pick(VOLUME_ICONS, percent), f"{percent}%", percent, False


def _read_mic() -> tuple[str, str, int, bool] | None:
    state = audio_state(SOURCE)
    if state is None:
        return None
    percent, muted = state
    if muted:
        return MIC_MUTED_ICON, "Mic off", percent, True
    return MIC_ICON, f"{percent}%", percent, False


def _read_brightness() -> tuple[str, str, int, bool] | None:
    percent = backlight_state()
    if percent is None:
        return None
    return _pick(BRIGHTNESS_ICONS, percent), f"{percent}%", percent, False


READERS = {
    "volume": _read_volume,
    "mic": _read_mic,
    "brightness": _read_brightness,
}


class OSD(Overlay):
    """Bottom-centred card showing the level a media key just changed."""

    # the daemon closes every other overlay when one opens; the OSD is
    # feedback rather than a mode, so it stays out of that exchange
    exclusive = False

    def __init__(self):
        super().__init__(
            title="fabric-osd",
            layer="overlay",
            anchor="bottom",
            margin="0px 0px 90px 0px",
        )
        self.add_style_class("osd-window")

        self._dismiss_src: int | None = None
        self._settle_src: int | None = None

        self._icon = Label(label="󰕾", style_classes="osd-icon", v_align="center")
        self._value = Label(label="0%", style_classes="osd-value", v_align="center")

        # a plain Gtk.ProgressBar — its trough/progress nodes are what osd.css
        # styles, and unlike a Scale it cannot be dragged by a stray click
        self._bar = Gtk.ProgressBar(valign=Gtk.Align.CENTER, hexpand=True)
        self._bar.get_style_context().add_class("osd-bar")

        self._card = Box(
            orientation="horizontal",
            spacing=14,
            style_classes="osd-card",
            children=[self._icon, self._bar, self._value],
        )

        self.children = Box(
            orientation="vertical",
            h_align="center",
            v_align="center",
            style_classes="osd-root",
            children=[self._card],
        )
        self.show_all()
        self.hide()

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self, kind: str = "volume") -> None:
        reader = READERS.get(kind)
        if reader is None:
            print(f"[osd] unknown kind: {kind!r}")
            return
        state = reader()
        if state is None:
            return  # no such device on this machine — say nothing

        self._fill(*state)
        self._cancel("_settle_src", "_dismiss_src")

        if not self.get_visible():
            # start faded out, then drop the class one frame later so GTK has a
            # state to transition *from* — otherwise the animation never plays
            self.add_style_class("anim-out")
            self.show()
            self._settle_src = GLib.timeout_add(16, self._settle)
        else:
            # already up and the key was pressed again — just restart the clock
            self.remove_style_class("anim-out")

        self._dismiss_src = GLib.timeout_add(DISMISS_MS, self._on_timeout)

    def dismiss(self) -> None:
        self._cancel("_settle_src", "_dismiss_src")
        self.add_style_class("anim-out")
        self._dismiss_src = GLib.timeout_add(ANIM_MS, self._finish_dismiss)

    # ── internals ───────────────────────────────────────────────────────────

    def _fill(self, glyph: str, text: str, percent: int, muted: bool) -> None:
        self._icon.set_label(glyph)
        self._value.set_label(text)
        # a boosted sink reads past 100% — the bar caps, the label does not
        self._bar.set_fraction(min(percent, 100) / 100)
        for name, active in (("muted", muted), ("over", percent > 100)):
            if active:
                self._card.add_style_class(name)
            else:
                self._card.remove_style_class(name)

    def _cancel(self, *names: str) -> None:
        for name in names:
            source = getattr(self, name)
            if source is not None:
                GLib.source_remove(source)
                setattr(self, name, None)

    def _settle(self) -> bool:
        self._settle_src = None
        self.remove_style_class("anim-out")
        return False

    def _on_timeout(self) -> bool:
        self._dismiss_src = None
        self.dismiss()
        return False

    def _finish_dismiss(self) -> bool:
        self._dismiss_src = None
        self.hide()
        return False
