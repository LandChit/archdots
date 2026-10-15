pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config

// Toasts for things that happen to the machine (TODO C9): charger in or out,
// Caps/Num Lock, keyboard layout, audio output, VPN up or down, a new track,
// DND. Each kind can be switched off under "toasts" in settings.json.
Singleton {
    id: root

    // Nothing is reported until the initial states have settled.
    property bool armed: false
    property string capsFile: ""
    property string numFile: ""
    property int caps: -1
    property int num: -1

    function toast(enabled: bool, title: string, body: string, glyph: string): void {
        if (armed && enabled)
            Notifs.toast(title, body, glyph, false);
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: root.armed = true
    }

    // ── the shell itself ─────────────────────────────────────────────────
    // hypr/Scripts/shell-watchdog.sh started this shell again after a crash
    // and left a note with the exit status. Said once, even in DND.
    FileView {
        id: crashNote

        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/simplychit/shell-crashed"
        printErrors: false
        onLoaded: crashToast.start()
    }

    Timer {
        id: crashToast

        interval: 2500
        onTriggered: {
            Notifs.toast("The shell restarted", "It crashed (exit " + crashNote.text().trim() + ") and came back", "\u{f0026}", true);
            Quickshell.execDetached(["rm", "-f", crashNote.path]);
        }
    }

    // ── charger ──────────────────────────────────────────────────────────
    Connections {
        target: Battery

        function onChargingChanged(): void {
            if (Battery.available)
                root.toast(Config.toasts.charging, Battery.charging ? "Charging" : "On battery", Battery.percent + "%", Battery.charging ? "\u{f0084}" : "\u{f0079}");
        }
    }

    // ── Caps / Num Lock ──────────────────────────────────────────────────
    // There is no event for lock keys, but every keyboard's LED is a sysfs
    // file. One of each is found once and re-read a few times a second (a
    // tiny file read, no process started).
    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null | head -1; ls -d /sys/class/leds/*::numlock 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l !== "");
                root.capsFile = lines.find(l => l.endsWith("capslock")) ? lines.find(l => l.endsWith("capslock")) + "/brightness" : "";
                root.numFile = lines.find(l => l.endsWith("numlock")) ? lines.find(l => l.endsWith("numlock")) + "/brightness" : "";
            }
        }
    }
    FileView {
        id: capsLed

        path: root.capsFile
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: numLed

        path: root.numFile
        blockLoading: true
        printErrors: false
    }
    Timer {
        interval: 350
        repeat: true
        running: Config.toasts.locks && (root.capsFile !== "" || root.numFile !== "")
        onTriggered: {
            capsLed.reload();
            numLed.reload();
            const caps = parseInt(capsLed.text()), num = parseInt(numLed.text());
            if (!isNaN(caps) && root.caps !== -1 && caps !== root.caps)
                root.toast(true, caps > 0 ? "Caps Lock on" : "Caps Lock off", "", "\u{f0632}");
            if (!isNaN(num) && root.num !== -1 && num !== root.num)
                root.toast(true, num > 0 ? "Num Lock on" : "Num Lock off", "", "\u{f03a5}");
            root.caps = isNaN(caps) ? -1 : caps;
            root.num = isNaN(num) ? -1 : num;
        }
    }

    // ── keyboard layout ──────────────────────────────────────────────────
    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            // activelayout>>keyboard-name,Layout name
            if (event.name === "activelayout") {
                const layout = event.data.slice(event.data.indexOf(",") + 1);
                root.toast(Config.toasts.keyboardLayout, "Keyboard layout", layout, "\u{f030c}");
            }
        }
    }

    // ── audio output ─────────────────────────────────────────────────────
    Connections {
        target: Pipewire

        function onDefaultAudioSinkChanged(): void {
            const sink = Pipewire.defaultAudioSink;
            if (sink)
                root.toast(Config.toasts.audioDevice, "Audio output", sink.nickname || sink.description || sink.name, "\u{f04c3}");
        }
    }

    // ── VPN ──────────────────────────────────────────────────────────────
    // `ip monitor link` prints a line whenever an interface comes or goes;
    // tunnels have recognisable names.
    Process {
        running: true
        command: ["ip", "-o", "monitor", "link"]
        stdout: SplitParser {
            onRead: line => {
                const match = line.match(/^(Deleted )?\d+: ([^:@ ]+)/);
                if (!match || !/^(tun|tap|wg|tailscale|proton|nordlynx|mullvad|ppp|vpn)/.test(match[2]))
                    return;
                const gone = match[1] !== undefined;
                if (gone || / UP[ ,>]|state UP|LOWER_UP/.test(line))
                    root.toast(Config.toasts.vpn, gone ? "VPN disconnected" : "VPN connected", match[2], gone ? "\u{f099e}" : "\u{f0582}");
            }
        }
    }

    // ── now playing ──────────────────────────────────────────────────────
    Connections {
        target: Media

        function onTitleChanged(): void {
            if (Media.playing && Media.title !== "")
                root.toast(Config.toasts.nowPlaying, Media.title, Media.artist, "\u{f075a}");
        }
    }

    // ── stay awake ───────────────────────────────────────────────────────
    // SUPER+SHIFT+I or the control centre; also asked for, so always shown
    Connections {
        target: Idle

        function onInhibitedChanged(): void {
            if (root.armed)
                Notifs.toast(Idle.inhibited ? "Staying awake" : "Idle back on", Idle.inhibited ? "Idle lock and suspend are off" : "The screen locks and suspends when idle again", "\u{f0176}", true);
        }
    }

    // ── DND ──────────────────────────────────────────────────────────────
    // shown even when it has just been switched on: you asked for it
    Connections {
        target: Notifs

        function onDndChanged(): void {
            if (root.armed && Config.toasts.dnd)
                Notifs.toast(Notifs.dnd ? "Do not disturb" : "Alerts on", Notifs.dnd ? "Only critical notifications will show" : "", Notifs.dnd ? "\u{f009b}" : "\u{f009a}", true);
        }
    }
}
