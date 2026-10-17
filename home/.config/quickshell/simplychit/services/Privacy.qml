pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// What is recording you, for the bar's privacy indicators: lists of app names
// using the microphone, the camera, or sharing the screen.
//
//   mic     PipeWire streams capturing audio, except ones that capture what
//           is playing (visualisers, recorders of the output)
//   screen  streams fed by xdg-desktop-portal-hyprland's screencast nodes
//           ("xdph-streaming-…"), or "Screen sharing" while one runs
//   camera  other PipeWire video capture streams, plus apps that open
//           /dev/video* directly (`simplychit privacy-watch`, inotify)
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values

    // capture streams, told apart by their type flags (always there); their
    // properties (the app's name, stream.capture.sink) are only filled in
    // while something tracks them, so these few are tracked
    function capturing(node, kind: int): bool {
        return node.isStream && (node.type & PwNodeType.Source) && (node.type & kind);
    }

    readonly property var captures: nodes.filter(n => capturing(n, PwNodeType.Audio | PwNodeType.Video))

    PwObjectTracker {
        objects: root.captures
    }

    function prop(node, key: string): string {
        return node && node.properties ? (node.properties[key] ?? "") : "";
    }

    function appOf(node): string {
        return prop(node, "application.name") || prop(node, "application.process.binary") || node.description || node.name || "Unknown";
    }

    function unique(names): var {
        return names.filter((n, i) => names.indexOf(n) === i);
    }

    // this shell's own streams (the media panel's visualiser) are not someone
    // recording you
    function ours(node): bool {
        const bin = prop(node, "application.process.binary");
        return bin === "quickshell" || bin === "qs" || bin === "cava";
    }

    readonly property var screenSources: nodes.filter(n => (n.name ?? "").startsWith("xdph-streaming-"))
    readonly property var videoStreams: captures.filter(n => capturing(n, PwNodeType.Video) && !ours(n))

    // the streams a screencast node feeds
    readonly property var screenStreams: {
        const sources = screenSources;
        if (sources.length === 0)
            return [];
        const fed = Pipewire.links.values.filter(l => l.source && sources.includes(l.source)).map(l => l.target);
        return videoStreams.filter(s => fed.includes(s));
    }

    readonly property var mic: unique(captures.filter(n => capturing(n, PwNodeType.Audio) && prop(n, "stream.capture.sink") !== "true" && !ours(n)).map(appOf))

    readonly property var screen: screenStreams.length > 0 ? unique(screenStreams.map(appOf)) : screenSources.length > 0 ? ["Screen sharing"] : []

    property var directCamera: []
    readonly property var camera: unique(videoStreams.filter(s => !screenStreams.includes(s)).map(appOf).concat(directCamera))

    readonly property bool any: mic.length > 0 || camera.length > 0 || screen.length > 0

    // apps opening a camera without PipeWire; restarted if it ever exits
    Process {
        id: watcher

        running: true
        command: [Quickshell.env("HOME") + "/.local/bin/simplychit", "privacy-watch"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.directCamera = root.unique(JSON.parse(line).camera.map(u => u.app));
                } catch (e) {
                    console.warn("privacy-watch: " + e);
                }
            }
        }
        onExited: restart.start()
    }

    Timer {
        id: restart

        interval: 5000
        onTriggered: watcher.running = true
    }
}
