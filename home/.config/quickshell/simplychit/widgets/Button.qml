import QtQuick
import qs.config
import qs.widgets

// A text button; `primary` fills it with the accent.
Rectangle {
    id: root

    property string text: ""
    property bool primary: false
    property bool enabled: true
    signal clicked

    implicitWidth: label.implicitWidth + 26
    implicitHeight: 30
    radius: 9
    opacity: enabled ? 1 : 0.45
    color: primary ? Colours.alpha(Colours.accentBright, area.containsMouse ? 0.38 : 0.26) : area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.10)
    border.width: 1
    border.color: primary ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.24)

    BarText {
        id: label

        anchors.centerIn: parent
        text: root.text
        px: 11.5
    }
    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
