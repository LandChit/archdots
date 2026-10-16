//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.bar
import qs.modules.battery
import qs.modules.calendar
import qs.modules.clipboard
import qs.modules.control
import qs.modules.emoji
import qs.modules.keybinds
import qs.modules.launcher
import qs.modules.lock
import qs.modules.notepad
import qs.modules.notifications
import qs.modules.osd
import qs.modules.polkit
import qs.modules.powermenu
import qs.modules.qr
import qs.modules.screenshot
import qs.modules.settings
import qs.modules.wallpaper
import qs.modules.welcome
import qs.services

// simplychit shell. Run with `qs -c simplychit`; control it with
// `qs -c simplychit ipc call <target> <function>`.
ShellRoot {
    id: root

    property bool barVisible: true

    Variants {
        model: Quickshell.screens

        delegate: Background {}
    }

    Variants {
        // no bar on screens listed in bar.excluded (by description or port)
        model: Quickshell.screens.filter(s => !BarLayout.isExcluded(s))

        delegate: Bar {
            visible: root.barVisible
        }
    }

    Launcher {}
    PowerMenu {}
    Calendar {}
    Clipboard {}
    Emoji {}
    Keybinds {}
    Notepad {
        id: notepad
    }
    Qr {}
    Screenshot {}
    Picker {}
    ControlCentre {}
    Centre {}
    Popups {}
    Toasts {}
    PolkitDialog {}

    // after a display change, and Identify; also run by the Displays service
    // on hotplug, so it lives here rather than in the settings window
    DisplayOverlays {}

    // built the first time it opens
    LazyLoader {
        active: SettingsState.open

        SettingsWindow {}
    }

    // the first-run welcome; also `ipc call welcome open`
    LazyLoader {
        active: FirstRun.open

        WelcomeWindow {}
    }
    Lock {}

    // started for their side effects: event toasts, idle timeouts, sounds
    readonly property var events: Events
    readonly property var idleTimers: IdleTimers
    readonly property var settingsCheck: SettingsCheck
    readonly property var sounds: Sounds
    BatteryCard {}

    Osd {
        id: osd
    }

    // qs -c simplychit ipc call wallpaper set ~/Pictures/wallpapers/x.jpg
    IpcHandler {
        target: "wallpaper"

        function set(path: string): void {
            Theme.apply(path);
        }
        function next(): void {
            Theme.next(false);
        }
        function random(): void {
            Theme.next(true);
        }
        function mode(mode: string): void {
            Theme.setMode(mode);
        }
    }

    // qs -c simplychit ipc call notifications toast "Title" "Body"
    IpcHandler {
        target: "notifications"

        function toast(title: string, body: string): void {
            Notifs.toast(title, body, "\u{f009a}", true);
        }
        function dnd(on: bool): void {
            Notifs.dnd = on;
        }
        function clear(): void {
            Notifs.clearHistory();
        }
    }

    // qs -c simplychit ipc call recording toggle   (stop, or record a region)
    IpcHandler {
        target: "recording"

        function region(): void {
            Recorder.region();
        }
        function screen(): void {
            Recorder.screen();
        }
        function stop(): void {
            Recorder.stop();
        }
        function toggle(): void {
            Recorder.toggle();
        }
        // "recording 1:05" or "idle", for scripts
        function status(): string {
            return Recorder.recording ? "recording " + Recorder.elapsed : "idle";
        }
    }

    // qs -c simplychit ipc call qr open   (the clipboard as a QR code)
    IpcHandler {
        target: "qr"

        function open(): void {
            Panels.open("qr");
        }
        // read a code off a region of the screen and copy it
        function scan(): void {
            QrScan.scan();
        }
    }

    // qs -c simplychit ipc call notepad append "call the plumber"
    IpcHandler {
        target: "notepad"

        function append(line: string): void {
            notepad.append(line);
        }
    }

    // qs -c simplychit ipc call displays keep|revert   (e.g. from a TTY keybind)
    IpcHandler {
        target: "displays"

        function keep(): void {
            Displays.keep();
        }
        function revert(): void {
            Displays.revert();
        }
        function refresh(): void {
            Displays.refresh();
        }
    }

    IpcHandler {
        target: "osd"

        function volume(): void {
            osd.show("volume");
        }
        function mic(): void {
            osd.show("mic");
        }
        function brightness(): void {
            osd.show("brightness");
        }
    }

    IpcHandler {
        target: "brightness"

        function up(): void {
            Brightness.step(5);
        }
        function down(): void {
            Brightness.step(-5);
        }
        function set(percent: int): void {
            Brightness.set(percent);
        }
    }

    // One panel at a time:
    // qs -c simplychit ipc call panel toggle launcher
    IpcHandler {
        target: "panel"

        function toggle(name: string): string {
            return Panels.toggle(name) ? "ok" : "no panel named " + name;
        }
        function open(name: string): string {
            return Panels.open(name) ? "ok" : "no panel named " + name;
        }
        function close(): void {
            Panels.close("");
        }
    }

    // Not show/hide: `qs ipc call bar show` parses "show" as the ipc
    // subcommand of that name and lists the target instead of calling it.
    IpcHandler {
        target: "bar"

        function toggle(): void {
            root.barVisible = !root.barVisible;
        }
        function open(): void {
            root.barVisible = true;
        }
        function close(): void {
            root.barVisible = false;
        }
    }

    // qs -c simplychit ipc call settings set bar.showCpu false
    // The value is read as JSON (false, 5, "text", [1, 2]); anything that does
    // not parse is kept as a plain string.
    IpcHandler {
        target: "settings"

        // a page name from services/SettingsState.qml, or '' for the last one
        function open(page: string): void {
            SettingsState.show(page);
        }
        function close(): void {
            SettingsState.open = false;
        }

        function set(key: string, value: string): string {
            let parsed = value;
            try {
                parsed = JSON.parse(value);
            } catch (e) {}
            return Config.set(key, parsed) ? "ok" : "settings.json is not valid JSON, left alone";
        }
    }

    // qs -c simplychit ipc call welcome open   (shown by itself on a first run)
    IpcHandler {
        target: "welcome"

        function open(): void {
            FirstRun.show();
        }
    }

    IpcHandler {
        target: "shell"

        function reload(): void {
            Quickshell.reload(true);
        }
    }
}
