import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The media panel, opened from the bar's media island: cover art, the track,
// a seek bar, the controls, a switcher when several players are open (the one
// picked becomes the bar's player), a cava spectrum (services/Visualiser.qml)
// and synced lyrics from LRCLIB (services/Lyrics.qml). The visualiser and the
// lyrics only run while the panel is open.
Panel {
    id: root

    name: "media"
    anchors.top: true
    margins.top: 46
    implicitWidth: 440
    implicitHeight: card.implicitHeight + 20

    readonly property var player: Media.active
    // MPRIS does not push the position; read it twice a second while shown
    property real position: 0

    function clock(seconds: real): string {
        if (!(seconds >= 0))
            return "-:--";
        const s = Math.floor(seconds);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    function refresh(): void {
        if (player) {
            player.positionChanged();
            position = player.position;
        }
    }

    onOpened: {
        keys.forceActiveFocus();
        refresh();
    }

    Binding {
        target: Visualiser
        property: "wanted"
        value: root.shown && Media.playing
    }
    Binding {
        target: Lyrics
        property: "wanted"
        value: root.shown
    }
    Binding {
        target: Lyrics
        property: "position"
        value: root.position
    }

    Timer {
        interval: 500
        running: root.shown && root.player !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // nothing to show any more: close
    onPlayerChanged: {
        if (player === null)
            close();
        else
            refresh();
    }

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onSpacePressed: root.player?.togglePlaying()
        Keys.onLeftPressed: root.player?.previous()
        Keys.onRightPressed: root.player?.next()
    }

    Rectangle {
        id: card

        width: root.implicitWidth
        implicitHeight: column.implicitHeight + 32
        y: (1 - root.reveal) * -10
        opacity: root.reveal
        radius: 18
        color: Colours.panel
        border.width: 1
        border.color: Colours.panelBorder

        ColumnLayout {
            id: column

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 12

            // cover and track
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Rectangle {
                    implicitWidth: 84
                    implicitHeight: 84
                    radius: 12
                    color: Colours.alpha(Colours.accent, 0.16)
                    clip: true

                    BarText {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: "\u{f075a}"
                        px: 30
                        color: Colours.subtext
                    }
                    Image {
                        id: cover

                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        sourceSize: Qt.size(168, 168)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    BarText {
                        Layout.fillWidth: true
                        text: root.player ? (root.player.trackTitle || root.player.identity) : ""
                        px: 15
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    BarText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.player ? [root.player.trackArtist, root.player.trackAlbum].filter(t => t).join(" · ") : ""
                        px: 11.5
                        color: Colours.subtext
                        elide: Text.ElideRight
                    }
                    BarText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: Media.players.length < 2
                        text: root.player ? root.player.identity.toUpperCase() : ""
                        px: 9.5
                        color: Colours.hint
                        font.letterSpacing: 0.6
                    }
                }
            }

            // the spectrum
            Item {
                Layout.fillWidth: true
                implicitHeight: 44
                visible: Visualiser.available && Media.playing

                Row {
                    id: spectrum

                    anchors.fill: parent
                    spacing: 3

                    Repeater {
                        model: Visualiser.bars

                        Rectangle {
                            required property int index

                            readonly property real level: Visualiser.levels[index] ?? 0

                            anchors.bottom: parent.bottom
                            width: (spectrum.width - (Visualiser.bars - 1) * 3) / Visualiser.bars
                            height: Math.max(3, level * spectrum.height)
                            radius: Math.min(width / 2, 3)
                            color: Colours.alpha(Colours.accentBright, 0.45 + 0.55 * level)

                            Behavior on height {
                                NumberAnimation { duration: 60 }
                            }
                        }
                    }
                }
            }

            // seek
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.player !== null && root.player.lengthSupported && root.player.length > 0
                spacing: 2

                Slider {
                    Layout.fillWidth: true
                    value: root.player && root.player.length > 0 ? root.position / root.player.length : 0
                    step: 0.02
                    enabled: root.player !== null && root.player.canSeek
                    opacity: enabled ? 1 : 0.5
                    onMoved: v => {
                        root.player.position = v * root.player.length;
                        root.position = root.player.position;
                    }
                }
                RowLayout {
                    Layout.fillWidth: true

                    BarText {
                        text: root.clock(root.position)
                        px: 10
                        color: Colours.subtext
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    BarText {
                        text: root.clock(root.player ? root.player.length : -1)
                        px: 10
                        color: Colours.subtext
                    }
                }
            }

            // controls
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 18

                Repeater {
                    model: [["\u{f04ae}", "previous", root.player !== null && root.player.canGoPrevious],
                        [Media.playing ? "\u{f03e4}" : "\u{f040a}", "toggle", root.player !== null && root.player.canTogglePlaying],
                        ["\u{f04ad}", "next", root.player !== null && root.player.canGoNext]]

                    Hot {
                        id: control

                        required property var modelData

                        implicitWidth: modelData[1] === "toggle" ? 48 : 36
                        implicitHeight: modelData[1] === "toggle" ? 48 : 36
                        radius: implicitWidth / 2
                        enabled: modelData[2] === true
                        opacity: enabled ? 1 : 0.4
                        color: modelData[1] === "toggle" ? Colours.alpha(Colours.accent, 0.35) : "transparent"
                        onClicked: {
                            if (modelData[1] === "previous")
                                root.player.previous();
                            else if (modelData[1] === "next")
                                root.player.next();
                            else
                                root.player.togglePlaying();
                        }

                        BarText {
                            text: control.modelData[0]
                            px: control.modelData[1] === "toggle" ? 22 : 17
                        }
                    }
                }
            }

            // several players: pick the one shown here and in the bar
            Flow {
                Layout.fillWidth: true
                visible: Media.players.length > 1
                spacing: 6

                Repeater {
                    model: Media.players

                    Hot {
                        id: chip

                        required property var modelData
                        readonly property bool current: modelData === root.player

                        implicitHeight: 24
                        color: current ? Colours.alpha(Colours.accent, 0.35) : Colours.alpha(Colours.accent, 0.10)
                        onClicked: Media.prefer(modelData.identity)

                        BarText {
                            text: (chip.modelData.isPlaying ? "\u{f040a} " : "") + chip.modelData.identity
                            px: 10.5
                            color: chip.current ? Colours.foreground : Colours.subtext
                        }
                    }
                }
            }

            // lyrics
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Colours.alpha(Colours.accent, 0.20)
                visible: lyricsBox.visible
            }

            Item {
                id: lyricsBox

                Layout.fillWidth: true
                visible: root.player !== null && root.player.trackTitle !== ""
                implicitHeight: Lyrics.status === "found" ? (Lyrics.synced ? 150 : 180) : 28

                BarText {
                    anchors.centerIn: parent
                    visible: Lyrics.status !== "found"
                    text: ({ loading: "Looking for lyrics…", none: "No lyrics found", error: "Lyrics unavailable (offline?)" })[Lyrics.status] ?? ""
                    px: 11
                    color: Colours.hint
                }

                // synced: the current line in the middle, the rest fading out
                ListView {
                    id: synced

                    anchors.fill: parent
                    visible: Lyrics.status === "found" && Lyrics.synced
                    clip: true
                    interactive: false
                    model: Lyrics.synced ? Lyrics.lines : []
                    currentIndex: Math.max(0, Lyrics.current)
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: height / 2 - 14
                    preferredHighlightEnd: height / 2 + 14
                    highlightMoveDuration: 350
                    spacing: 4

                    delegate: BarText {
                        required property var modelData
                        required property int index

                        readonly property bool now: index === Lyrics.current

                        width: synced.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: modelData.text === "" ? "♪" : modelData.text
                        px: now ? 13.5 : 12
                        font.weight: now ? Font.Medium : Font.Normal
                        color: now ? Colours.foreground : Colours.alpha(Colours.foreground, Math.max(0.18, 0.55 - Math.abs(index - Lyrics.current) * 0.12))

                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }
                    }
                }

                // plain: scroll by hand
                Flickable {
                    anchors.fill: parent
                    visible: Lyrics.status === "found" && !Lyrics.synced
                    clip: true
                    contentHeight: plain.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    BarText {
                        id: plain

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Lyrics.synced ? "" : Lyrics.lines.map(l => l.text).join("\n")
                        px: 12
                        color: Colours.alpha(Colours.foreground, 0.75)
                    }
                }
            }
        }
    }
}
