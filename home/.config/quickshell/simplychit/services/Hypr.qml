pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Hyprland state the shell needs beyond what Quickshell.Hyprland gives directly.
//
// Hyprland.activeToplevel stays null until the first focus change after the
// shell starts (none of the toplevels is marked activated either, checked on
// quickshell 0.3.2), so a fresh bar would show no title over a focused window.
// Until that first change, the active window is looked up from
// `hyprctl activewindow`, by address.
Singleton {
    id: root

    // Hyprland's address without the 0x, the form Quickshell uses.
    property string startupAddress: ""

    readonly property HyprlandToplevel activeWindow: Hyprland.activeToplevel
        ?? Hyprland.toplevels.values.find(t => t.address === startupAddress)
        ?? null
    readonly property string activeTitle: activeWindow ? activeWindow.title : ""

    Process {
        running: true
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.startupAddress = (JSON.parse(text).address ?? "").replace(/^0x/, "");
                } catch (e) {
                    // no active window: nothing to show
                }
            }
        }
    }

    // From the first real focus event on, Hyprland.activeToplevel is right,
    // including null for an empty workspace.
    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            root.startupAddress = "";
        }
    }
}
