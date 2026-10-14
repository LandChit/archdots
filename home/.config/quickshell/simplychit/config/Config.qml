pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shell's settings. Defaults are declared below; ~/.config/simplychit/settings.json
// overrides any of them and is picked up live when it changes on disk.
//
// Read a setting as Config.bar.showCpu. Change one with Config.set("bar.showCpu", false).
//
// Never writeAdapter(): it rewrites the whole file from the declared properties,
// dropping every key it does not know and writing every default (checked on
// quickshell 0.3.2). set() edits the parsed file instead, so only the key that
// changed is written and hand edits, unknown keys included, survive.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/simplychit/settings.json"

    property alias bar: adapter.bar
    property alias appearance: adapter.appearance
    property alias audio: adapter.audio
    property alias launcher: adapter.launcher
    property alias battery: adapter.battery
    property alias wallpaper: adapter.wallpaper
    property alias theme: adapter.theme
    property alias toasts: adapter.toasts
    property alias lock: adapter.lock
    property alias idle: adapter.idle
    property alias apps: adapter.apps
    property alias notifications: adapter.notifications
    property alias input: adapter.input
    property alias keybinds: adapter.keybinds
    property alias displays: adapter.displays

    // Sets one key, given as a dotted path, in settings.json. Returns false and
    // leaves the file alone if it is not valid JSON: a hand edit in progress is
    // the user's, not something to overwrite.
    function set(key: string, value: var): bool {
        let doc = {};
        const text = file.text();
        if (text.trim() !== "") {
            try {
                doc = JSON.parse(text);
            } catch (e) {
                console.warn("settings.json is not valid JSON, not writing " + key + ": " + e);
                return false;
            }
        }

        const parts = key.split(".");
        let node = doc;
        for (const part of parts.slice(0, -1)) {
            if (typeof node[part] !== "object" || node[part] === null)
                node[part] = {};
            node = node[part];
        }
        node[parts[parts.length - 1]] = value;

        file.setText(JSON.stringify(doc, null, 2) + "\n");
        return true;
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        atomicWrites: true
        // A missing file is normal (nothing changed yet): the defaults apply.
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter

            property JsonObject bar: JsonObject {
                property bool showMedia: true
                property bool showCpu: true
                property bool showBattery: true
                property string clockFormat: "hh:mm AP"
                // Shown in place of the window title when nothing is focused.
                property string emptyTitle: "Chit"
                property int titleChars: 20
                property int mediaChars: 28
                // Per screen (TODO C7): any bar key above, by monitor name,
                // e.g. { "HDMI-A-1": { "showMedia": false } }
                property var monitors: ({})
                // Screens with no bar at all.
                property list<string> excluded: []
                // Which islands, in order, on each side.
                property list<string> left: ["workspaces", "special", "title"]
                property list<string> right: ["media", "resources", "clock"]
            }

            property JsonObject appearance: JsonObject {
                // Multiplies the opacity of the bar's islands and the panels:
                // 1 as designed, lower is more see-through (0.5 at least).
                property real opacity: 1
            }

            property JsonObject launcher: JsonObject {
                // Desktop entry ids (firefox.desktop -> "firefox") pinned to
                // the top, in this order. Ctrl+P in the launcher toggles one.
                property list<string> favourites: []
                // Never listed. Ctrl+H hides one; "> unhide" brings it back.
                property list<string> hidden: []
                // %s is the query.
                property string searchUrl: "https://www.google.com/search?q=%s"
            }

            property JsonObject battery: JsonObject {
                // Warnings while discharging, at or below these percentages.
                property int lowPercent: 20
                property int criticalPercent: 10
                // At this level, after a 30 s countdown you can cancel:
                // "suspend", "hibernate", "poweroff" or "none" (TODO C13).
                property int actionPercent: 5
                property string criticalAction: "suspend"
            }

            property JsonObject wallpaper: JsonObject {
                property string directory: "~/Pictures/wallpapers"
                // Change to another wallpaper from the folder every N minutes;
                // 0 is off (TODO 16).
                property int cycleMinutes: 0
                // Crossfade length when the wallpaper changes, in ms; 0 is a cut.
                property int transitionMs: 700
            }

            property JsonObject theme: JsonObject {
                // pywal16's palette from the wallpaper: "dark" or "light" (wal -l)
                property string mode: "dark"
                // a backend from `wal --backend`; some need extra Python packages
                property string backend: "wal"
            }

            // What the launch keybinds run (hypr/config/keybind.lua reads these
            // too); the terminal is also the launcher's, for apps that ask for
            // one and for "!" commands with Shift.
            property JsonObject apps: JsonObject {
                property string terminal: "alacritty"
                property string browser: "zen-browser"
                property string fileManager: "dolphin"
                property string processManager: "flatpak run io.missioncenter.MissionCenter"
            }

            property JsonObject notifications: JsonObject {
                // Seconds a popup stays when the app does not say; critical
                // ones stay until closed regardless.
                property int timeout: 5
                // Do not disturb between these times every day ("HH:mm").
                property JsonObject schedule: JsonObject {
                    property bool enabled: false
                    property string from: "22:00"
                    property string to: "07:00"
                }
            }

            // Read by hypr/config/input.lua (only known keys, right types).
            property JsonObject input: JsonObject {
                property string kb_layout: "us"
                property string kb_variant: ""
                property string kb_options: ""
                property real sensitivity: 0
                property JsonObject touchpad: JsonObject {
                    property bool natural_scroll: true
                    property bool tap_to_click: true
                    property bool disable_while_typing: true
                }
            }

            // Read by hypr/config/keybind.lua: id -> keys, and ids to drop.
            property JsonObject keybinds: JsonObject {
                property var remap: ({})
                property list<string> disabled: []
            }

            // Written by the Displays page; read by hypr/config/monitor.lua.
            property JsonObject displays: JsonObject {
                property string active: ""
                property var profiles: ({})
            }

            // Minutes idle before each step, on AC and on battery; 0 is never.
            // Stay awake (SUPER+SHIFT+I) and apps that inhibit idle pause all
            // of it. Locking before suspend is hypridle's job (hypridle.conf).
            property JsonObject idle: JsonObject {
                property JsonObject ac: JsonObject {
                    property real dim: 2.5
                    property real lock: 5
                    property real screenOff: 5.5
                    property real suspend: 30
                }
                property JsonObject battery: JsonObject {
                    property real dim: 1
                    property real lock: 2
                    property real screenOff: 2.5
                    property real suspend: 10
                }
            }

            property JsonObject lock: JsonObject {
                // Off by default: hyprlock locks. On, the shell's own lock
                // screen does (hypr/Scripts/lock.sh asks it first and falls
                // back to hyprlock). Try `ipc call lock preview` first.
                property bool enabled: false
                // the PAM service the password is checked against
                property string pamConfig: "login"
            }

            // Which events show a toast (TODO C9).
            property JsonObject toasts: JsonObject {
                property bool charging: true
                property bool locks: true
                property bool keyboardLayout: true
                property bool audioDevice: true
                property bool vpn: true
                property bool nowPlaying: false
                property bool dnd: true
            }

            property JsonObject audio: JsonObject {
                // Percentage points per scroll notch over the volume meter.
                property int scrollStep: 5
                // 1.0 is 100%; 2.0 matches the volume keys' wpctl -l 2.
                property real maxVolume: 2.0
            }
        }
    }
}
