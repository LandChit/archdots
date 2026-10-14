import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.widgets

// The level card at the bottom of the focused screen. It shows itself when the
// volume, the mic or the brightness changes, from a key, the bar or any app,
// and fades out on its own. Click-through.
//
// qs -c simplychit ipc call osd volume|mic|brightness   (show without a change)
PanelWindow {
    id: root

    property string kind: "volume"
    property bool shown: false
    property real reveal: shown ? 1 : 0
    // PipeWire reports the initial levels as changes; stay quiet until then.
    property bool armed: false

    readonly property var volumeIcons: [[34, "\u{f057f}"], [67, "\u{f0580}"], [10000, "\u{f057e}"]]
    readonly property var brightnessIcons: [[34, "\u{f00de}"], [67, "\u{f00df}"], [10000, "\u{f00e0}"]]

    readonly property int percent: kind === "volume" ? Math.round(Audio.volume * 100)
        : kind === "mic" ? Math.round(Audio.micVolume * 100)
        : Brightness.percent
    readonly property bool muted: kind === "volume" ? Audio.muted : kind === "mic" ? Audio.micMuted : false

    function pick(icons, value) {
        for (const [bound, glyph] of icons)
            if (value < bound)
                return glyph;
        return icons[icons.length - 1][1];
    }

    function show(which: string): void {
        if (!armed || (which === "brightness" && Brightness.percent < 0))
            return;
        kind = which;
        shown = true;
        hide.restart();
    }

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
    visible: reveal > 0
    anchors.bottom: true
    margins.bottom: 90
    implicitWidth: 340
    implicitHeight: 70
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "simplychit-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Behavior on reveal {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Timer {
        id: hide

        interval: 1600
        onTriggered: root.shown = false
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Connections {
        target: Audio

        function onVolumeChanged(): void { root.show("volume"); }
        function onMutedChanged(): void { root.show("volume"); }
        function onMicVolumeChanged(): void { root.show("mic"); }
        function onMicMutedChanged(): void { root.show("mic"); }
    }

    Connections {
        target: Brightness

        function onChanged(): void { root.show("brightness"); }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 320
        height: 50
        y: (1 - root.reveal) * 10
        opacity: root.reveal
        radius: 18
        color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), 0.94)
        border.width: 1
        border.color: Colours.panelBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 14

            BarText {
                px: 22
                color: root.muted ? Colours.alpha(Colours.foreground, 0.45) : Colours.accentBright
                text: root.kind === "mic" ? (root.muted ? "\u{f036d}" : "\u{f036c}")
                    : root.kind === "brightness" ? root.pick(root.brightnessIcons, root.percent)
                    : root.muted || root.percent === 0 ? "\u{f075f}" : root.pick(root.volumeIcons, root.percent)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Colours.alpha(Colours.accent, 0.16)

                Rectangle {
                    width: parent.width * Math.min(root.percent, 100) / 100
                    height: parent.height
                    radius: 3
                    // past 100%: a fixed warm red, since the palette's own
                    // red can come out grey
                    color: root.muted ? Colours.alpha(Colours.foreground, 0.30)
                         : root.percent > 100 ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1)
                         : Colours.accentBright

                    Behavior on width {
                        NumberAnimation { duration: 90 }
                    }
                }
            }

            BarText {
                Layout.minimumWidth: 46
                px: 11.5
                horizontalAlignment: Text.AlignRight
                color: root.percent > 100 && !root.muted ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1) : Colours.alpha(Colours.foreground, 0.72)
                text: root.muted ? (root.kind === "mic" ? "Mic off" : "Muted") : root.percent + "%"
            }
        }
    }
}
