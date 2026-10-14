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
import qs.modules.notifications
import qs.modules.osd
import qs.modules.polkit
import qs.modules.powermenu
import qs.modules.screenshot
import qs.modules.wallpaper
import qs.services

// archdots shell. Run with `qs -c archdots`; control it with
// `qs -c archdots ipc call <target> <function>`.
ShellRoot {
    id: root

    property bool barVisible: true

    Variants {
        model: Quickshell.screens

        delegate: Background {}
    }

    Variants {
        // no bar on screens listed in bar.excluded (TODO C7)
        model: Quickshell.screens.filter(s => !Config.bar.excluded.includes(s.name))

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
    Screenshot {}
    Picker {}
    ControlCentre {}
    Centre {}
    Popups {}
    PolkitDialog {}
    Lock {}

    // started for its side effects: the event toasts
    readonly property var events: Events
    BatteryCard {}

    Osd {
        id: osd
    }

    // qs -c archdots ipc call wallpaper set ~/Pictures/wallpapers/x.jpg
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

    // qs -c archdots ipc call notifications toast "Title" "Body"
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

    // One panel at a time, as with fabric's ctl.py:
    // qs -c archdots ipc call panel toggle launcher
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

    // qs -c archdots ipc call settings set bar.showCpu false
    // The value is read as JSON (false, 5, "text", [1, 2]); anything that does
    // not parse is kept as a plain string.
    IpcHandler {
        target: "settings"

        function set(key: string, value: string): string {
            let parsed = value;
            try {
                parsed = JSON.parse(value);
            } catch (e) {}
            return Config.set(key, parsed) ? "ok" : "settings.json is not valid JSON, left alone";
        }
    }

    IpcHandler {
        target: "shell"

        function reload(): void {
            Quickshell.reload(true);
        }
    }
}
