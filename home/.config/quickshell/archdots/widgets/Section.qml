import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// A titled group of settings rows on a settings page.
ColumnLayout {
    id: root

    property string title: ""
    property string description: ""
    default property alias rows: body.data

    Layout.fillWidth: true
    spacing: 6

    BarText {
        text: root.title
        px: 13
        font.weight: Font.Medium
        color: Colours.accentBright
        Layout.topMargin: 8
    }
    BarText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.description
        px: 11
        color: Colours.subtext
        wrapMode: Text.Wrap
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 8
        radius: 14
        color: Colours.alpha(Colours.accent, 0.06)
        border.width: 1
        border.color: Colours.alpha(Colours.accent, 0.16)

        ColumnLayout {
            id: body

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 4
            }
            spacing: 0
        }
    }
}
