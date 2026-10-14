import QtQuick
import qs.config

// A clickable meter: tints on hover, shows a hand cursor, passes clicks and
// scrolls on. Wrap the meter's content in it.
Rectangle {
    id: root

    default property alias content: inner.data
    signal clicked(var mouse)
    signal scrolled(real steps)

    implicitWidth: inner.childrenRect.width + 10
    implicitHeight: 24
    radius: 9
    color: area.containsMouse ? Colours.alpha(Colours.accent, 0.14) : "transparent"

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Item {
        id: inner

        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => root.clicked(mouse)
        // angleDelta is 120 per notch; a touchpad sends fractions of that.
        onWheel: wheel => root.scrolled(wheel.angleDelta.y / 120)
    }
}
