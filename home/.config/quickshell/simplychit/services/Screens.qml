pragma Singleton

import QtQuick
import Quickshell
import qs.config

// The primary screen (displays.primary in settings.json): where the login
// screen shows, and toasts before any screen has had focus. It is saved by
// Hyprland's description ("BOE 0x0BCA ..."), which survives a change of
// port; a port name ("eDP-1") written by hand works too. Nothing chosen,
// or the chosen one not connected: the built-in panel, else the first
// screen.
Singleton {
    id: root

    readonly property var primary: find(Config.displays.primary) ?? Quickshell.screens.find(s => s.name.startsWith("eDP")) ?? Quickshell.screens[0] ?? null

    // A ShellScreen has a model and a serial, not Hyprland's description,
    // which is "make model serial": a screen matches when both are in it.
    function matches(screen: var, key: string): bool {
        if (!screen || key === "")
            return false;
        if (screen.name === key)
            return true;
        return screen.model !== "" && key.includes(screen.model) && (screen.serialNumber === "" || key.includes(screen.serialNumber));
    }

    function find(key: string): var {
        return Quickshell.screens.find(s => matches(s, key)) ?? null;
    }
}
