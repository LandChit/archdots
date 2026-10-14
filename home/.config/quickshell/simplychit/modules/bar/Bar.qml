import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config

// One floating row of islands along the top of a screen:
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
        mediaChars: Config.bar.mediaChars,
        left: Config.bar.left,
        right: Config.bar.right
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
    WlrLayershell.namespace: "simplychit-bar"

    // bar.left / bar.right (per screen too): which islands, in this order
    readonly property var islands: ({
        workspaces: workspaces,
        special: special,
        title: title,
        media: media,
        resources: resources,
        clock: clock
    })

    Component {
        id: workspaces

        Workspaces {}
    }
    Component {
        id: special

        SpecialWorkspaces {
            monitorName: root.modelData.name
        }
    }
    Component {
        id: title

        ActiveTitle {
            settings: root.settings
        }
    }
    Component {
        id: media

        MediaIsland {
            settings: root.settings
        }
    }
    Component {
        id: resources

        Resources {
            settings: root.settings
        }
    }
    Component {
        id: clock

        Clock {
            settings: root.settings
        }
    }

    component Side: RowLayout {
        property var names: []

        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: parent.names.filter(n => root.islands[n] !== undefined)

            Loader {
                required property string modelData

                sourceComponent: root.islands[modelData]
                visible: item !== null && item.wanted !== false
            }
        }
    }

    Side {
        anchors.left: parent.left
        names: root.settings.left
    }

    Side {
        anchors.right: parent.right
        names: root.settings.right
    }
}
