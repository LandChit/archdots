import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.widgets

// Special (scratchpad) workspaces that hold windows (TODO C7): one chip
// each, lit while it is shown on this screen. Click to show or hide it.
Island {
    id: root

    required property string monitorName

    readonly property var specials: Hyprland.workspaces.values.filter(ws => ws.id < 0 && ws.toplevels.values.length > 0)
    readonly property string shownHere: {
        const monitor = Hyprland.monitors.values.find(m => m.name === monitorName);
        const special = monitor && monitor.lastIpcObject ? monitor.lastIpcObject.specialWorkspace : null;
        return special ? special.name : "";
    }

    function toggle(name: string): void {
        const short = name.replace(/^special:/, "");
        Quickshell.execDetached(["hyprctl", "dispatch", Hyprland.usingLua ? "hl.dsp.workspace.toggle_special(\"" + short + "\")" : "togglespecialworkspace " + short]);
    }

    readonly property bool wanted: specials.length > 0 // see MediaIsland
    visible: wanted
    padding: 6
    spacing: 4

    // the monitor's specialWorkspace only arrives with a refresh
    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name === "activespecial")
                Hyprland.refreshMonitors();
        }
    }

    Repeater {
        model: root.specials

        Rectangle {
            id: chip

            required property HyprlandWorkspace modelData
            readonly property bool shown: root.shownHere === modelData.name

            implicitWidth: label.implicitWidth + 16
            implicitHeight: 22
            radius: 7
            color: shown ? Colours.alpha(Colours.accent, 0.30) : Colours.alpha(Colours.accent, 0.12)
            border.width: 1
            border.color: shown ? Colours.alpha(Colours.accent, 0.55) : "transparent"

            BarText {
                id: label

                anchors.centerIn: parent
                text: "\u{f0aa2} " + chip.modelData.name.replace(/^special:/, "")
                px: 11.5
                color: chip.shown ? Colours.highlight : Colours.alpha(Colours.foreground, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggle(chip.modelData.name)
            }
        }
    }
}
