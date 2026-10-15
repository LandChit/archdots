pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// Screen recording with wf-recorder: a region (picked with slurp) or the
// focused screen, to recording.directory as mp4. The bar shows a red dot and
// the time while it runs; a click there, the screenshot menu or SUPER+SHIFT+R
// stops it.
//
// The recording belongs to the shell: restarting the shell mid-recording
// kills wf-recorder without letting it finish, and that file will not play.
//
// qs -c simplychit ipc call recording region|screen|stop|toggle
Singleton {
    id: root

    property bool recording: false
    // slurp is up: not recording yet, so no indicator
    property bool picking: false
    property int seconds: 0
    // stop() was asked for: the exit is ours, not a failure
    property bool stopping: false
    property string file: ""

    readonly property string directory: Config.recording.directory.replace(/^~/, Quickshell.env("HOME"))
    readonly property string elapsed: Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")

    function region(): void {
        if (recording || picking)
            return;
        picking = true;
        slurp.running = true;
    }

    function screen(): void {
        if (recording || picking)
            return;
        const monitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        start(monitor !== "" ? ["-o", monitor] : []);
    }

    function stop(): void {
        // SIGINT is wf-recorder's Ctrl+C: it finishes the file and exits
        if (recording) {
            stopping = true;
            recorder.signal(2);
        }
    }

    // stop a running one, or else record a region
    function toggle(): void {
        if (recording)
            stop();
        else
            region();
    }

    function start(where: var): void {
        file = directory + "/Recording-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        // wf-recorder's -a takes a PulseAudio source; desktop sound is the
        // default sink's monitor. The device is looked up now, not at login,
        // so a headset plugged in since is the one recorded.
        recorder.command = ["sh", "-c", `
            mkdir -p "$1" || exit 1
            case "$2" in
                desktop) A="--audio=$(pactl get-default-sink).monitor" ;;
                mic) A="--audio=$(pactl get-default-source)" ;;
                *) A="" ;;
            esac
            F="$3"
            shift 3
            exec wf-recorder $A "$@" -f "$F"
        `, "sh", directory, Config.recording.audio, file].concat(where);
        seconds = 0;
        stopping = false;
        recording = true;
        recorder.running = true;
    }

    Process {
        id: slurp

        // slurp reads preset boxes from stdin when it is not a terminal, and
        // a Process keeps stdin open: without </dev/null it waits forever
        // and never shows the selection.
        command: ["sh", "-c", "slurp </dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.picking = false;
                const geometry = text.trim();
                // empty: Esc in slurp, a cancel and not an error
                if (geometry !== "")
                    root.start(["-g", geometry]);
            }
        }
    }

    Process {
        id: recorder

        stderr: StdioCollector {
            id: errors
        }

        onExited: code => {
            const ran = root.seconds;
            const asked = root.stopping;
            root.recording = false;
            root.stopping = false;
            if (code === 0 || (asked && ran >= 1))
                Quickshell.execDetached(["notify-send", "-a", "SimplyChit", "-i", "video-x-generic", "--", "Recording saved", root.file.replace(Quickshell.env("HOME"), "~")]);
            // stopped within a second, possibly before wf-recorder started:
            // a cancel, not a failure
            else if (!asked)
                Quickshell.execDetached(["notify-send", "-a", "SimplyChit", "-u", "critical", "--", "Recording failed", errors.text.trim().split("\n").slice(-2).join("\n") || "wf-recorder exited with " + code]);
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.seconds++
    }
}
