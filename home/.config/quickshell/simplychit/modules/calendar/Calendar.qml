import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The month under the clock, opened by clicking the clock island. Always
// opens on today; ← → or the arrows page through months, Esc closes.
Panel {
    id: root

    name: "calendar"
    anchors.top: true
    anchors.right: true
    margins.top: 46
    margins.right: 14
    implicitWidth: 300
    implicitHeight: card.implicitHeight + 20

    property date today: new Date()
    property int month: today.getMonth()
    property int year: today.getFullYear()

    function page(delta: int): void {
        const d = new Date(year, month + delta, 1);
        month = d.getMonth();
        year = d.getFullYear();
    }

    onOpened: {
        today = new Date();
        month = today.getMonth();
        year = today.getFullYear();
        keys.forceActiveFocus();
    }

    Item {
        id: keys

        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.close();
            else if (event.key === Qt.Key_Left)
                root.page(-1);
            else if (event.key === Qt.Key_Right)
                root.page(1);
            else
                return;
            event.accepted = true;
        }
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
            spacing: 2

            BarText {
                text: Qt.formatDate(root.today, "dddd")
                px: 11
                color: Colours.subtext
            }
            BarText {
                text: Qt.formatDate(root.today, "d MMMM yyyy")
                px: 17
                font.weight: Font.Medium
                Layout.bottomMargin: 10
            }

            RowLayout {
                Layout.fillWidth: true

                BarText {
                    Layout.fillWidth: true
                    text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
                    font.weight: Font.Medium
                }

                Repeater {
                    model: [["\u{f0141}", -1], ["\u{f0142}", 1]]

                    Hot {
                        required property var modelData

                        onClicked: root.page(modelData[1])

                        BarText {
                            text: parent.parent.modelData[0]
                            px: 15
                        }
                    }
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                locale: grid.locale
                delegate: BarText {
                    required property string shortName

                    text: shortName.slice(0, 2)
                    px: 10.5
                    color: Colours.subtext
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MonthGrid {
                id: grid

                Layout.fillWidth: true
                // six rows of 30, always: MonthGrid has no implicit height of
                // its own inside a layout, and a fixed six rows stops the card
                // changing size between months
                Layout.preferredHeight: 6 * 30 + 5 * spacing
                month: root.month
                year: root.year
                spacing: 2

                delegate: Rectangle {
                    required property var model

                    readonly property bool isToday: model.today
                    readonly property bool inMonth: model.month === grid.month

                    implicitHeight: 30
                    radius: 8
                    color: isToday ? Colours.alpha(Colours.accentBright, 0.30) : "transparent"
                    border.width: isToday ? 1 : 0
                    border.color: Colours.selectionBorder

                    BarText {
                        anchors.centerIn: parent
                        text: parent.model.day
                        px: 12
                        color: parent.isToday ? Colours.highlight
                             : parent.inMonth ? Colours.foreground
                             : Colours.alpha(Colours.foreground, 0.25)
                    }
                }
            }
        }
    }
}
