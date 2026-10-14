pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Which panel is open. One at a time, like fabric's daemon: opening one closes
// the other. Feedback surfaces (OSD, notification popups, toasts) are not
// panels and are never closed by this.
//
// qs -c archdots ipc call panel toggle launcher
Singleton {
    id: root

    readonly property list<string> names: ["launcher", "powermenu", "clipboard", "emoji", "calendar", "battery", "notifications", "control", "wallpaper", "screenshot", "keybinds"]

    property string current: ""
    // The monitor a panel opens on: the focused one, caught at open time so a
    // panel does not jump screens while it is up.
    property string screenName: ""

    readonly property ShellScreen screen: Quickshell.screens.find(s => s.name === screenName) ?? Quickshell.screens[0] ?? null

    function open(name: string): bool {
        if (!names.includes(name)) {
            console.warn("no panel named " + name + " (choose: " + names.join(", ") + ")");
            return false;
        }
        screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        current = name;
        return true;
    }

    function close(name: string): void {
        if (name === "" || current === name)
            current = "";
    }

    function toggle(name: string): bool {
        if (current === name) {
            close(name);
            return true;
        }
        return open(name);
    }
}
