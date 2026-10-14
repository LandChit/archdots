import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.widgets

// Previous / play-pause / next and "title · artist". Only shown while a
// player is playing, so it can afford the space.
Island {
    required property var settings
    id: root

    padding: 10
    // read by the bar's Loader: an item's own `visible` is false whenever its
    // parent is hidden, so it cannot drive the parent's visibility
    readonly property bool wanted: settings.showMedia && Media.playing
    visible: wanted

    component MediaButton: BarText {
        id: button

        signal activated

        px: 13
        leftPadding: 3
        rightPadding: 3
        color: area.containsMouse ? Colours.accent : Colours.alpha(Colours.foreground, 0.70)

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }

    MediaButton {
        text: "󰒮"
        onActivated: Media.active?.previous()
    }
    MediaButton {
        text: Media.playing ? "󰏤" : "󰐊"
        onActivated: Media.active?.togglePlaying()
    }
    MediaButton {
        text: "󰒭"
        onActivated: Media.active?.next()
    }

    BarText {
        readonly property string full: Media.artist === "" ? Media.title : Media.title + " · " + Media.artist

        px: 11.5
        leftPadding: 6
        rightPadding: 4
        text: full.length > settings.mediaChars ? full.slice(0, settings.mediaChars) + "…" : full
    }
}
