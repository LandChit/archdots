import QtQuick
import QtQuick.Layouts
import qs.config

// One rounded bar island: 32px tall, the accent-mixed
// surface, a faint accent border. Children are laid out in a row.
Rectangle {
    id: root

    default property alias content: row.data
    property int padding: 11
    property alias spacing: row.spacing

    implicitHeight: 32
    implicitWidth: row.implicitWidth + padding * 2
    radius: 11
    color: Colours.island
    border.width: 1
    border.color: Colours.islandBorder

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: 0
    }
}
