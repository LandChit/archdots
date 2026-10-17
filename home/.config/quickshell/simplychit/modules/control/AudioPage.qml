import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.config
import qs.widgets

// Audio devices and per-app volume (TODO 10): pick the default output and
// input; give each playing app its own level.
ColumnLayout {
    id: root

    property bool active: false

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio !== null)
    readonly property var outputs: nodes.filter(n => n.isSink && !n.isStream)
    readonly property var inputs: nodes.filter(n => !n.isSink && !n.isStream)
    // an app playing sound: Quickshell flags a playback stream as a sink
    // (type AudioOutStream, Audio | Stream | Sink); a recording one is not
    readonly property var apps: nodes.filter(n => n.isStream && n.isSink)

    function portName(n: var): string {
        return n.nickname || n.properties["node.nick"] || n.properties["device.profile.description"] || n.description || n.name;
    }

    function appName(n: var): string {
        return n.properties["application.name"] || n.description || n.name;
    }

    spacing: 4

    // per-app volumes are only live while tracked
    PwObjectTracker {
        objects: root.active ? root.apps.concat(root.outputs, root.inputs) : []
    }

    BarText {
        text: "Output"
        px: 10.5
        color: Colours.accentBright
        Layout.leftMargin: 4
    }
    Repeater {
        model: root.outputs

        InfoRow {
            required property var modelData

            glyph: "\u{f04c3}"
            // the card's description is the same for every port on it; the
            // nickname ("Speaker", "HDMI 1", …) is what tells them apart
            title: root.portName(modelData)
            subtitle: modelData.description
            active: Pipewire.defaultAudioSink === modelData
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }

    BarText {
        text: "Input"
        px: 10.5
        color: Colours.accentBright
        Layout.leftMargin: 4
        Layout.topMargin: 6
    }
    Repeater {
        model: root.inputs

        InfoRow {
            required property var modelData

            glyph: "\u{f036c}"
            title: root.portName(modelData)
            subtitle: modelData.description
            active: Pipewire.defaultAudioSource === modelData
            onClicked: Pipewire.preferredDefaultAudioSource = modelData
        }
    }

    BarText {
        text: "Apps"
        px: 10.5
        color: Colours.accentBright
        Layout.leftMargin: 4
        Layout.topMargin: 6
    }
    BarText {
        visible: root.apps.length === 0
        text: "Nothing is playing"
        px: 11
        color: Colours.subtext
        Layout.leftMargin: 4
    }
    Repeater {
        model: root.apps

        InfoRow {
            id: app

            required property var modelData

            glyph: modelData.audio.muted ? "\u{f075f}" : "\u{f057e}"
            title: root.appName(modelData)
            trailing: Math.round(modelData.audio.volume * 100) + "%"
            onClicked: modelData.audio.muted = !modelData.audio.muted

            Slider {
                width: parent.width
                value: app.modelData.audio.volume
                onMoved: v => app.modelData.audio.volume = v
            }
        }
    }
}
