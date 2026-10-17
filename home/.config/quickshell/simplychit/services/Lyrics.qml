pragma Singleton

import QtQuick
import Quickshell

// Lyrics for the playing track from LRCLIB (lrclib.net, no key), looked up
// only while `wanted` (the media panel is open) and kept per track for the
// session. Synced lyrics give `lines` with times and `current`, the line
// being sung; plain ones give `lines` without times (current stays -1).
//
//   status  "", "loading", "found", "none" (nothing on LRCLIB), "error"
Singleton {
    id: root

    property bool wanted: false
    property string status: ""
    property var lines: []
    property bool synced: false
    property string key: ""
    property var cache: ({})

    readonly property var player: Media.active
    readonly property string track: player ? player.trackTitle : ""
    readonly property string artist: player ? player.trackArtist : ""
    readonly property string album: player ? player.trackAlbum : ""
    readonly property real length: player && player.lengthSupported ? player.length : 0

    // set by the media panel while it is open; the line whose time has come,
    // -1 before the first or when not synced
    property real position: 0
    readonly property int current: {
        if (!synced)
            return -1;
        let found = -1;
        for (let i = 0; i < lines.length && lines[i].time <= position + 0.25; i++)
            found = i;
        return found;
    }

    // "[01:02.34] words" → { time: 62.34, text: "words" }; a line can carry
    // several stamps; tags such as [ar:…] have no time and are dropped
    function parseSynced(lrc: string): var {
        const out = [];
        for (const raw of lrc.split("\n")) {
            // QML's JavaScript has no matchAll
            const stamps = [];
            const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
            let m;
            while ((m = re.exec(raw)) !== null)
                stamps.push(m);
            if (stamps.length === 0)
                continue;
            const text = raw.replace(/\[[^\]]*\]/g, "").trim();
            for (const s of stamps)
                out.push({ time: parseInt(s[1]) * 60 + parseFloat(s[2]), text: text });
        }
        return out.sort((a, b) => a.time - b.time);
    }

    // LRCLIB is crowd-sourced: an exact match can be a stub ("[00:00.00]probe"
    // on a well-known song), so an entry with next to nothing in it does not
    // count and the search is tried instead
    function usable(entry): bool {
        if (!entry)
            return false;
        if (entry.syncedLyrics)
            return parseSynced(entry.syncedLyrics).filter(l => l.text !== "").length >= 4;
        return (entry.plainLyrics ?? "").trim().length >= 40;
    }

    function show(entry): void {
        if (entry && entry.syncedLyrics) {
            lines = parseSynced(entry.syncedLyrics);
            synced = lines.length > 0;
        } else if (entry && entry.plainLyrics) {
            lines = entry.plainLyrics.split("\n").map(t => ({ time: -1, text: t.trim() }));
            synced = false;
        } else {
            lines = [];
            synced = false;
        }
        status = lines.length > 0 ? "found" : "none";
    }

    function request(url: string, done): void {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let body = null;
            try {
                body = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
            } catch (e) {}
            done(xhr.status, body);
        };
        xhr.open("GET", url);
        // LRCLIB asks clients to name themselves
        xhr.setRequestHeader("Lrclib-Client", "SimplyChit (https://github.com/LandChit/archdots)");
        xhr.send();
    }

    function lookup(): void {
        if (!wanted || track === "")
            return;
        const want = artist + "\n" + track;
        if (want === key && status !== "error")
            return;
        key = want;
        if (want in cache) {
            show(cache[want]);
            return;
        }
        status = "loading";
        lines = [];
        synced = false;
        const q = s => encodeURIComponent(s);
        let url = "https://lrclib.net/api/get?track_name=" + q(track) + "&artist_name=" + q(artist);
        if (album !== "")
            url += "&album_name=" + q(album);
        if (length > 0)
            url += "&duration=" + Math.round(length);
        request(url, (code, body) => {
            if (key !== want)
                return;  // the track changed while this was out
            if (code === 200 && usable(body)) {
                remember(want, body);
                return;
            }
            if (code !== 200 && code !== 404) {
                status = "error";
                return;
            }
            // no exact match (the album or length differ, or it was a stub):
            // the search, synced hits first, nearest in length first
            request("https://lrclib.net/api/search?track_name=" + q(track) + "&artist_name=" + q(artist), (code2, hits) => {
                if (key !== want)
                    return;
                if (code2 !== 200 || !Array.isArray(hits)) {
                    status = code2 === 404 ? "none" : "error";
                    return;
                }
                const off = h => length > 0 && h.duration ? Math.abs(h.duration - length) : 0;
                const good = hits.filter(h => usable(h)).sort((a, b) => (b.syncedLyrics ? 1 : 0) - (a.syncedLyrics ? 1 : 0) || off(a) - off(b));
                remember(want, good[0] ?? null);
            });
        });
    }

    function remember(want: string, entry): void {
        const next = Object.assign({}, cache);
        next[want] = entry;
        cache = next;
        show(entry);
    }

    onWantedChanged: lookup()
    onTrackChanged: Qt.callLater(lookup)
    onArtistChanged: Qt.callLater(lookup)
}
