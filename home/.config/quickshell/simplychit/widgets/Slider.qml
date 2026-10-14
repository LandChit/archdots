import QtQuick
import qs.config

// A level slider: drag or click to set, scroll to nudge. `value` is 0..1 and
// follows the outside value until the user moves it; `moved(v)` reports the
// user's changes only, so a level pushed in from elsewhere never echoes back.
Item {
    id: root

    property real value: 0
    property real step: 0.05
    signal moved(real value)

    implicitHeight: 22

    function setFrom(x: real): void {
        const v = Math.max(0, Math.min(1, x / track.width));
        moved(v);
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Colours.alpha(Colours.accent, 0.16)

        Rectangle {
            width: parent.width * Math.min(1, Math.max(0, root.value))
            height: parent.height
            radius: 3
            color: Colours.accentBright
        }
    }

    Rectangle {
        x: track.width * Math.min(1, Math.max(0, root.value)) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: Colours.highlight
        border.width: 2
        border.color: Colours.accentBright
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.setFrom(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                root.setFrom(mouse.x);
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + root.step * wheel.angleDelta.y / 120)))
    }
}
