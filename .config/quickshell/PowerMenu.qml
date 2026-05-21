import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./"

PanelWindow {
    id: root
    visible: false
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: root.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 396; height: 100
            color: Palette.bg
            radius: Palette.radius
            border { color: Palette.border; width: 1 }
            MouseArea { anchors.fill: parent }

            RowLayout {
                anchors.centerIn: parent
                spacing: 12

                Repeater {
                    model: [
                        { icon: "󰤄", label: "Lock",     cmd: "loginctl lock-session" },
                        { icon: "󰒲", label: "Suspend",  cmd: "systemctl suspend" },
                        { icon: "",  label: "Reboot",   cmd: "systemctl reboot" },
                        { icon: "󰐥", label: "Shutdown", cmd: "systemctl poweroff" },
                        { icon: "󰗼", label: "Logout",   cmd: "hyprctl dispatch exit" },
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: 60; height: 72
                        radius: Palette?.radius ?? 8
                        color: hov ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        property bool hov: false

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                color: parent.parent.hov ? (Palette?.accent ?? "#f38ba8") : (Palette?.fg ?? "#cdd6f4")
                                font { family: Palette?.font ?? "monospace"; pixelSize: 24 }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: Palette?.muted ?? "#888888"
                                font { family: Palette?.font ?? "monospace"; pixelSize: 10 }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: parent.hov = true
                            onExited:  parent.hov = false
                            onClicked: {
                                root.visible = false
                                actionProc.command = ["bash", "-c", parent.modelData.cmd]
                                actionProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }

    Process { id: actionProc; command: [] }
}
