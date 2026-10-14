//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.bar
import qs.modules.launcher
import qs.modules.powermenu
import qs.services

// archdots shell. Run with `qs -c archdots`; control it with
// `qs -c archdots ipc call <target> <function>`.
ShellRoot {
    id: root

    property bool barVisible: true

    Variants {
        model: Quickshell.screens

        delegate: Bar {
            required property ShellScreen modelData

            screen: modelData
            visible: root.barVisible
        }
    }

    Launcher {}
    PowerMenu {}

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
