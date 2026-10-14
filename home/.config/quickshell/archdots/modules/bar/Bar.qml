import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// One floating row of islands along the top of a screen, like fabric's bar.py:
// workspaces and the window title on the left, media, meters and the clock on
// the right.
PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 6
        left: 14
        right: 14
    }
    implicitHeight: 32
    color: "transparent"
    WlrLayershell.namespace: "archdots-bar"

    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Workspaces {}
        ActiveTitle {}
    }

    RowLayout {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        MediaIsland {}
        Resources {}
        Clock {}
    }
}
