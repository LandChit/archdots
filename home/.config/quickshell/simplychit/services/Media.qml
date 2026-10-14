pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The player the bar shows: the first one playing, else the first one there is.
Singleton {
    id: root

    readonly property list<MprisPlayer> players: Mpris.players.values
    readonly property MprisPlayer active: {
        for (const player of players)
            if (player.isPlaying)
                return player;
        return players.length > 0 ? players[0] : null;
    }
    readonly property bool playing: active !== null && active.isPlaying
    readonly property string title: active ? active.trackTitle : ""
    readonly property string artist: active ? active.trackArtist : ""
}
