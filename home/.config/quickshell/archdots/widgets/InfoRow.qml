import QtQuick
import QtQuick.Layouts
import qs.config

// A list row for the control centre's pages: glyph, title over subtitle,
// optional trailing text; tinted when `active`.
Rectangle {
    id: root

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property bool active: false
    default property alias extra: extraHolder.data
    signal clicked

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 14
    radius: 11
    color: active ? Colours.alpha(Colours.accentBright, 0.14) : area.containsMouse ? Colours.hover : "transparent"
    border.width: 1
    border.color: active ? Colours.alpha(Colours.accentBright, 0.40) : "transparent"

    ColumnLayout {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            BarText {
                text: root.glyph
                px: 16
                color: root.active ? Colours.highlight : Colours.alpha(Colours.foreground, 0.75)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                BarText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                }
                BarText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    px: 10.5
                    color: Colours.subtext
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            BarText {
                text: root.trailing
                px: 10.5
                color: Colours.subtext
                visible: text !== ""
            }
        }

        Item {
            id: extraHolder

            Layout.fillWidth: true
            implicitHeight: childrenRect.height
            visible: children.length > 0 && childrenRect.height > 0
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        z: -1
    }
}
