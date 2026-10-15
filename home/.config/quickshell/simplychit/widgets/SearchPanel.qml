import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

// A search panel: a card hanging from the top of the screen with a
// search row, a body (default property) and a footer of key hints. Slides
// and fades in. The search field keeps the keyboard; arrow keys and Enter are
// passed on as signals for the body to act on.
Panel {
    id: root

    default property alias body: bodyHolder.data
    property alias query: input.text
    property string placeholder: ""
    property string glyph: ""
    property var hints: []
    property int panelWidth: 540

    signal moveUp
    signal moveDown
    signal moveLeft
    signal moveRight
    signal accepted(int modifiers)
    // Any other key, before the search field sees it. Set event.accepted to
    // keep it.
    signal otherKey(var event)

    anchors.top: true
    // level with the control centre and the other panels under the bar
    margins.top: 46
    implicitWidth: panelWidth
    implicitHeight: card.implicitHeight + 40

    onOpened: {
        input.text = "";
        input.forceActiveFocus();
    }

    Rectangle {
        id: card

        width: root.panelWidth
        implicitHeight: column.implicitHeight + 14
        y: (1 - root.reveal) * -18
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
                margins: 14
            }
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 13
                color: Colours.alpha(Colours.accent, 0.10)
                border.width: 1
                border.color: Colours.alpha(Colours.accent, 0.25)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    BarText {
                        text: root.glyph
                        px: 16
                        color: Colours.accent
                        opacity: 0.85
                    }

                    TextInput {
                        id: input

                        Layout.fillWidth: true
                        color: Colours.foreground
                        selectionColor: Colours.alpha(Colours.accent, 0.4)
                        font.family: "JetBrainsMono NF"
                        font.pointSize: 13.5 * 0.75
                        clip: true

                        Keys.onPressed: event => {
                            root.otherKey(event);
                            if (event.accepted)
                                return;
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.close();
                                break;
                            case Qt.Key_Up:
                                root.moveUp();
                                break;
                            case Qt.Key_Down:
                            case Qt.Key_Tab:
                                root.moveDown();
                                break;
                            case Qt.Key_Backtab:
                                root.moveUp();
                                break;
                            case Qt.Key_Left:
                                if (input.text !== "")
                                    return;
                                root.moveLeft();
                                break;
                            case Qt.Key_Right:
                                if (input.text !== "")
                                    return;
                                root.moveRight();
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                root.accepted(event.modifiers);
                                break;
                            default:
                                return;
                            }
                            event.accepted = true;
                        }

                        BarText {
                            anchors.fill: parent
                            text: root.placeholder
                            px: 13.5
                            color: Colours.hint
                            visible: input.text === ""
                        }
                    }
                }
            }

            Item {
                id: bodyHolder

                Layout.fillWidth: true
                implicitHeight: childrenRect.height
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colours.alpha(Colours.accent, 0.20)
                visible: root.hints.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.bottomMargin: 2
                spacing: 20
                visible: root.hints.length > 0

                Repeater {
                    model: root.hints

                    BarText {
                        required property string modelData

                        text: modelData
                        px: 10.5
                        color: Colours.hint
                    }
                }
            }
        }
    }
}
