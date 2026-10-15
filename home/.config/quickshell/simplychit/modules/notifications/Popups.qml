import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

// The stack of live notifications, top right under the bar, on
// the focused screen. Each card leaves after its timeout (5 s unless the app
// asks otherwise; critical ones stay until closed); hovering a card holds it.
PanelWindow {
    id: root

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
    // hidden while the history is open: it lists the same cards
    visible: Notifs.popups.length > 0 && Panels.current !== "notifications"
    anchors.top: true
    anchors.right: true
    margins.top: 46
    margins.right: 14
    implicitWidth: 370
    implicitHeight: stack.implicitHeight + 10
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "simplychit-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: stack

        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups

            NotificationCard {
                id: card

                required property var modelData

                Layout.fillWidth: true
                entry: modelData
                onClosed: Notifs.dismissPopup(modelData.key)

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }

                HoverHandler {
                    id: hover
                }

                Timer {
                    interval: card.modelData.timeout
                    running: card.modelData.timeout > 0 && !hover.hovered
                    // a popup leaving by itself stays in the history; only
                    // the close button dismisses the notification itself
                    onTriggered: {
                        card.modelData.closeOnDismiss = false;
                        Notifs.dismissPopup(card.modelData.key);
                    }
                }
            }
        }
    }
}
