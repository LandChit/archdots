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
                let r;
                try {
                    r = JSON.parse(text);
                } catch (e) {
                    // a run stopped by a newer load() ends with no output
                    return;
                }
                // an answer for a day clicked before the current one
                if (r.day !== root.day)
                    return;
                root.loading = false;
                root.available = r.available;
                root.reason = r.error ?? "";
                // khal's order: all-day first, then by start
                root.events = r.events;
            }
        }
    }
}
