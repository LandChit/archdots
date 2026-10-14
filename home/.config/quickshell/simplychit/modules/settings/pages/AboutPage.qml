import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.widgets

// What `simplychit doctor` finds: the programs the desktop needs, what should be
// running, whether the config parses, and versions.
ColumnLayout {
    id: page

    spacing: 14

    property var results: []
    property bool checking: true
    readonly property var groups: [...new Set(results.map(r => r.group))]

    function check(): void {
        checking = true;
        doctor.running = true;
    }

    Component.onCompleted: check()

    Process {
        id: doctor

        command: [Quickshell.env("HOME") + "/.local/bin/simplychit", "doctor", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.results = JSON.parse(text);
                } catch (e) {
                    page.results = [{ group: "Doctor", name: "simplychit doctor", status: "fail", detail: "could not run ~/.local/bin/simplychit (is it stowed?)" }];
                }
                page.checking = false;
            }
        }
    }

    // A command that never starts gives no output to finish: stopped, and
    // still checking a second later, means it could not run.
    Timer {
        interval: 1000
        running: page.checking && !doctor.running
        onTriggered: {
            page.results = [{ group: "Doctor", name: "simplychit doctor", status: "fail", detail: "could not run ~/.local/bin/simplychit (is it stowed?)" }];
            page.checking = false;
        }
    }

    PageTitle {
        title: "About"
        description: "SimplyChit — Hyprland and a Quickshell desktop, themed from the wallpaper. The same checks run in a terminal with `simplychit doctor`."
    }

    RowLayout {
        spacing: 8

        Button {
            text: page.checking ? "Checking…" : "Check again"
            enabled: !page.checking
            onClicked: page.check()
        }
        Button {
            text: "Open the config folder"
            onClicked: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/simplychit"])
        }
        Button {
            text: "Hyprland override log"
            onClicked: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.cache/hypr-custom.log"])
        }
    }

    Repeater {
        model: page.groups

        Section {
            id: group

            required property string modelData

            title: modelData

            Repeater {
                model: page.results.filter(r => r.group === group.modelData)

                Setting {
                    required property var modelData

                    label: modelData.name
                    help: modelData.detail

                    BarText {
                        text: modelData.status === "ok" ? "\u{f012c}" : modelData.status === "warn" ? "\u{f0026}" : "\u{f0156}"
                        px: 16
                        color: modelData.status === "ok" ? Colours.accentBright : modelData.status === "warn" ? Qt.rgba(232 / 255, 168 / 255, 74 / 255, 1) : Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1)
                    }
                }
            }
        }
    }
}
