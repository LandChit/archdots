pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Stay-awake: the systemd idle inhibitor that hypr/Scripts/idle-inhibit.sh
// holds (SUPER+SHIFT+I). hypridle respects it. The script keeps its pid in
// $XDG_RUNTIME_DIR/simplychit-idle-inhibit.pid, which is watched here so the bar
// and the control centre follow the keybind too.
//
// Apps that ask to stay awake (a browser playing video), over D-Bus or with a
// logind idle inhibitor, are listed by `simplychit inhibitors` in
// $XDG_RUNTIME_DIR/simplychit-inhibitors.json: [{app, reason, via}]. No file
// is no requests.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/Scripts/idle-inhibit.sh"
    property bool inhibited: false
    property var apps: []
    readonly property bool appInhibited: apps.length > 0
    // "Zen", or "Zen +1" when several ask
    readonly property string appSummary: appInhibited ? apps[0].app + (apps.length > 1 ? " +" + (apps.length - 1) : "") : ""

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

    FileView {
        id: requests

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/simplychit-inhibitors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let list = [];
            try {
                list = JSON.parse(text());
            } catch (e) {}
            root.apps = Array.isArray(list) ? list.filter(a => a && typeof a.app === "string") : [];
        }
        onLoadFailed: root.apps = []
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
