import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config

// One floating row of islands along the top of a screen, like fabric's bar.py:
// workspaces and the window title on the left, media, meters and the clock on
// the right.
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Config.bar with this screen's overrides from bar.monitors on top
    readonly property var settings: Object.assign({}, {
        showMedia: Config.bar.showMedia,
        showCpu: Config.bar.showCpu,
        showBattery: Config.bar.showBattery,
        clockFormat: Config.bar.clockFormat,
        emptyTitle: Config.bar.emptyTitle,
        titleChars: Config.bar.titleChars,
        mediaChars: Config.bar.mediaChars
    }, Config.bar.monitors[modelData.name] ?? {})

    screen: modelData

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
        SpecialWorkspaces {
            monitorName: root.modelData.name
        }
        ActiveTitle {
            settings: root.settings
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        MediaIsland {
            settings: root.settings
        }
        Resources {
            settings: root.settings
        }
        Clock {
            settings: root.settings
        }
    }
}
