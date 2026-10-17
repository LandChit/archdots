import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// A drop-down for longer lists. `options` is [[value, label], ...]. The open
// list is moved onto the window's root item: `z` only orders siblings, so in
// place the rows below would cover it and take its clicks. A click or scroll
// outside it closes it.
Item {
    id: root

    property var options: []
    property var value
    property int fieldWidth: 220
    property bool open: false
    signal chosen(var value)

    readonly property string currentLabel: (options.find(o => o[0] === value) ?? [value, String(value ?? "")])[1]

    implicitWidth: fieldWidth
    implicitHeight: 30

    onOpenChanged: {
        if (!open)
            return;
        const top = root.mapToItem(overlay, 0, 0);
        const below = top.y + root.height + 4;
        menu.x = top.x;
        menu.y = below + menu.height <= overlay.height ? below : Math.max(0, top.y - 4 - menu.height);
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.08)
        border.width: 1
        border.color: root.open ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.22)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8

            BarText {
                Layout.fillWidth: true
                text: root.currentLabel
                elide: Text.ElideRight
            }
            BarText {
                text: root.open ? "\u{f0143}" : "\u{f0140}"
                color: Colours.subtext
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    Item {
        id: overlay

        parent: root.Window.window ? root.Window.window.contentItem : root
        anchors.fill: parent
        visible: root.open
        z: 1000

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
            onWheel: root.open = false
        }

        Rectangle {
            id: menu

            width: root.width
            height: Math.min(260, list.contentHeight + 8)
            radius: 10
            color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.18), 0.98)
            border.width: 1
            border.color: Colours.selectionBorder

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: 4
                clip: true
                model: root.options
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData

                    width: ListView.view.width
                    height: 28
                    radius: 7
                    color: modelData[0] === root.value ? Colours.selection : itemArea.containsMouse ? Colours.hover : "transparent"

                    BarText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        width: parent.width - 16
                        text: parent.modelData[1]
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: itemArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.open = false;
                            root.chosen(parent.modelData[0]);
                        }
                    }
                }
            }
        }
    }
}
