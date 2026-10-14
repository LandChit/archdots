pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shell's settings. Defaults are declared below; ~/.config/archdots/settings.json
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

    readonly property string path: Quickshell.env("HOME") + "/.config/archdots/settings.json"

    property alias bar: adapter.bar
    property alias audio: adapter.audio

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
            }

            property JsonObject audio: JsonObject {
                // Percentage points per scroll notch over the volume meter.
                property int scrollStep: 5
                // 1.0 is 100%. The fabric bar allowed up to 200% (wpctl -l 2).
                property real maxVolume: 2.0
            }
        }
    }
}
