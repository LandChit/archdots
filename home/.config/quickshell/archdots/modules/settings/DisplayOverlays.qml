import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// On every screen: the "keep these settings?" countdown after a display
// change (on every screen, since the one the settings window was on may be
// the one that went dark), and the Identify labels.
Scope {
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData

            PanelWindow {
                screen: perScreen.modelData
                visible: Displays.confirming
                implicitWidth: 460
                implicitHeight: 150
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "archdots-displays"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: 18
                    color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), 0.96)
                    border.width: 1
                    border.color: Colours.selectionBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10

                        BarText {
                            text: "Keep these display settings?"
                            px: 15
                            font.weight: Font.Medium
                        }
                        BarText {
                            text: "Going back to the previous ones in " + Displays.countdown + " s."
                            color: Colours.subtext
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 8

                            Button {
                                text: "Revert"
                                onClicked: Displays.revert()
                            }
                            Button {
                                primary: true
                                text: "Keep"
                                onClicked: Displays.keep()
                            }
                        }
                    }
                }
            }

            PanelWindow {
                screen: perScreen.modelData
                visible: Displays.identifying
                implicitWidth: 360
                implicitHeight: 160
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "archdots-identify"

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.30), 0.94)
                    border.width: 2
                    border.color: Colours.selectionBorder

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: perScreen.modelData.name
                            px: 40
                            font.weight: Font.Medium
                        }
                        BarText {
                            Layout.alignment: Qt.AlignHCenter
                            text: perScreen.modelData.model
                            color: Colours.subtext
                        }
                    }
                }
            }
        }
    }
}
