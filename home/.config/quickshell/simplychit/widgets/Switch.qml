import QtQuick
import qs.config

// On/off. `checked` follows the outside value; `toggled(v)` reports clicks.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    width: 44
    height: 24
    radius: 12
    color: checked ? Colours.alpha(Colours.accentBright, 0.55) : Colours.alpha(Colours.foreground, 0.12)
    border.width: 1
    border.color: checked ? Colours.selectionBorder : Colours.alpha(Colours.foreground, 0.18)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Rectangle {
        x: root.checked ? root.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 9
        color: root.checked ? Colours.highlight : Colours.alpha(Colours.foreground, 0.7)

        Behavior on x {
            NumberAnimation { duration: 120 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
