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
    // false until settings.json has been read (or found missing): before
    // that every setting is its default
    property bool ready: false

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
    property alias brightness: adapter.brightness
    property alias recording: adapter.recording
    property alias sounds: adapter.sounds

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
        onLoaded: root.ready = true
        onLoadFailed: root.ready = true

        JsonAdapter {
            id: adapter

            property JsonObject bar: JsonObject {
                property bool showMedia: true
                property bool showCpu: true
                property bool showBattery: true
                property string clockFormat: "hh:mm AP"
                // The calendar's events from khal, and its "set up khal" line.
                // Off: a plain month, and khal is never run.
                property bool calendarEvents: true
                // Shown in place of the window title when nothing is focused.
                property string emptyTitle: "Chit"
                property int titleChars: 20
                property int mediaChars: 28
                // Per screen: any bar key, by the monitor's description
                // ("BOE 0x094D") or port ("eDP-1"). One with left, center or
                // right has its own layout: { "HDMI-A-1": { "right": ["clock"] } }
                property var monitors: ({})
                // Screens with no bar at all, by description or port.
                property list<string> excluded: []
                // The default layout: which widgets, in order, in each section.
                // workspaces, special, title, media, indicators, volume, cpu,
                // battery, clock ("resources" is the four status ones).
                property list<string> left: ["workspaces", "special", "title"]
                property list<string> center: []
                property list<string> right: ["media", "indicators", "volume", "cpu", "battery", "clock"]
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
                property string processManager: "missioncenter || flatpak run io.missioncenter.MissionCenter"
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

            // Read by hypr/config/rules.lua: the games scratchpad.
            property JsonObject games: JsonObject {
                // More window classes (regular expressions, ^…$ for an exact
                // one) that open fullscreen in the games scratchpad. Windows
                // sent there by hand are listed in
                // ~/.config/simplychit/games-to-review.txt.
                property list<string> classes: []
            }

            // Read by hypr/config/keybind.lua: id -> keys, and ids to drop.
            property JsonObject keybinds: JsonObject {
                property var remap: ({})
                property list<string> disabled: []
                // More scratchpads: name -> { "keys": "SUPER + M", "command":
                // "spotify" }. The command starts when the scratchpad is empty.
                property var scratchpads: ({})
            }

            // Written by the Displays page; read by hypr/config/monitor.lua.
            property JsonObject displays: JsonObject {
                property string active: ""
                property var profiles: ({})
                // The main screen, by description (or port name): the login
                // screen shows there (services/Screens.qml). Empty: the built-in panel, else
                // the first screen.
                property string primary: ""
            }

            // Screen brightness: the laptop panel (brightnessctl) and external
            // monitors over DDC/CI (ddcutil).
            property JsonObject brightness: JsonObject {
                // true: the brightness keys and the control centre's slider
                // set every screen to the same level. false: the keys set the
                // focused screen, and each screen has its own slider.
                property bool linked: false
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
                // The keypad types digits on the lock and login screens, as
                // if Num Lock were on, whatever its state.
                property bool numlock: true
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

            // Event sounds (freedesktop sound theme, played with pw-play).
            property JsonObject sounds: JsonObject {
                // a tick when the output volume changes
                property bool volume: true
                // a chime when a notification pops up (not under do not disturb)
                property bool notifications: true
            }

            // Screen recording (the screenshot menu, SUPER+SHIFT+R).
            property JsonObject recording: JsonObject {
                property string directory: "~/Videos/recordings"
                // Sound in the recording: "none", "desktop" (what you hear)
                // or "mic" (the default input).
                property string audio: "none"
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
