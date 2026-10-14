import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// Full-screen scrim with a card per session action (services/Power.qml).
// Arrows move, Enter runs the selected card, Esc or a click on the scrim
// cancels. Nothing is selected until an arrow key is pressed, so a stray
// Enter does nothing.
Panel {
    id: root

    name: "powermenu"
    layer: WlrLayer.Overlay
    closeOnOutsideClick: false
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property int selected: -1

    onOpened: {
        selected = -1;
        keys.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.scrim
        opacity: root.reveal

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const count = Power.actions.length;
            switch (event.key) {
            case Qt.Key_Escape:
                root.close();
                break;
            case Qt.Key_Left:
            case Qt.Key_Up:
            case Qt.Key_Backtab:
                root.selected = root.selected <= 0 ? count - 1 : root.selected - 1;
                break;
            case Qt.Key_Right:
            case Qt.Key_Down:
            case Qt.Key_Tab:
                root.selected = (root.selected + 1) % count;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root.selected >= 0) {
                    Power.run(Power.actions[root.selected].id);
                    root.close();
                }
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 22
        opacity: root.reveal
        scale: 0.96 + 0.04 * root.reveal

        RowLayout {
            spacing: 16

            Repeater {
                model: Power.actions

                delegate: Rectangle {
                    id: card

                    required property var modelData
                    required property int index
                    readonly property bool active: root.selected === index

                    implicitWidth: 148
                    implicitHeight: 148
                    radius: 20
                    color: active ? Colours.alpha(Colours.accent, 0.18)
                         : area.containsMouse ? Colours.alpha(Colours.accent, 0.16)
                         : Colours.panel
                    border.width: 1
                    border.color: active || area.containsMouse ? Colours.alpha(Colours.accent, 0.50) : Colours.panelBorder

                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }

                    // fabric's glowpulse: an accent halo breathing round the selection
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 2 * glow
                        height: parent.height + 2 * glow
                        radius: parent.radius + glow
                        color: "transparent"
                        border.width: glow
                        border.color: Colours.alpha(Colours.accent, 0.10)
                        visible: card.active
                        z: -1

                        property real glow: 6

                        SequentialAnimation on glow {
                            running: card.active
                            loops: Animation.Infinite
                            NumberAnimation { from: 4; to: 12; duration: 1300; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 12; to: 4; duration: 1300; easing.type: Easing.InOutSine }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10

                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: card.modelData.glyph
                            px: 38
                            color: card.active ? Colours.accent : Colours.alpha(Colours.foreground, 0.60)
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: card.modelData.label
                            color: card.active ? Colours.accent : Colours.foreground
                        }
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Power.run(card.modelData.id);
                            root.close();
                        }
                    }
                }
            }
        }

        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: "←→ navigate · ↵ confirm · esc cancel"
            px: 11
            color: Colours.hint
        }
    }
}
