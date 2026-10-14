import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The notification history (the last 50), newest first, with Clear and the
// DND switch. Opened with SUPER+N.
Panel {
    id: root

    name: "notifications"
    anchors.top: true
    anchors.right: true
    margins.top: 46
    margins.right: 14
    implicitWidth: 400
    implicitHeight: card.implicitHeight + 20

    onOpened: keys.forceActiveFocus()

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: root.close()
    }

    Rectangle {
        id: card

        width: root.implicitWidth
        implicitHeight: column.implicitHeight + 32
        y: (1 - root.reveal) * -10
        opacity: root.reveal
        radius: 18
        color: Colours.panel
        border.width: 1
        border.color: Colours.panelBorder

        ColumnLayout {
            id: column

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                BarText {
                    Layout.fillWidth: true
                    text: "Notifications"
                    px: 15
                    font.weight: Font.Medium
                }
                Hot {
                    onClicked: Notifs.dnd = !Notifs.dnd

                    BarText {
                        text: (Notifs.dnd ? "\u{f009b} DND on" : "\u{f009a} Alerts on")
                        px: 11
                        color: Notifs.dnd ? Colours.accentBright : Colours.subtext
                    }
                }
                Hot {
                    visible: Notifs.history.length > 0
                    onClicked: Notifs.clearHistory()

                    BarText {
                        text: "Clear"
                        px: 11
                        color: Colours.subtext
                    }
                }
            }

            BarText {
                visible: Notifs.history.length === 0
                text: "Nothing yet"
                color: Colours.subtext
                Layout.margins: 10
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(520, list.implicitHeight)
                visible: Notifs.history.length > 0
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: list

                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Notifs.history

                        NotificationCard {
                            required property var modelData

                            Layout.fillWidth: true
                            entry: modelData
                            inHistory: true
                            onClosed: Notifs.removeFromHistory(modelData.key)
                        }
                    }
                }
            }
        }
    }
}
