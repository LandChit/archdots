import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.config
import qs.widgets

// Every normal workspace that exists, in order. Special workspaces (negative
// ids) are left out; indicators for them are TODO C7.
Island {
    id: root

    padding: 6
    spacing: 4

    Repeater {
        model: Hyprland.workspaces.values.filter(ws => ws.id > 0).sort((a, b) => a.id - b.id)

        delegate: Rectangle {
            id: button

            required property HyprlandWorkspace modelData
            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData.id
            readonly property bool occupied: modelData.toplevels.values.length > 0

            implicitWidth: 22
            implicitHeight: 22
            radius: 7
            color: focused ? Colours.alpha(Colours.accent, 0.30)
                 : occupied ? Colours.alpha(Colours.accent, 0.12)
                 : "transparent"
            border.width: 1
            border.color: focused ? Colours.alpha(Colours.accent, 0.55) : "transparent"

            Behavior on color {
                ColorAnimation { duration: 140 }
            }

            BarText {
                anchors.centerIn: parent
                text: button.modelData.name
                px: 12
                color: button.focused ? Colours.highlight : Colours.alpha(Colours.foreground, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: button.modelData.activate()
            }
        }
    }
}
