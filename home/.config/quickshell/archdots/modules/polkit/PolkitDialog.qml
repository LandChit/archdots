import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs.config
import qs.widgets

// The polkit agent and its dialog (TODO 2), in the shell's theme instead of
// hyprpolkitagent's.
//
// Only one agent can serve a session, and whichever registers first wins.
// autorun.lua starts hyprpolkitagent as a fallback when this one has not
// registered (`ipc call polkit registered` answers), so a broken shell never
// leaves you with no way to authenticate.
Scope {
    id: root

    // the request on screen: the agent's, or a sample from `polkit preview`
    property var flow: agent.flow ?? preview
    property var preview: null
    readonly property bool shown: flow !== null && !(flow.isCompleted ?? false)

    PolkitAgent {
        id: agent
    }

    IpcHandler {
        target: "polkit"

        function registered(): bool {
            return agent.isRegistered;
        }
        // the dialog with a sample request, to see it without authenticating
        function preview(): void {
            root.preview = {
                message: "Authentication is needed to run `/usr/bin/true' as the super user",
                actionId: "org.freedesktop.policykit.exec",
                iconName: "dialog-password",
                inputPrompt: "Password: ",
                responseVisible: false,
                supplementaryMessage: "",
                supplementaryIsError: false,
                identities: [],
                submit: () => root.preview = null,
                cancelAuthenticationRequest: () => root.preview = null
            };
        }
    }

    PanelWindow {
        id: window

        screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
        visible: root.shown
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: Colours.scrim
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "archdots-polkit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (visible) {
                password.text = "";
                password.forceActiveFocus();
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 440
            implicitHeight: column.implicitHeight + 40
            radius: 20
            color: Colours.panel
            border.width: 1
            border.color: root.flow && root.flow.supplementaryIsError ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 0.6) : Colours.panelBorder

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

                    BarText {
                        text: "\u{f033e}"
                        px: 30
                        color: Colours.accentBright
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        BarText {
                            text: "Authentication required"
                            px: 15
                            font.weight: Font.Medium
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: root.flow ? root.flow.actionId : ""
                            px: 10.5
                            color: Colours.subtext
                            elide: Text.ElideRight
                        }
                    }
                }

                BarText {
                    Layout.fillWidth: true
                    text: root.flow ? root.flow.message : ""
                    wrapMode: Text.Wrap
                    color: Colours.alpha(Colours.foreground, 0.85)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 11
                    color: Colours.alpha(Colours.accent, 0.10)
                    border.width: 1
                    border.color: password.activeFocus ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.30)

                    TextInput {
                        id: password

                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        color: Colours.foreground
                        font.family: "JetBrainsMono NF"
                        font.pointSize: 13 * 0.75
                        Keys.onReturnPressed: root.flow.submit(text)
                        Keys.onEnterPressed: root.flow.submit(text)
                        Keys.onEscapePressed: root.flow.cancelAuthenticationRequest()

                        BarText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.flow ? (root.flow.inputPrompt || "Password").replace(/:\s*$/, "") : ""
                            color: Colours.hint
                            visible: password.text === ""
                        }
                    }
                }

                BarText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.flow ? root.flow.supplementaryMessage : ""
                    px: 11
                    wrapMode: Text.Wrap
                    color: root.flow && root.flow.supplementaryIsError ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1) : Colours.subtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: [["Cancel", false], ["Authenticate", true]]

                        Rectangle {
                            required property var modelData

                            implicitWidth: label.implicitWidth + 28
                            implicitHeight: 34
                            radius: 10
                            color: modelData[1] ? Colours.alpha(Colours.accentBright, area.containsMouse ? 0.35 : 0.25) : area.containsMouse ? Colours.hover : "transparent"
                            border.width: 1
                            border.color: modelData[1] ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.25)

                            BarText {
                                id: label

                                anchors.centerIn: parent
                                text: parent.modelData[0]
                            }

                            MouseArea {
                                id: area

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: parent.modelData[1] ? root.flow.submit(password.text) : root.flow.cancelAuthenticationRequest()
                            }
                        }
                    }
                }
            }
        }
    }
}
