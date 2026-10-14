pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Checks settings.json against its schema (`simplychit check-settings`) at
// start and after every change, and says so in a toast when something is
// wrong: an unknown key is ignored and a bad value falls back to the default,
// both silently otherwise. Toasts once per new set of problems.
Singleton {
    id: root

    property var problems: []
    property string shown: ""

    function check(): void {
        if (!proc.running)
            proc.running = true;
    }

    FileView {
        path: Config.path
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
        onLoaded: debounce.restart()
        onLoadFailed: debounce.restart()
    }

    Timer {
        id: debounce

        interval: 800
        onTriggered: root.check()
    }

    Process {
        id: proc

        command: [Quickshell.env("HOME") + "/.local/bin/simplychit", "check-settings", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let result;
                try {
                    result = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.problems = result.problems ?? [];
                const key = root.problems.join("\n");
                if (key === root.shown)
                    return;
                root.shown = key;
                if (root.problems.length === 0)
                    return;
                const more = root.problems.length > 1 ? " (+" + (root.problems.length - 1) + " more: simplychit check-settings)" : "";
                Notifs.toast("settings.json: " + root.problems.length + (root.problems.length === 1 ? " problem" : " problems"), root.problems[0] + more, "\u{f0026}", true);
            }
        }
    }
}
