pragma Singleton

import QtQuick
import Quickshell

// Session actions, shared by the power menu and the launcher's > actions.
//
// Lock goes through `loginctl lock-session`, so whichever locker hypridle's
// lock_cmd names does the locking (and idle- and sleep-locking use the same
// one). fabric ran hyprlock directly because nothing listened then.
Singleton {
    readonly property var actions: [
        { id: "lock", label: "Lock", glyph: "󰍁", command: ["loginctl", "lock-session"] },
        { id: "suspend", label: "Suspend", glyph: "󰤄", command: ["systemctl", "suspend"] },
        { id: "logout", label: "Logout", glyph: "󰍃", command: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { id: "reboot", label: "Restart", glyph: "󰑙", command: ["systemctl", "reboot"] },
        { id: "poweroff", label: "Shutdown", glyph: "󰐥", command: ["systemctl", "poweroff"] }
    ]

    function run(id: string): void {
        const action = actions.find(a => a.id === id);
        if (action)
            Quickshell.execDetached(action.command);
    }
}
