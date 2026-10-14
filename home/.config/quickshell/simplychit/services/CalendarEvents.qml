pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One day's events from khal, for the calendar panel (TODO 9). khal reads
// local calendars; vdirsyncer keeps them in step with Google or any CalDAV
// server (its vdirsyncer.timer user unit syncs every 15 minutes).
// CUSTOMIZING.md has the setup.
//
// `simplychit events <date>` does the khal call: khal only parses dates in the
// user's own format, and the CLI reads that from khal's config.
Singleton {
    id: root

    // false: khal missing or not set up; `reason` says which
    property bool available: false
    property string reason: ""
    property var events: []
    property bool loading: false
    property string day: ""

    function iso(d: date): string {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function load(d: date): void {
        day = iso(d);
        loading = true;
        proc.running = false;
        proc.command = [Quickshell.env("HOME") + "/.local/bin/simplychit", "events", day];
        proc.running = true;
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const r = JSON.parse(text);
                    root.available = r.available;
                    root.reason = r.error ?? "";
                    // all-day ones first, then by start time
                    root.events = r.events.sort((a, b) => a.allDay !== b.allDay ? (a.allDay ? -1 : 1) : a.start.localeCompare(b.start));
                } catch (e) {
                    root.available = false;
                    root.reason = "simplychit events gave no answer";
                    root.events = [];
                }
            }
        }
    }
}
