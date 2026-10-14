pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Stay-awake: the systemd idle inhibitor that hypr/Scripts/idle-inhibit.sh
// holds (SUPER+SHIFT+I). hypridle respects it. The script keeps its pid in
// $XDG_RUNTIME_DIR/simplychit-idle-inhibit.pid, which is watched here so the bar
// and the control centre follow the keybind too.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/Scripts/idle-inhibit.sh"
    property bool inhibited: false

    function toggle(): void {
        Quickshell.execDetached([script, "toggle"]);
        refresh.restart();
    }

    function check(): void {
        status.running = true;
    }

    Process {
        id: status

        command: [root.script, "status"]
        onExited: code => root.inhibited = code === 0
    }

    // Catches the keybind's changes; the script writes or removes the file.
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/simplychit-idle-inhibit.pid"
        watchChanges: true
        printErrors: false
        onFileChanged: root.check()
        onLoaded: root.check()
        onLoadFailed: root.check()
    }

    Timer {
        id: refresh

        interval: 400
        onTriggered: root.check()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
}
