import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// "Add this to games?" for a window that went into the games scratchpad, or
// opened looking like a game, while in no list (services/Games.qml). On the
// primary screen, where the games scratchpad shows. Enter adds it, Escape
// answers No, which is remembered (Settings > Games changes it back).
Scope {
    id: root

    readonly property var question: Games.asking

    PanelWindow {
        id: window

        screen: Screens.primary
        visible: root.question !== null
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: Colours.scrim
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "simplychit-games"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (visible)
                keys.forceActiveFocus();
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true
            Keys.onReturnPressed: Games.answerYes()
            Keys.onEnterPressed: Games.answerYes()
            Keys.onEscapePressed: Games.answerNo()
        }

        Rectangle {
            anchors.centerIn: parent
            width: 440
            implicitHeight: column.implicitHeight + 40
            radius: 20
            color: Colours.panel
            border.width: 1
            border.color: Colours.panelBorder

            ColumnLayout {
                id: column

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 20
                }
                spacing: 12

                RowLayout {
                    spacing: 12

                    Rectangle {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: 12
                        color: Colours.alpha(Colours.accent, 0.12)

                        Image {
                            anchors.centerIn: parent
                            width: 34
                            height: 34
                            sourceSize: Qt.size(34, 34)
                            source: root.question && root.question.icon !== "" ? Quickshell.iconPath(root.question.icon, "application-x-executable") : ""
                            visible: root.question !== null && root.question.icon !== ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }
                        BarText {
                            anchors.centerIn: parent
                            text: "\u{f0297}"
                            px: 24
                            color: Colours.accentBright
                            visible: !root.question || root.question.icon === ""
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        BarText {
                            Layout.fillWidth: true
                            text: root.question ? root.question.name : ""
                            px: 15
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: root.question ? root.question.cls : ""
                            px: 10.5
                            color: Colours.subtext
                            elide: Text.ElideRight
                        }
                    }
                }

                BarText {
                    Layout.fillWidth: true
                    text: root.question && root.question.detected ? "This looks like a game. Open it in Games, fullscreen, from now on?" : "Open it in Games, fullscreen, by itself from now on?"
                    wrapMode: Text.Wrap
                    color: Colours.alpha(Colours.foreground, 0.85)
                }

                BarText {
                    Layout.fillWidth: true
                    text: "No is remembered for this app; Settings › Games changes either answer."
                    px: 10.5
                    wrapMode: Text.Wrap
                    color: Colours.hint
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "No, don't ask again"
                        onClicked: Games.answerNo()
                    }
                    Button {
                        primary: true
                        text: "Add to games"
                        onClicked: Games.answerYes()
                    }
                }
            }
        }
    }
}
