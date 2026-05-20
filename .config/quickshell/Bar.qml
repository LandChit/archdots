import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "./"

PanelWindow {
    id: bar
    required property var screen

    anchors { top: true; left: true; right: true }
    exclusiveZone: height
    height: 32
    color: Palette.bg

    // Workspaces shown on this specific monitor
    property var wsIds: {
        const n = screen.name
        if (n === "eDP-1")    return [2, 4, 6, 8, 10]
        if (n === "HDMI-A-1") return [1, 3, 5, 7, 9]
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }

    // Find the Hyprland monitor that matches this quickshell screen
    property var hlMonitor: {
        for (const m of Hyprland.monitors) {
            if (m.name === screen.name) return m
        }
        return null
    }
    property int activeWsId: hlMonitor?.activeWorkspace?.id ?? -1

    RowLayout {
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
        spacing: 0

        // ── Workspaces ─────────────────────────────────────────────
        RowLayout {
            spacing: 2
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: bar.wsIds
                delegate: Rectangle {
                    required property int modelData
                    readonly property bool active: modelData === bar.activeWsId
                    readonly property bool occupied: {
                        for (const c of Hyprland.clients) {
                            if (c.workspace?.id === modelData) return true
                        }
                        return false
                    }

                    width: 26; height: 22; radius: 4
                    color: active   ? Palette.accent
                         : occupied ? Palette.surface
                                    : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.toString()
                        color: parent.active   ? Palette.bg
                             : parent.occupied ? Palette.fg
                                               : Palette.muted
                        font { family: Palette.font; pixelSize: 11; bold: parent.active }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + parent.modelData)
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // ── Active window title ────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: bar.width * 0.35
            text: Hyprland.focusedClient?.title ?? "Desktop"
            color: Palette.fg
            font { family: Palette.font; pixelSize: 12 }
            elide: Text.ElideRight
        }

        Item { Layout.fillWidth: true }

        // ── System tray ────────────────────────────────────────────
        RowLayout {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter

            // Volume
            Text {
                id: volLabel
                color: Palette.fg
                font { family: Palette.font; pixelSize: 12 }
                property string val: "–"
                text: "󰕾 " + val
                Timer {
                    interval: 3000; repeat: true; triggeredOnStart: true; running: true
                    onTriggered: if (!volProc.running) volProc.running = true
                }
                Process {
                    id: volProc
                    command: ["bash", "-c",
                        "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"%d%%\", $2*100}'"]
                    stdout: SplitParser { onRead: (l) => volLabel.val = l.trim() }
                }
            }

            // CPU Temperature
            Text {
                id: tempLabel
                font { family: Palette.font; pixelSize: 12 }
                property int deg: 0
                color: deg > 90 ? Palette.color9 : Palette.fg
                text: " " + (deg > 0 ? deg + "°C" : "–")
                Timer {
                    interval: 4000; repeat: true; triggeredOnStart: true; running: true
                    onTriggered: if (!tempProc.running) tempProc.running = true
                }
                Process {
                    id: tempProc
                    command: ["bash", "-c",
                        "awk '{printf \"%d\", $1/1000}' " +
                        "/sys/class/hwmon/hwmon5/temp1_input 2>/dev/null || echo 0"]
                    stdout: SplitParser { onRead: (l) => tempLabel.deg = parseInt(l) || 0 }
                }
            }

            // Battery
            Text {
                id: batLabel
                font { family: Palette.font; pixelSize: 12 }
                property int pct: 100
                property string status: "Full"
                color: pct < 15 ? Palette.color9 : pct < 30 ? Palette.color3 : Palette.fg
                text: {
                    const icons = ["", "", "", "", ""]
                    const icon  = status === "Charging"
                                ? ""
                                : icons[Math.min(4, Math.floor(pct / 25))]
                    return icon + " " + pct + "%"
                }
                Timer {
                    interval: 10000; repeat: true; triggeredOnStart: true; running: true
                    onTriggered: if (!batProc.running) batProc.running = true
                }
                Process {
                    id: batProc
                    command: ["bash", "-c",
                        "p=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
                        "s=$(cat /sys/class/power_supply/BAT*/status   2>/dev/null | head -1); " +
                        "echo \"${p:-0} ${s:-Unknown}\""]
                    stdout: SplitParser {
                        onRead: function(l) {
                            const p = l.trim().split(" ")
                            batLabel.pct    = parseInt(p[0]) || 0
                            batLabel.status = p[1] || "Unknown"
                        }
                    }
                }
            }

            // Clock
            Text {
                id: clockLabel
                color: Palette.fg
                font { family: Palette.font; pixelSize: 12 }
                text: Qt.formatDateTime(new Date(), "hh:mm")
                Timer {
                    interval: 30000; repeat: true; triggeredOnStart: true; running: true
                    onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "hh:mm")
                }
            }
        }
    }
}
