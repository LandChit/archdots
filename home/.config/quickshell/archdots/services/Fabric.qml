pragma Singleton

import QtQuick
import Quickshell

// The fabric daemon's popups (calendar, battery, launcher, ...) until each one
// is ported. Same call as hypr/config/helpers/shell.lua makes. Remove this
// file once nothing uses it (TODO.md, phase 4).
Singleton {
    readonly property string root: Quickshell.env("HOME") + "/.config/fabric_shell"

    function send(action: string, window: string): void {
        Quickshell.execDetached([root + "/.venv/bin/python", root + "/ctl.py", action, window]);
    }
}
