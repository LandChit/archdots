pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The media panel's spectrum: cava reading what plays (PipeWire, the default
// output's monitor), `bars` levels 0..1 at 30 frames a second. cava only runs
// while `wanted` (the panel is open). Without cava installed `available`
// stays false and the panel leaves the visualiser out.
Singleton {
    id: root

    property bool wanted: false
    readonly property int bars: 36
    property var levels: []
    property bool available: false

    // the config goes in through a process substitution, so nothing is
    // written to disk; `exec` so stopping the process stops cava
    readonly property string config: ["[general]", "bars = " + bars, "framerate = 30", "sleep_timer = 0",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10",
        "[smoothing]", "noise_reduction = 60"].join("\n")

    Process {
        id: cava

        running: root.wanted
        command: ["bash", "-c", "command -v cava >/dev/null || exit 127; exec cava -p <(printf '%s\\n' \"$1\")", "bash", root.config]
        stdout: SplitParser {
            onRead: line => {
                const values = line.split(";").filter(v => v !== "").map(v => Math.min(1, parseInt(v) / 1000));
                if (values.length === root.bars)
                    root.levels = values;
            }
        }
        onExited: code => {
            root.levels = [];
            // 127: not installed; the panel then has no visualiser
            if (code === 127)
                root.available = false;
        }
    }

    // levels at rest until the first frame, so the visualiser does not jump
    onWantedChanged: {
        if (wanted)
            levels = new Array(bars).fill(0);
    }

    // looked up once at start, so the panel knows before cava's first frame
    Process {
        running: true
        command: ["bash", "-c", "command -v cava"]
        onExited: code => root.available = code === 0
    }
}
