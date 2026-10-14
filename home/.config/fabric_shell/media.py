"""MPRIS media state and the transport controls the bar and control centre share.

playerctl does the DBus talking. `--follow` keeps one process open and prints a
line whenever the player, its playback status or its metadata changes, so
nothing here polls. With no player running it prints nothing and waits, which
is exactly what we want — the island simply stays hidden.
"""

from typing import NamedTuple

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label
from fabric.utils.helpers import (
    exec_shell_command,
    exec_shell_command_async,
    truncate,
)

# ASCII unit separator — metadata will never contain it, unlike the "|" or " - "
# that a track title can very reasonably include
SEP = "\x1f"
FORMAT = f"{{{{status}}}}{SEP}{{{{title}}}}{SEP}{{{{artist}}}}"

PLAY_ICON = "󰐊"
PAUSE_ICON = "󰏤"
PREV_ICON = "󰒮"
NEXT_ICON = "󰒭"


class MediaState(NamedTuple):
    status: str  # Playing | Paused | Stopped
    title: str
    artist: str

    @property
    def playing(self) -> bool:
        return self.status == "Playing"

    def summary(self, limit: int) -> str:
        text = " · ".join(part for part in (self.title, self.artist) if part)
        return truncate(text, limit) if text else "Nothing playing"


def parse(line: str) -> MediaState | None:
    """A `--follow` line into a state, or None when it says nothing useful."""
    parts = line.rstrip("\n").split(SEP)
    if len(parts) != 3:
        return None
    status, title, artist = (part.strip() for part in parts)
    if not status or status == "Stopped":
        return None
    return MediaState(status, title, artist)


def current() -> MediaState | None:
    """One-shot read, to fill the widgets before the first event arrives."""
    out = exec_shell_command(f"playerctl metadata --format {FORMAT}")
    return parse(out) if out is not False else None


def watch(callback) -> object:
    """Call `callback(MediaState | None)` whenever the player changes.

    Returns the subprocess — the caller has to keep a reference to it, or it is
    collected and the subscription dies with it.
    """

    def on_line(line: str) -> None:
        callback(parse(line))

    process, _stdout = exec_shell_command_async(
        f"playerctl --follow metadata --format {FORMAT}", on_line
    )
    return process


def command(action: str) -> None:
    """previous | play-pause | next."""
    exec_shell_command_async(f"playerctl {action}")


class MediaControls(Box):
    """Prev / play-pause / next with the current track.

    `hidden_when_idle` suits the bar, where an empty island would just be a
    gap; the control centre keeps its row in place and says "Nothing playing"
    instead, so the panel does not change height as tracks come and go.
    """

    def __init__(
        self,
        title_limit: int,
        style_classes: str = "media",
        hidden_when_idle: bool = True,
    ):
        super().__init__(
            orientation="horizontal", spacing=6, style_classes=style_classes
        )
        self._limit = title_limit
        self._hidden_when_idle = hidden_when_idle

        self._play = self._button(PLAY_ICON, "play-pause")
        self._title = Label(label="", style_classes="media-title", h_align="start")

        for child in (
            self._button(PREV_ICON, "previous"),
            self._play,
            self._button(NEXT_ICON, "next"),
            self._title,
        ):
            self.add(child)

        if hidden_when_idle:
            # stops a parent's show_all() from revealing an empty island
            self.set_no_show_all(True)
            self.hide()

    @staticmethod
    def _button(glyph: str, action: str) -> Button:
        button = Button(
            child=Label(label=glyph, style_classes="media-icon"),
            style_classes="media-btn",
        )
        button.connect("clicked", lambda *_: command(action))
        return button

    def set_state(self, state: MediaState | None) -> None:
        if state is None:
            self._title.set_label("Nothing playing")
            self._play.get_child().set_label(PLAY_ICON)
            if self._hidden_when_idle:
                self.hide()
            return

        self._title.set_label(state.summary(self._limit))
        self._play.get_child().set_label(PAUSE_ICON if state.playing else PLAY_ICON)
        if self._hidden_when_idle:
            self.set_no_show_all(False)
            self.show_all()
