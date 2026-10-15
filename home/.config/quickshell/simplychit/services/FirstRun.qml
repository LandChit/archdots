pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The welcome window (modules/welcome): shown once, on the first start of the
// shell after a fresh install. Closing it, finished or not, leaves a marker in
// ~/.local/state/simplychit/welcomed; install.sh's update leaves it too, since
// an existing install is not a first run.
// qs -c simplychit ipc call welcome open   (any time; the launcher's > has it)
Singleton {
    id: root

    readonly property string marker: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/simplychit/welcomed"

    property bool open: false

    function show(): void {
        open = true;
    }

    function done(): void {
        open = false;
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "sh", marker]);
    }

    FileView {
        path: root.marker
        printErrors: false
        // no marker: a first run. A moment after start, so the bar and the
        // wallpaper are up behind it.
        onLoadFailed: firstStart.start()
    }

    Timer {
        id: firstStart

        interval: 2000
        onTriggered: root.show()
    }
}
