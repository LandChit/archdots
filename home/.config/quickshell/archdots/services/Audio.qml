pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.config

// The default output and input devices. PipeWire pushes every change, so
// there is no polling and no fallback timer (the fabric bar needed both).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    // 0..1, past 1 when boosted
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micReady: source !== null && source.audio !== null
    readonly property real micVolume: micReady ? source.audio.volume : 0
    readonly property bool micMuted: micReady ? source.audio.muted : false

    function setVolume(value: real): void {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(Config.audio.maxVolume, value));
    }

    // steps: notches, positive is louder
    function nudge(steps: real): void {
        setVolume(volume + steps * Config.audio.scrollStep / 100);
    }

    function toggleMute(): void {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleMicMute(): void {
        if (micReady)
            source.audio.muted = !source.audio.muted;
    }

    // A node's audio properties are only live while something tracks it.
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
}
