import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// One floating row of islands along the top of a screen, in three sections:
// left, centre and right. Which widgets, in what order, is the default layout
// (bar.left / bar.center / bar.right) or this screen's own (bar.monitors);
// services/BarLayout.qml works that out.
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
    }, BarLayout.overrideFor(modelData))
    readonly property var layout: BarLayout.layoutFor(modelData)

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

    // the widgets that are islands of their own; the status parts are drawn
    // by Status, several to an island
    readonly property var islands: ({
        workspaces: workspaces,
        special: special,
        title: title,
        media: media,
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
        id: clock

        Clock {
            settings: root.settings
        }
    }
    Component {
        id: statusIsland

        Status {
            settings: root.settings
        }
    }

    component BarSection: RowLayout {
        property var names: []

        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: BarLayout.groups(parent.names)

            Loader {
                id: slot

                required property var modelData

                sourceComponent: modelData.status ? statusIsland : root.islands[modelData.name] ?? null
                visible: item !== null && item.wanted !== false
                onLoaded: {
                    if (slot.modelData.status)
                        item.parts = Qt.binding(() => slot.modelData.status);
                }
            }
        }
    }

    BarSection {
        anchors.left: parent.left
        names: root.layout.left
    }

    BarSection {
        anchors.horizontalCenter: parent.horizontalCenter
        names: root.layout.center
    }

    BarSection {
        anchors.right: parent.right
        names: root.layout.right
    }
}
