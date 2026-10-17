import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// Which apps are using the microphone, the camera and the screen
// (services/Privacy.qml), opened from the bar's privacy indicator. Closes by
// itself when nothing is recording any more.
Panel {
    id: root

    name: "privacy"
    anchors.top: true
    anchors.right: true
    margins.top: 46
    margins.right: 14
    implicitWidth: 300
    implicitHeight: card.implicitHeight + 20

    onOpened: keys.forceActiveFocus()

    Connections {
        target: Privacy

        function onAnyChanged(): void {
            if (!Privacy.any)
                root.close();
        }
    }

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
            spacing: 12

            BarText {
                text: "In use"
                px: 15
                font.weight: Font.Medium
            }

            Repeater {
                model: [["\u{f0379}", "Screen", Privacy.screen], ["\u{f0100}", "Camera", Privacy.camera], ["\u{f036c}", "Microphone", Privacy.mic]].filter(k => k[2].length > 0)

                RowLayout {
                    id: row

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: 9
                        color: Colours.alpha(Colours.alert, 0.18)

                        BarText {
                            anchors.centerIn: parent
                            text: row.modelData[0]
                            px: 14
                            color: Colours.alert
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        BarText {
                            text: row.modelData[1].toUpperCase()
                            px: 9.5
                            color: Colours.subtext
                            font.letterSpacing: 0.6
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: row.modelData[2].join(", ")
                            px: 12.5
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
