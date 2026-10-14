pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screen brightness for the focused monitor: the laptop panel through
// brightnessctl, an external monitor over DDC/CI through ddcutil (TODO 19).
//
// ddcutil is optional. It needs the i2c-dev module loaded and access to
// /dev/i2c-* (the i2c group, or ddcutil's udev rule); without it, external
// monitors are simply not adjustable from here.
//
// qs -c simplychit ipc call brightness up|down|set <percent>
Singleton {
    id: root

    // 0..100 for whichever monitor was last read or changed, -1 if none
    property int percent: -1
    property string device: ""
    // monitor connector name -> ddcutil display number
    property var ddcDisplays: ({})
    property bool hasDdcutil: false

    readonly property string focused: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    // eDP, LVDS and DSI are built-in panels with a kernel backlight
    readonly property bool internal: /^(eDP|LVDS|DSI)-/.test(focused)

    signal changed

    function step(delta: int): void {
        set(Math.max(1, Math.min(100, (percent < 0 ? 50 : percent) + delta)));
    }

    function set(value: int): void {
        value = Math.max(1, Math.min(100, value));
        if (internal || ddcDisplays[focused] === undefined) {
            // -e4: perceptual curve, as the old keybind used
            setter.command = ["brightnessctl", "-e4", "-n2", "set", value + "%"];
        } else {
            setter.command = ["ddcutil", "--noverify", "--display", String(ddcDisplays[focused]), "setvcp", "10", String(value)];
        }
        percent = value;
        setter.running = true;
        changed();
    }

    function refresh(): void {
        if (internal || ddcDisplays[focused] === undefined)
            reader.command = ["brightnessctl", "-m"];
        else
            reader.command = ["ddcutil", "--display", String(ddcDisplays[focused]), "getvcp", "10", "--terse"];
        reader.running = true;
    }

    onFocusedChanged: refresh()

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                // brightnessctl -m: intel_backlight,backlight,128,50%,255
                let match = line.match(/^[^,]*,backlight,\d+,(\d+)%/);
                if (match) {
                    root.percent = parseInt(match[1]);
                    return;
                }
                // ddcutil --terse: VCP 10 C 60 100
                match = line.match(/^VCP 10 C (\d+) (\d+)/);
                if (match)
                    root.percent = Math.round(100 * parseInt(match[1]) / parseInt(match[2]));
            }
        }
    }

    Process {
        id: setter
    }

    // Which DRM connector each DDC display is on, read once at startup.
    Process {
        running: true
        command: ["sh", "-c", "command -v ddcutil >/dev/null && ddcutil detect --terse 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                let display = null;
                for (const line of text.split("\n")) {
                    const d = line.match(/^Display (\d+)/);
                    if (d)
                        display = parseInt(d[1]);
                    const c = line.match(/DRM[_ ]connector:\s+card\d+-(\S+)/i);
                    if (c && display !== null)
                        map[c[1]] = display;
                }
                root.hasDdcutil = text.trim() !== "";
                root.ddcDisplays = map;
                root.refresh();
            }
        }
    }
}
