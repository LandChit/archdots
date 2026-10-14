import QtQuick
import Quickshell
import Quickshell.Io

// Pick tallies in a JSON file, used to float frequent entries to the top.
// Not a singleton: each picker keeps its own file.
//
//   UsageCounts { id: usage; file: "launcher" }
//   usage.bump(id); items.sort((a, b) => usage.count(b.id) - usage.count(a.id))
Item {
    id: root

    // ~/.local/state/archdots/<file>-counts.json
    required property string file
    // Read once if the file above does not exist yet (tallies kept by the
    // shell before this one).
    property string importFrom: ""

    property var counts: ({})

    function count(key: string): int {
        return counts[key] ?? 0;
    }

    function bump(key: string): void {
        const next = Object.assign({}, counts);
        next[key] = (next[key] ?? 0) + 1;
        counts = next;
        store.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function parse(text: string): var {
        try {
            const parsed = JSON.parse(text);
            return typeof parsed === "object" && parsed !== null ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    FileView {
        id: store

        path: Quickshell.env("HOME") + "/.local/state/archdots/" + root.file + "-counts.json"
        printErrors: false
        onLoaded: root.counts = root.parse(text())
        onLoadFailed: legacy.path = root.importFrom
    }

    FileView {
        id: legacy

        printErrors: false
        onLoaded: root.counts = root.parse(text())
    }
}
