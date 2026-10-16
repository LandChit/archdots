import QtQuick
import QtQuick.Layouts
import qs.config

// A control-centre switch: glyph over label, accent-filled when on.
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    // a small third line under the label, e.g. who is keeping it on
    property string note: ""
    property bool active: false
    signal clicked

    Layout.fillWidth: true
    implicitHeight: 62
    radius: 14
    color: active ? Colours.alpha(Colours.accentBright, 0.22) : area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.08)
    border.width: 1
    border.color: active ? Colours.alpha(Colours.accentBright, 0.50) : Colours.alpha(Colours.accent, 0.18)

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 3

        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: root.glyph
            px: 18
            color: root.active ? Colours.highlight : Colours.alpha(Colours.foreground, 0.75)
        }
        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            px: 10.5
            color: root.active ? Colours.foreground : Colours.subtext
        }
        BarText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width - 12
            visible: root.note !== ""
            text: root.note
            textFormat: Text.PlainText
            elide: Text.ElideRight
            px: 9
            color: Colours.hint
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
