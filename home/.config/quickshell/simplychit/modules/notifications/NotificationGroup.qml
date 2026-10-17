import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.widgets

// One app's notifications in the history (Notifs.historyGroups). A single one
// is a plain card. Two or more get a header (app, count, expand, clear) and
// show the newest card with the rest stacked under it, or every card when
// expanded.
ColumnLayout {
    id: root

    required property var group
    property bool expanded: false
    signal toggled

    readonly property bool stacked: group.items.length > 1

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 2
        visible: root.stacked
        spacing: 6

        Hot {
            onClicked: root.toggled()

            RowLayout {
                spacing: 6

                BarText {
                    text: root.expanded ? "\u{f0140}" : "\u{f0142}"
                    px: 12
                    color: Colours.subtext
                }
                BarText {
                    text: root.group.app.toUpperCase()
                    px: 9.5
                    color: Colours.subtext
                    font.letterSpacing: 0.6
                }
                Rectangle {
                    implicitWidth: count.implicitWidth + 10
                    implicitHeight: 16
                    radius: 8
                    color: Colours.alpha(Colours.accent, 0.22)

                    BarText {
                        id: count

                        anchors.centerIn: parent
                        text: root.group.items.length
                        px: 9.5
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
        }
        Hot {
            onClicked: Notifs.removeGroup(root.group.app)

            BarText {
                text: "Clear"
                px: 10.5
                color: Colours.subtext
            }
        }
    }

    Repeater {
        model: root.expanded || !root.stacked ? root.group.items : root.group.items.slice(0, 1)

        NotificationCard {
            required property var modelData

            Layout.fillWidth: true
            entry: modelData
            inHistory: true
            onClosed: Notifs.removeFromHistory(modelData.key)
        }
    }

    // the edges of the cards under the newest one, while collapsed; a click
    // opens the group
    Item {
        Layout.fillWidth: true
        Layout.topMargin: -6
        implicitHeight: Math.min(root.group.items.length - 1, 2) * 5
        visible: root.stacked && !root.expanded

        Repeater {
            model: Math.min(root.group.items.length - 1, 2)

            Rectangle {
                required property int index

                x: 10 * (index + 1)
                y: index * 5 - 4
                z: -index
                width: parent.width - 20 * (index + 1)
                height: 9
                bottomLeftRadius: 8
                bottomRightRadius: 8
                color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), 0.80 - index * 0.2)
                border.width: 1
                border.color: Colours.panelBorder
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -2
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }
}
