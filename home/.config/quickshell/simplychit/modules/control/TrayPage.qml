import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.config
import qs.widgets

// Tray icons (they live here, not in the bar). Click to activate,
// right-click for the app's menu.
Flow {
    id: root

    property var window: null
    // a tray menu is its own popup surface: while one is open the control
    // centre must not take a click there as a click outside and close (the
    // menu would go with it)
    // Raised before the menu opens, since the popup can take focus before
    // `opened` arrives; reset when the control centre closes, so a menu that
    // never opened cannot leave it stuck.
    property int menusOpen: 0
    readonly property bool menuOpen: menusOpen > 0

    Connections {
        target: root.window

        function onShownChanged(): void {
            if (!root.window.shown)
                root.menusOpen = 0;
        }
    }

    spacing: 6

    BarText {
        visible: SystemTray.items.values.length === 0
        text: "No tray icons"
        color: Colours.subtext
        padding: 8
    }

    Repeater {
        model: SystemTray.items.values

        Rectangle {
            id: icon

            required property SystemTrayItem modelData

            width: 40
            height: 40
            radius: 10
            color: area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.08)

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize: Qt.size(40, 40)
                source: icon.modelData.icon
                asynchronous: true
            }

            QsMenuAnchor {
                id: menu

                menu: icon.modelData.menu
                anchor.item: icon
                anchor.edges: Edges.Bottom
                onClosed: root.menusOpen = Math.max(0, root.menusOpen - 1)
            }

            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton || icon.modelData.onlyMenu) {
                        if (icon.modelData.hasMenu) {
                            root.menusOpen++;
                            menu.open();
                        }
                    } else {
                        icon.modelData.activate();
                    }
                }
            }
        }
    }
}
