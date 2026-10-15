pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Screen brightness, one level per screen: the laptop panel through
// brightnessctl, external monitors over DDC/CI through ddcutil (TODO 19).
// With Config.brightness.linked, every change goes to all of them at once;
// otherwise the keys change the focused screen and the control centre has a
// slider for each.
//
// ddcutil is optional. It needs the i2c-dev module loaded and access to
// /dev/i2c-* (the i2c group, or ddcutil's udev rule); without it, external
// monitors are simply not adjustable from here.
//
// qs -c simplychit ipc call brightness up|down|set <percent>
Singleton {
    id: root

    // monitor connector name -> ddcutil display number (IdleTimers dims these)
    property var ddcDisplays: ({})
    property bool hasDdcutil: false
    property bool hasBacklight: false
    // connector -> 1..100, for every screen read so far
    property var levels: ({})

    readonly property bool linked: Config.brightness.linked
    readonly property string focused: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // The screens whose brightness can be set, in Hyprland's order:
    // [{ name, label, ddc }], ddc -1 for a built-in panel.
    readonly property var screens: {
        const out = [];
        for (const m of Hyprland.monitors.values) {
            if (isInternal(m.name)) {
                if (hasBacklight)
                    out.push({ name: m.name, label: "Built-in", ddc: -1 });
            } else if (ddcDisplays[m.name] !== undefined) {
                out.push({ name: m.name, label: m.description || m.name, ddc: ddcDisplays[m.name] });
            }
        }
        return out;
    }

    // What the keys change: the focused screen, or the first one that can be
    // set when the focused one cannot (a monitor without DDC/CI).
    readonly property string target: screens.some(s => s.name === focused) ? focused : (screens.length ? screens[0].name : "")
    // the target's level, -1 if there is none
    readonly property int percent: levels[target] ?? -1

    signal changed

    function isInternal(name: string): bool {
        // eDP, LVDS and DSI are built-in panels with a kernel backlight
        return /^(eDP|LVDS|DSI)-/.test(name);
    }

    function step(delta: int): void {
        set((percent < 0 ? 50 : percent) + delta);
    }

    // The keys and the IPC: the target screen, or every screen when linked.
    function set(value: int): void {
        setScreen(linked ? "" : target, value);
    }

    // One screen by connector name, or all of them for "".
    function setScreen(name: string, value: int): void {
        value = Math.max(1, Math.min(100, value));
        const next = Object.assign({}, levels);
        for (const s of screens) {
            if (name !== "" && s.name !== name)
                continue;
            next[s.name] = value;
            pending[s.name] = s.ddc < 0
                // -e4: perceptual curve, as the old keybind used
                ? ["brightnessctl", "-e4", "-n2", "set", value + "%"]
                : ["ddcutil", "--noverify", "--display", String(s.ddc), "setvcp", "10", String(value)];
        }
        levels = next;
        flush();
        changed();
    }

    // ── writing ──────────────────────────────────────────────────────────
    // One write at a time, the newest level per screen: a slider dragged
    // faster than ddcutil can follow skips the levels in between, and the
    // last one always lands.
    property var pending: ({})

    function flush(): void {
        if (writer.running)
            return;
        const name = Object.keys(pending)[0];
        if (name === undefined)
            return;
        writer.command = pending[name];
        delete pending[name];
        writer.running = true;
    }

    Process {
        id: writer

        onExited: Qt.callLater(root.flush)
    }

    // ── reading ──────────────────────────────────────────────────────────
    // Every screen in one go, the DDC ones side by side (ddcutil takes a
    // moment each). Prints "<connector> <percent>" per screen. Under the idle
    // dim's lock (IdleTimers), and nothing while the screens are dimmed: a
    // read then would take the dimmed level for the real one.
    property bool rereadAfter: false

    function refresh(): void {
        if (screens.length === 0)
            return;
        if (reader.running) {
            rereadAfter = true;
            return;
        }
        reader.command = ["flock", Quickshell.env("XDG_RUNTIME_DIR") + "/simplychit-dim.lock", "sh", "-c", `
            [ -e "$XDG_RUNTIME_DIR/simplychit-dim" ] && exit 0
            while [ $# -gt 0 ]; do
                name=$1 ddc=$2; shift 2
                if [ "$ddc" = -1 ]; then
                    brightnessctl -m | awk -F, -v n="$name" '$2 == "backlight" { sub("%", "", $4); print n, $4; exit }'
                else
                    ddcutil --display "$ddc" getvcp 10 --terse 2>/dev/null \\
                        | awk -v n="$name" '$1 == "VCP" && $5 > 0 { print n, int(100 * $4 / $5 + 0.5) }' &
                fi
            done
            wait
        `, "sh"].concat(...screens.map(s => [s.name, String(s.ddc)]));
        reader.running = true;
    }

    onScreensChanged: refresh()

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: {
                const next = Object.assign({}, root.levels);
                for (const line of text.split("\n")) {
                    const m = line.match(/^(\S+) (\d+)$/);
                    // a write still waiting would be undone by the old level
                    if (m && root.pending[m[1]] === undefined)
                        next[m[1]] = parseInt(m[2]);
                }
                root.levels = next;
            }
        }
        onExited: {
            if (root.rereadAfter) {
                root.rereadAfter = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    // ── which screens there are ──────────────────────────────────────────
    // Whether there is a backlight, and which DRM connector each DDC display
    // is on: at startup, and again when a monitor is plugged in or out.
    function detect(): void {
        if (!detector.running)
            detector.running = true;
    }

    Process {
        id: detector

        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | grep -q . && echo backlight; command -v ddcutil >/dev/null && ddcutil detect --terse 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                let display = null;
                for (const line of text.split("\n")) {
                    // a block per monitor; "Invalid display" (no DDC/CI,
                    // like a laptop panel) must not take the previous number
                    if (/^\S/.test(line)) {
                        const d = line.match(/^Display (\d+)/);
                        display = d ? parseInt(d[1]) : null;
                    }
                    const c = line.match(/DRM[_ ]connector:\s+card\d+-(\S+)/i);
                    if (c && display !== null)
                        map[c[1]] = display;
                }
                root.hasBacklight = /^backlight$/m.test(text);
                root.hasDdcutil = /^Display \d+/m.test(text);
                root.ddcDisplays = map;
            }
        }
    }

    // ddcutil only sees a monitor once it is up, so look a moment later
    Timer {
        id: redetect

        interval: 3000
        onTriggered: root.detect()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (event.name.startsWith("monitoradded") || event.name.startsWith("monitorremoved"))
                redetect.restart();
        }
    }
}
