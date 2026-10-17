pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// The player the bar and the media panel show. One picked in the media panel
// (by its name, kept in ~/.local/state/simplychit/media-player) wins while it
// is open; otherwise the first one playing, else the first one there is.
Singleton {
    id: root

    readonly property list<MprisPlayer> players: Mpris.players.values
    property string preferred: ""

    readonly property MprisPlayer active: {
        const picked = players.find(p => p.identity === preferred);
        if (picked)
            return picked;
        for (const player of players)
            if (player.isPlaying)
                return player;
        return players.length > 0 ? players[0] : null;
    }
    readonly property bool playing: active !== null && active.isPlaying
    // any player at all, for the bar: a pinned player that is paused while
    // another plays must still be reachable to unpin it
    readonly property bool anyPlaying: players.some(p => p.isPlaying)
    readonly property string title: active ? active.trackTitle : ""
    readonly property string artist: active ? active.trackArtist : ""

    function prefer(identity: string): void {
        preferred = identity;
        store.setText(identity + "\n");
    }

    FileView {
        id: store

        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/simplychit/media-player"
        printErrors: false
        onLoaded: root.preferred = text().trim()
    }
}
