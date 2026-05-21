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
    exclusiveZone: implicitHeight
    implicitHeight: 32
    color: Palette.bg

    property var wsIds: {
        const n = screen.name
        if (n === "eDP-1")    return [2, 4, 6, 8, 10]
        if (n === "HDMI-A-1") return [1, 3, 5, 7, 9]
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }

    property var hlMonitor: {
        for (const m of Hyprland.monitors) {
            if (m.name === screen.name) return m
        }
        return null
    }
    property int activeWsId: hlMonitor?.activeWorkspace?.id ?? -1

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        spacing: 0

        // ── Title (left) ───────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: bar.width * 0.22
            text: Hyprland.focusedClient?.title ?? "Desktop"
            color: Palette.muted
            font { family: Palette.font; pixelSize: 12 }
            elide: Text.ElideRight
        }

        Item { Layout.fillWidth: true }

        // ── Workspaces pill (center) ───────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            height: 24
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.10)
            implicitWidth: wsRow.implicitWidth + 12

            Row {
                id: wsRow
                anchors.centerIn: parent
                spacing: 2

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

                        width: 24; height: 18; radius: 5
                        color: active   ? Palette.accent
                             : occupied ? Qt.rgba(1, 1, 1, 0.07)
                                        : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData === 10 ? "0" : parent.modelData.toString()
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
        }

        Item { Layout.fillWidth: true }

        // ── Status pills (right) ───────────────────────────────────
        Row {
            spacing: 5
            Layout.alignment: Qt.AlignVCenter

            // Network + Bluetooth pill
            Rectangle {
                height: 24; radius: 12
                color: Qt.rgba(1, 1, 1, 0.10)
                width: netBtRow.implicitWidth + 16
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: netBtRow
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        id: wifiIcon
                        property bool up: false
                        color: up ? Palette.accent : Palette.muted
                        font { family: Palette.font; pixelSize: 14 }
                        text: up ? "󰤨" : "󰤭"
                        anchors.verticalCenter: parent.verticalCenter
                        Timer {
                            interval: 8000; repeat: true; triggeredOnStart: true; running: true
                            onTriggered: if (!wifiProc.running) wifiProc.running = true
                        }
                        Process {
                            id: wifiProc
                            command: ["bash", "-c",
                                "for f in /sys/class/net/wl*/operstate; do " +
                                "  [ -f \"$f\" ] && cat \"$f\" && exit; done; echo down"]
                            stdout: SplitParser { onRead: (l) => wifiIcon.up = l.trim() === "up" }
                        }
                    }

                    Text {
                        id: btIcon
                        property bool connected: false
                        color: connected ? Palette.accent : Palette.muted
                        font { family: Palette.font; pixelSize: 14 }
                        text: "󰂯"
                        anchors.verticalCenter: parent.verticalCenter
                        Timer {
                            interval: 8000; repeat: true; triggeredOnStart: true; running: true
                            onTriggered: if (!btProc.running) btProc.running = true
                        }
                        Process {
                            id: btProc
                            command: ["bash", "-c",
                                "bluetoothctl info 2>/dev/null | grep -c 'Connected: yes' || echo 0"]
                            stdout: SplitParser { onRead: (l) => btIcon.connected = parseInt(l.trim()) > 0 }
                        }
                    }
                }
            }

            // Volume pill
            Rectangle {
                height: 24; radius: 12
                color: Qt.rgba(1, 1, 1, 0.10)
                width: volText.implicitWidth + 16
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: volText
                    anchors.centerIn: parent
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
                        stdout: SplitParser { onRead: (l) => volText.val = l.trim() }
                    }
                }
            }

            // CPU temp pill
            Rectangle {
                height: 24; radius: 12
                color: Qt.rgba(1, 1, 1, 0.10)
                width: tempText.implicitWidth + 16
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: tempText
                    anchors.centerIn: parent
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
                        stdout: SplitParser { onRead: (l) => tempText.deg = parseInt(l) || 0 }
                    }
                }
            }

            // Battery pill
            Rectangle {
                height: 24; radius: 12
                color: batText.pct < 15 ? Qt.darker(Palette.color9, 2.0) : Qt.rgba(1, 1, 1, 0.10)
                width: batText.implicitWidth + 16
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: batText
                    anchors.centerIn: parent
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
                                batText.pct    = parseInt(p[0]) || 0
                                batText.status = p[1] || "Unknown"
                            }
                        }
                    }
                }
            }

            // Clock pill
            Rectangle {
                height: 24; radius: 12
                color: Qt.rgba(1, 1, 1, 0.10)
                width: clockText.implicitWidth + 16
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    color: Palette.fg
                    font { family: Palette.font; pixelSize: 12 }
                    text: Qt.formatDateTime(new Date(), "hh:mm")
                    Timer {
                        interval: 30000; repeat: true; triggeredOnStart: true; running: true
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm")
                    }
                }
            }
        }
    }
}
