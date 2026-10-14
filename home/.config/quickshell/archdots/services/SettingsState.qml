pragma Singleton

import QtQuick
import Quickshell

// Whether the settings window is open, and on which page.
// qs -c archdots ipc call settings open displays   ('' for the last page)
Singleton {
    readonly property var pages: [
        ["displays", "Displays", "\u{f0379}"],
        ["appearance", "Appearance", "\u{f03d8}"],
        ["bar", "Bar", "\u{f0aaf}"],
        ["idle", "Idle & power", "\u{f0425}"],
        ["apps", "Default apps", "\u{f003b}"],
        ["notifications", "Notifications", "\u{f009a}"],
        ["input", "Input", "\u{f030c}"],
        ["keybinds", "Keybinds", "\u{f0313}"],
        ["about", "About", "\u{f02fd}"]
    ]

    property bool open: false
    property string page: "displays"

    function show(name: string): void {
        if (pages.some(p => p[0] === name))
            page = name;
        open = true;
    }
}
