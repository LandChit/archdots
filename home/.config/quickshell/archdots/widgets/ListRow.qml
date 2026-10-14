import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

// fabric's app row: an icon tile, a title over a subtitle, and a trailing
// hint shown only on the keyboard-selected row. Use as a ListPanel delegate.
//
// `icon` is a theme icon name or path; `glyph` is a Nerd Font glyph used
// instead when there is no icon.
Rectangle {
    id: root

    required property int index
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property string glyph: ""
    property string hint: "open ↵"

    readonly property bool selected: ListView.isCurrentItem && ListView.view.showSelection

    width: ListView.view.width
    implicitHeight: 54
    radius: 12
    color: selected ? Colours.selection : area.containsMouse ? Colours.hover : "transparent"
    border.width: 1
    border.color: selected ? Colours.selectionBorder : "transparent"

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Rectangle {
            implicitWidth: 40
            implicitHeight: 40
            radius: 10
            color: Colours.alpha(Colours.accent, root.selected ? 0.25 : 0.12)

            // A plain Image with a fixed sourceSize: SVG icons are rendered at
            // 32px instead of at their native size first ("requested buffer
            // size is too big" otherwise).
            Image {
                anchors.centerIn: parent
                width: 32
                height: 32
                sourceSize: Qt.size(32, 32)
                source: root.icon === "" ? "" : Quickshell.iconPath(root.icon, "application-x-executable")
                visible: root.icon !== ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }

            BarText {
                anchors.centerIn: parent
                text: root.glyph
                px: 18
                // not the accent: on a dark wallpaper color4 is dark too, and a
                // glyph is all there is in the tile
                color: Colours.alpha(Colours.foreground, 0.85)
                visible: root.icon === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            BarText {
                Layout.fillWidth: true
                text: root.title
                px: 13.5
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            BarText {
                Layout.fillWidth: true
                text: root.subtitle
                px: 11
                color: Colours.subtext
                elide: Text.ElideRight
                visible: text !== ""
            }
        }

        Rectangle {
            implicitWidth: hintText.implicitWidth + 12
            implicitHeight: hintText.implicitHeight + 4
            radius: 5
            color: Colours.alpha(Colours.accent, 0.20)
            border.width: 1
            border.color: Colours.alpha(Colours.accent, 0.45)
            opacity: root.selected && root.hint !== "" ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            BarText {
                id: hintText

                anchors.centerIn: parent
                text: root.hint
                px: 10.5
                color: Colours.highlight
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.ListView.view.clickedRow(root.index)
    }
}
