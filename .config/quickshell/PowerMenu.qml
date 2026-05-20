import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./"

FloatingWindow {
    id: root
    visible: false

    WlrLayerShell.layer: WlrLayerShell.Layer.Overlay
    WlrLayerShell.keyboardFocus: WlrLayerShell.KeyboardFocus.OnDemand
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
                        radius: Palette.radius
                        color: hov ? Palette.surface : "transparent"
                        property bool hov: false

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                color: parent.parent.hov ? Palette.accent : Palette.fg
                                font { family: Palette.font; pixelSize: 24 }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: Palette.muted
                                font { family: Palette.font; pixelSize: 10 }
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
