import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.widgets

// The shell's own toasts (Notifs.toast: Caps Lock, charger, DND, ...): small
// pills at the bottom middle of the focused screen, under the OSD, newest at
// the bottom. Each leaves after its timeout; hovering holds it, a click
// dismisses it.
PanelWindow {
    id: root

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Screens.primary
    visible: Notifs.toasts.length > 0
    anchors.bottom: true
    margins.bottom: 34
    implicitWidth: 520
    implicitHeight: stack.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // only the pills take clicks, not the empty sides of the window
    mask: Region {
        item: stack
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "simplychit-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: stack

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        Repeater {
            model: Notifs.toasts

            Rectangle {
                id: pill

                required property var modelData

                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.implicitWidth
                implicitWidth: row.implicitWidth + 36
                implicitHeight: 40
                radius: 20
                color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), 0.94)
                border.width: 1
                border.color: Colours.panelBorder

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }

                RowLayout {
                    id: row

                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, pill.width - 36)
                    spacing: 10

                    BarText {
                        text: pill.modelData.glyph ?? ""
                        px: 17
                        color: Colours.accentBright
                        visible: text !== ""
                    }
                    BarText {
                        text: pill.modelData.summary
                        font.weight: Font.Medium
                    }
                    BarText {
                        Layout.fillWidth: true
                        text: pill.modelData.body
                        visible: text !== ""
                        color: Colours.subtext
                        elide: Text.ElideRight
                    }
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    onTapped: Notifs.dismissToast(pill.modelData.key)
                }

                Timer {
                    interval: pill.modelData.timeout
                    running: !hover.hovered
                    onTriggered: Notifs.dismissToast(pill.modelData.key)
                }
            }
        }
    }
}
