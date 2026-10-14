import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// The heading of a settings page.
ColumnLayout {
    property string title: ""
    property string description: ""

    Layout.fillWidth: true
    spacing: 4

    BarText {
        text: parent.title
        px: 22
        font.weight: Font.Medium
    }
    BarText {
        Layout.fillWidth: true
        visible: text !== ""
        text: parent.description
        color: Colours.subtext
        wrapMode: Text.Wrap
    }
}
