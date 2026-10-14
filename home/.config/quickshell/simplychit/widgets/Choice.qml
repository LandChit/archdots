import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// Segmented buttons for a few options. `options` is [[value, label], ...].
RowLayout {
    id: root

    property var options: []
    property var value
    signal chosen(var value)

    spacing: 4

    Repeater {
        model: root.options

        Rectangle {
            required property var modelData
            readonly property bool active: root.value === modelData[0]

            implicitWidth: label.implicitWidth + 22
            implicitHeight: 28
            radius: 9
            color: active ? Colours.alpha(Colours.accentBright, 0.25) : area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.08)
            border.width: 1
            border.color: active ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.20)

            BarText {
                id: label

                anchors.centerIn: parent
                text: parent.modelData[1]
                px: 11.5
                color: parent.active ? Colours.foreground : Colours.subtext
            }
            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.chosen(parent.modelData[0])
            }
        }
    }
}
