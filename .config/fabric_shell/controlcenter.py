"""Control centre — the switches that would otherwise send you to a terminal.

Sliders for volume and brightness, toggles for Wi-Fi, Bluetooth and
do-not-disturb, the nearby networks and the paired Bluetooth devices.

Pairing itself is left to `bluetoothctl` — it needs a passkey exchange this
panel has nowhere to show. Once a device is paired, connecting is one click.
"""

from fabric.widgets.box import Box
from fabric.widgets.button import Button
from fabric.widgets.label import Label
from fabric.widgets.scale import Scale
from fabric.utils.helpers import exec_shell_command, exec_shell_command_async

# importing common pulls in fabric's wayland widget, which pins the
# GtkLayerShell version — so it has to come before the gi import below
from common import (
    SINK,
    Overlay,
    audio_state,
    backlight_state,
    make_scroller,
    watch_audio,
)

import media
from tray import SafeSystemTray

from gi.repository import GLib  # type: ignore

WIDTH = 400
# one height for all three tabs — the panel must not resize as you switch
PAGE_HEIGHT = 180
MEDIA_TITLE_CHARS = 34
ANIM_MS = 180

# tab id, label — the id is what _show_page() switches on
PAGES = (("networks", "Networks"), ("devices", "Bluetooth"), ("tray", "Tray"))

# lines up with the calendar and the notification centre, under the bar
MARGIN = "52px 14px 0px 0px"

# how long a network list stays fresh before a reopen rescans
SCAN_MAX_AGE_SECONDS = 20

# brightnessctl offers no change signal, so the slider polls while the panel is
# open. The read is a 3ms sysfs lookup and stops the moment the panel closes.
BRIGHTNESS_POLL_MS = 700

# how long after a manual change the poll leaves the slider alone
BRIGHTNESS_SETTLE_SECONDS = 1.5

SIGNAL_ICONS = ((25, "󰤟"), (50, "󰤢"), (75, "󰤥"), (10_000, "󰤨"))


def _signal_icon(strength: int) -> str:
    return next(icon for threshold, icon in SIGNAL_ICONS if strength < threshold)


# ── system state ───────────────────────────────────────────────────────────────


def wifi_enabled() -> bool:
    return (exec_shell_command("nmcli radio wifi") or "").strip() == "enabled"


# bluetoothctl does not fail when bluetoothd is unreachable — it sits there
# printing "Waiting to connect to bluetoothd..." indefinitely. These readers run
# on the GTK main loop, so one such call takes the whole panel with it: the
# control centre opens and freezes. A machine with no adapter never starts the
# service, which is why this only ever appeared in a VM.
#
# rfkill answers "is there a radio at all" straight from the kernel with no
# daemon involved, so it gates every call below. The timeout covers the other
# half — hardware present but bluetoothd wedged — where rfkill says yes and
# bluetoothctl still never returns.
BLUETOOTHCTL_TIMEOUT = 2


def bluetooth_present() -> bool:
    """Whether this machine has a Bluetooth radio at all, blocked or not."""
    out = exec_shell_command("rfkill list bluetooth")
    return out is not False and bool(out.strip())


def _bluetoothctl(command: str) -> str | bool:
    """Run a bluetoothctl query, or return False if it cannot safely be asked."""
    if not bluetooth_present():
        return False
    return exec_shell_command(f"timeout {BLUETOOTHCTL_TIMEOUT} bluetoothctl {command}")


def bluetooth_powered() -> bool | None:
    """True when the adapter is powered, None when there is no adapter.

    A soft-blocked radio makes `bluetoothctl show` report no controller, which
    is indistinguishable from having no hardware — so rfkill is asked as well.
    Blocked counts as "off, but switchable", not "absent".
    """
    out = _bluetoothctl("show")
    if out is False or "Controller" not in out:
        return False if bluetooth_present() else None
    return "Powered: yes" in out


def bluetooth_devices() -> list[tuple[str, str, bool]]:
    """(mac, name, connected) for each paired device, connected ones first."""
    paired = _bluetoothctl("devices Paired")
    if paired is False:
        return []
    connected = _bluetoothctl("devices Connected") or ""

    # both list `Device AC:80:FB:DA:46:49 Galaxy Buds2 (4649)`
    def macs(text: str) -> set[str]:
        return {
            line.split()[1]
            for line in text.splitlines()
            if line.startswith("Device ") and len(line.split()) >= 2
        }

    live = macs(connected)
    devices = []
    for line in paired.splitlines():
        parts = line.split(maxsplit=2)
        if len(parts) == 3 and parts[0] == "Device":
            devices.append((parts[1], parts[2], parts[1] in live))
    return sorted(devices, key=lambda d: (not d[2], d[1].casefold()))


def wifi_networks() -> list[tuple[bool, str, int, bool]]:
    """(active, ssid, signal, secured) for each network, strongest first.

    **`--rescan no` is load-bearing.** Without it nmcli triggers a scan and
    blocks until it finishes — 4.9 seconds here, on the GTK main loop, which is
    what made the panel seem slow to open. The cached list is the same twelve
    networks in 25ms; a fresh scan runs separately and redraws when it lands.
    """
    out = exec_shell_command(
        "nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list --rescan no"
    )
    if out is False:
        return []

    seen: dict[str, tuple[bool, str, int, bool]] = {}
    for line in out.splitlines():
        # -t escapes literal colons in an SSID as \:, so hide them before split
        parts = line.replace("\\:", "\0").split(":")
        if len(parts) < 4:
            continue
        active, ssid, signal, security = (p.replace("\0", ":") for p in parts[:4])
        if not ssid or not signal.isdigit():
            continue  # a hidden network has no name to show or click
        entry = (active == "yes", ssid, int(signal), bool(security.strip()))
        # the same SSID appears once per band; keep the strongest
        if ssid not in seen or entry[2] > seen[ssid][2]:
            seen[ssid] = entry

    return sorted(seen.values(), key=lambda e: (not e[0], -e[2]))


class ControlCenter(Overlay):
    """Panel of system toggles, sliders and nearby networks."""

    def __init__(self, store):
        super().__init__(
            title="fabric-control",
            layer="top",
            anchor="top right",
            margin=MARGIN,
            keyboard_mode="on-demand",
        )
        self.add_style_class("control-window")

        self._store = store  # NotificationStore, for the DND toggle
        self._anim_src: int | None = None
        self._scanned_at = 0.0
        self._syncing = False  # guards the slider callbacks while we set them
        self._pending_ssid = ""  # the network the last connect attempt targeted
        self._brightness_src: int | None = None  # poll, alive only while open
        self._brightness_touched = 0.0  # when the slider was last dragged

        self._volume = self._slider(self._on_volume_changed)
        self._volume_value = Label(label="--%", style_classes="control-value")
        self._brightness = self._slider(self._on_brightness_changed)
        self._brightness_value = Label(label="--%", style_classes="control-value")

        self._wifi = self._toggle("󰖩", "Wi-Fi", self._on_wifi_clicked)
        self._bluetooth = self._toggle("󰂯", "Bluetooth", self._on_bluetooth_clicked)
        self._dnd = self._toggle("󰂚", "Alerts", self._on_dnd_clicked)

        self._networks = Box(
            orientation="vertical",
            spacing=4,
            style_classes="control-networks",
            h_expand=True,
            v_align="start",
        )
        # unlike the bar island this row stays put when nothing is playing, so
        # the panel does not change height as tracks come and go
        self._player = media.MediaControls(
            MEDIA_TITLE_CHARS, "control-player", hidden_when_idle=False
        )

        # the tray moved here from the bar, where it was an invisible island
        # eating width. SafeSystemTray is what actually makes it appear at all:
        # see tray.py — one unresolvable icon used to empty the whole thing.
        self._tray = SafeSystemTray(icon_size=18, style_classes="control-tray")

        self._devices = Box(
            orientation="vertical",
            spacing=4,
            style_classes="control-networks",
            h_expand=True,
            v_align="start",
        )
        self._status = Label(label="", style_classes="control-status", h_align="start")

        # networks / bluetooth / tray share one scroll area, one page at a time
        self._page = PAGES[0][0]
        self._tabs: dict[str, Button] = {}
        self._tab_bar = Box(
            orientation="horizontal",
            spacing=6,
            h_expand=True,
            style_classes="control-tabs",
            children=[self._tab(key, label) for key, label in PAGES],
        )
        self._pages = Box(
            orientation="vertical",
            h_expand=True,
            v_align="start",
            children=[self._networks, self._devices, self._tray],
        )

        card = Box(
            orientation="vertical",
            spacing=12,
            style_classes="control-card",
            children=[
                Label(
                    label="Control centre",
                    style_classes="control-title",
                    h_align="start",
                ),
                Box(
                    orientation="horizontal",
                    spacing=8,
                    h_expand=True,
                    children=[self._wifi, self._bluetooth, self._dnd],
                ),
                self._slider_row("󰕾", self._volume, self._volume_value),
                self._slider_row("󰃠", self._brightness, self._brightness_value),
                self._player,
                self._tab_bar,
                # one scroller shared by all three pages: stacking them made the
                # panel 685px tall on a 1080p screen, and it only grows as more
                # networks or devices appear
                make_scroller(self._pages, WIDTH - 64, PAGE_HEIGHT),
                self._status,
            ],
        )
        self.children = Box(
            orientation="vertical", style_classes="control-root", children=[card]
        )

        # the panel is only one of several things that change the volume, so it
        # follows the same subscription the bar does
        self._audio_watch = watch_audio(self._sync_audio)
        self._media_watch = media.watch(self._player.set_state)
        store.subscribe(self._sync_dnd)

        self.show_all()
        self._status.hide()
        self._show_page(self._page)  # after show_all, or it reveals every page
        self.hide()

    # ── construction helpers ────────────────────────────────────────────────

    @staticmethod
    def _slider(on_change) -> Scale:
        scale = Scale(
            min_value=0,
            max_value=100,
            value=0,
            draw_value=False,
            h_expand=True,
            style_classes="control-slider",
        )
        scale.connect("value-changed", on_change)
        return scale

    @staticmethod
    def _slider_row(glyph: str, scale: Scale, value: Label) -> Box:
        return Box(
            orientation="horizontal",
            spacing=10,
            h_expand=True,
            style_classes="control-slider-row",
            children=[
                Label(label=glyph, style_classes="control-slider-icon"),
                scale,
                value,
            ],
        )

    def _tab(self, key: str, label: str) -> Button:
        button = Button(
            child=Label(label=label, style_classes="control-tab-label"),
            style_classes="control-tab",
            h_expand=True,
        )
        button.connect("clicked", lambda *_, k=key: self._show_page(k))
        self._tabs[key] = button
        return button

    def _reveal_rows(self, key: str, box: Box) -> None:
        """show_all() the rows just built, without un-hiding an inactive page."""
        box.show_all()
        box.set_visible(self._page == key)

    def _show_page(self, key: str) -> None:
        """Reveal one page and hide the rest, refreshing what is now visible.

        The pages are shown and hidden rather than swapped in and out of the
        scroller: a SystemTray cannot be reparented without losing its items.
        """
        self._page = key
        for name, button in self._tabs.items():
            self._set_active(button, name == key)

        for name, widget in (
            ("networks", self._networks),
            ("devices", self._devices),
            ("tray", self._tray),
        ):
            widget.set_visible(name == key)
            # without this a later show_all() elsewhere would reveal all three
            widget.set_no_show_all(name != key)

        if key == "networks":
            self._refresh_networks()
        elif key == "devices":
            self._refresh_devices()

    @staticmethod
    def _toggle(glyph: str, label: str, on_click) -> Button:
        button = Button(
            child=Box(
                orientation="vertical",
                spacing=2,
                h_align="center",
                children=[
                    Label(label=glyph, style_classes="control-toggle-icon"),
                    Label(label=label, style_classes="control-toggle-label"),
                ],
            ),
            style_classes="control-toggle",
            h_expand=True,
        )
        button.connect("clicked", on_click)
        return button

    # ── syncing from the system ─────────────────────────────────────────────

    def _sync_audio(self, *_) -> None:
        state = audio_state(SINK)
        if state is None:
            return
        percent, muted = state
        self._syncing = True
        self._volume.set_value(min(percent, 100))
        self._syncing = False
        self._volume_value.set_label("Muted" if muted else f"{percent}%")

    def _sync_brightness(self) -> None:
        percent = backlight_state()
        if percent is None:
            return
        self._syncing = True
        self._brightness.set_value(percent)
        self._syncing = False
        self._brightness_value.set_label(f"{percent}%")

    def _sync_toggles(self) -> None:
        self._set_active(self._wifi, wifi_enabled())

        powered = bluetooth_powered()
        self._set_active(self._bluetooth, powered is True)
        self._bluetooth.set_sensitive(powered is not None)

        self._sync_dnd()

    def _sync_dnd(self) -> None:
        # the button reads "Alerts", so DND being on means the toggle is off
        self._set_active(self._dnd, not self._store.dnd)

    @staticmethod
    def _set_active(button: Button, active: bool) -> None:
        if active:
            button.add_style_class("active")
        else:
            button.remove_style_class("active")

    # ── networks ────────────────────────────────────────────────────────────

    def _refresh_networks(self) -> None:
        for child in self._networks.get_children():
            self._networks.remove(child)

        if not wifi_enabled():
            self._networks.add(Label(label="Wi-Fi is off", style_classes="control-empty"))
            self._reveal_rows("networks", self._networks)
            return

        networks = wifi_networks()
        if not networks:
            self._networks.add(
                Label(label="No networks in range", style_classes="control-empty")
            )
        for active, ssid, signal, secured in networks:
            self._networks.add(self._network_row(active, ssid, signal, secured))
        self._networks.show_all()

    def _network_row(
        self, active: bool, ssid: str, signal: int, secured: bool
    ) -> Button:
        row = Box(
            orientation="horizontal",
            spacing=9,
            h_expand=True,
            style_classes="control-network" + (" connected" if active else ""),
            children=[
                Label(label=_signal_icon(signal), style_classes="control-network-icon"),
                # not ellipsized: inside a scroller GTK hands an ellipsizing
                # label its minimum width and clips it (see notifications.py)
                Label(
                    label=ssid,
                    style_classes="control-network-name",
                    h_align="start",
                    x_align=0.0,
                ),
                Box(h_expand=True),
                Label(
                    label="󰌾" if secured else "", style_classes="control-network-lock"
                ),
                Label(label=f"{signal}%", style_classes="control-network-signal"),
            ],
        )
        button = Button(child=row, style_classes="control-network-btn")
        button.connect("clicked", lambda *_, s=ssid, a=active: self._connect(s, a))
        return button

    # ── bluetooth devices ───────────────────────────────────────────────────

    def _refresh_devices(self) -> None:
        for child in self._devices.get_children():
            self._devices.remove(child)

        if bluetooth_powered() is not True:
            self._devices.add(
                Label(label="Bluetooth is off", style_classes="control-empty")
            )
            self._reveal_rows("devices", self._devices)
            return

        devices = bluetooth_devices()
        if not devices:
            self._devices.add(
                Label(
                    # pairing needs a passkey prompt this panel has nowhere to
                    # show, so it stays a `bluetoothctl` job; connecting does not
                    label="Nothing paired yet — run: bluetoothctl",
                    style_classes="control-empty",
                )
            )
        for mac, name, connected in devices:
            self._devices.add(self._device_row(mac, name, connected))
        self._devices.show_all()

    def _device_row(self, mac: str, name: str, connected: bool) -> Button:
        row = Box(
            orientation="horizontal",
            spacing=9,
            h_expand=True,
            style_classes="control-network" + (" connected" if connected else ""),
            children=[
                Label(
                    label="󰂱" if connected else "󰂯",
                    style_classes="control-network-icon",
                ),
                Label(
                    label=name,
                    style_classes="control-network-name",
                    h_align="start",
                    x_align=0.0,
                ),
                Box(h_expand=True),
                Label(
                    label="Connected" if connected else "",
                    style_classes="control-network-signal",
                ),
            ],
        )
        button = Button(child=row, style_classes="control-network-btn")
        button.connect(
            "clicked",
            lambda *_, m=mac, n=name, c=connected: self._on_device_clicked(m, n, c),
        )
        return button

    def _connect(self, ssid: str, already_active: bool) -> None:
        if already_active:
            return
        self._pending_ssid = ssid
        self._show_status(f"Connecting to {ssid}…")
        # a saved network connects straight away; an unsaved one needs a
        # password, which nmcli reports rather than prompting for here
        exec_shell_command_async(
            f'nmcli device wifi connect "{ssid}"', self._on_connect_output
        )

    def _on_connect_output(self, line: str) -> None:
        text = line.strip()
        if not text:
            return
        failed = text.lower().startswith("error")
        if failed and ("secrets" in text or "password" in text.lower()):
            self._show_status(f"{self._pending_ssid} needs a password — join it once from nmcli")
        else:
            self._show_status(text[:70])
            if not failed:
                self._refresh_networks()

    def _show_status(self, text: str) -> None:
        self._status.set_label(text)
        self._status.show()

    # ── actions ─────────────────────────────────────────────────────────────

    def _on_volume_changed(self, scale: Scale) -> None:
        if self._syncing:
            return
        percent = int(scale.get_value())
        self._volume_value.set_label(f"{percent}%")
        exec_shell_command_async(f"wpctl set-volume {SINK} {percent}%")

    def _on_brightness_changed(self, scale: Scale) -> None:
        if self._syncing:
            return
        self._brightness_touched = GLib.get_monotonic_time() / 1_000_000
        percent = max(1, int(scale.get_value()))  # never black the screen out
        self._brightness_value.set_label(f"{percent}%")
        # No -e4 here, unlike the keybinds. `brightnessctl -m` reports a linear
        # percentage, so writing on the exponential curve does not round-trip:
        # asking for 45% read back as 4% and the handle jumped on the next poll.
        # The keys keep -e4 because relative steps want a perceptual curve.
        exec_shell_command_async(f"brightnessctl -n2 set {percent}%")

    def _on_wifi_clicked(self, *_) -> None:
        state = "off" if wifi_enabled() else "on"
        exec_shell_command_async(f"nmcli radio wifi {state}")
        self._show_status(f"Wi-Fi {state}")
        # nmcli returns before the radio settles, so re-read after a moment
        GLib.timeout_add(700, self._after_radio_change)

    def _on_bluetooth_clicked(self, *_) -> None:
        powered = bluetooth_powered()
        if powered is None:
            self._show_status("No Bluetooth adapter found")
            return
        if powered:
            # rfkill as well as power off, so "off" survives a reboot.
            # `bluetoothctl power off` only clears the adapter's runtime
            # Powered property, and bluez re-enables every controller it finds
            # at startup (main.conf: "AutoEnable ... Defaults to 'true'"), so on
            # its own this toggle would quietly undo itself on the next boot.
            # systemd-rfkill saves the rfkill state at shutdown and restores it.
            # timeout on the bluetoothctl half only: if it hangs waiting for
            # bluetoothd, the rfkill still has to run or the toggle does nothing.
            exec_shell_command_async(
                f"sh -c 'timeout {BLUETOOTHCTL_TIMEOUT} bluetoothctl power off;"
                " rfkill block bluetooth'"
            )
            self._show_status("Bluetooth off")
        else:
            # `power on` fails silently while the radio is soft-blocked, so
            # the unblock has to happen first, in the same shell
            exec_shell_command_async(
                "sh -c 'rfkill unblock bluetooth;"
                f" timeout {BLUETOOTHCTL_TIMEOUT} bluetoothctl power on'"
            )
            self._show_status("Bluetooth on")
        GLib.timeout_add(900, self._after_radio_change)

    def _on_device_clicked(self, mac: str, name: str, connected: bool) -> None:
        action = "disconnect" if connected else "connect"
        self._show_status(f"{'Disconnecting from' if connected else 'Connecting to'} {name}…")
        # connect/disconnect can hang the same way a query does; the callback
        # then never fires and the row sits on "Connecting..." forever.
        exec_shell_command_async(
            f"timeout {BLUETOOTHCTL_TIMEOUT} bluetoothctl {action} {mac}",
            self._on_device_output,
        )

    def _on_device_output(self, line: str) -> None:
        text = line.strip()
        # bluetoothctl narrates at length; only the verdict is worth showing
        if any(word in text for word in ("successful", "Failed", "not available")):
            self._show_status(text[:70])
            self._refresh_devices()

    def _after_radio_change(self) -> bool:
        self._sync_toggles()
        self._show_page(self._page)  # rebuilds whichever page is on screen
        return False

    def _on_dnd_clicked(self, *_) -> None:
        self._store.set_dnd(not self._store.dnd)
        self._show_status(
            "Notifications silenced — still recorded" if self._store.dnd else "Alerts on"
        )

    # ── show / hide ─────────────────────────────────────────────────────────

    def reveal(self) -> None:
        # The window goes up first and fills itself a frame later. Every reader
        # here is a subprocess, and doing them before show() meant the panel
        # only appeared once they had all returned.
        self._cancel_anim()
        self._status.hide()
        self.add_style_class("anim-out")
        self.show()
        self._anim_src = GLib.timeout_add(16, self._settle)
        GLib.idle_add(self._populate)

    def _populate(self) -> bool:
        self._sync_audio()
        self._sync_brightness()
        self._sync_toggles()
        self._player.set_state(media.current())
        # only the visible page is worth rebuilding; the others refresh when
        # their tab is picked
        self._show_page(self._page)

        # brightnessctl has nothing to subscribe to, so the slider is polled —
        # but only while the panel is on screen, and it is a 3ms sysfs read
        if self._brightness_src is None:
            self._brightness_src = GLib.timeout_add(
                BRIGHTNESS_POLL_MS, self._poll_brightness
            )

        self._start_rescan()
        return False

    def _start_rescan(self) -> None:
        """Kick off a real scan and redraw the list when it finishes."""
        now = GLib.get_monotonic_time() / 1_000_000
        if now - self._scanned_at < SCAN_MAX_AGE_SECONDS:
            return  # a quick reopen reuses the list we already have
        self._scanned_at = now

        process, _ = exec_shell_command_async("nmcli device wifi rescan")
        if process is None:
            return
        # waiting on the process is what tells us the cache is worth re-reading
        process.wait_async(None, self._on_rescan_done)

    def _on_rescan_done(self, process, result) -> None:
        try:
            process.wait_finish(result)
        except Exception:
            return  # a failed scan just leaves the cached list in place
        if self.get_visible() and self._page == "networks":
            self._refresh_networks()

    def _poll_brightness(self) -> bool:
        if not self.get_visible():
            self._brightness_src = None
            return False  # stop; _populate starts a fresh one on reopen
        # don't fight a drag in progress: the readback lags the handle, so
        # writing it back mid-gesture makes the slider stutter
        since = GLib.get_monotonic_time() / 1_000_000 - self._brightness_touched
        if since > BRIGHTNESS_SETTLE_SECONDS:
            self._sync_brightness()
        return True

    def dismiss(self) -> None:
        self._cancel_anim()
        self._stop_brightness_watch()
        self.add_style_class("anim-out")
        self._anim_src = GLib.timeout_add(ANIM_MS, self._finish_dismiss)

    def _stop_brightness_watch(self) -> None:
        if self._brightness_src is not None:
            GLib.source_remove(self._brightness_src)
            self._brightness_src = None

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
