pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Event sounds from the freedesktop sound theme, played with pw-play: a tick
// when the output volume changes (from a key, the bar or any app) and a chime
// for each notification that pops up. sounds.volume and sounds.notifications
// turn them off.
Singleton {
    id: root

    readonly property string theme: "/usr/share/sounds/freedesktop/stereo/"

    // PipeWire reports the starting volume as a change; stay quiet until then.
    property bool armed: false

    function play(name: string): void {
        Quickshell.execDetached(["pw-play", theme + name + ".oga"]);
    }

    // Called by Notifs for each notification while do not disturb is off.
    // Apps can ask for silence with the suppress-sound hint.
    function notification(critical: bool, hints: var): void {
        if (!Config.sounds.notifications || (hints && hints["suppress-sound"]))
            return;
        play(critical ? "dialog-warning" : "message");
    }

    // Holding a volume key changes the level many times a second: one tick
    // once it settles, not one per step.
    Timer {
        id: settle

        interval: 90
        onTriggered: {
            if (Audio.ready && !Audio.muted)
                root.play("audio-volume-change");
        }
    }

    Connections {
        target: Audio

        function onVolumeChanged(): void {
            if (root.armed && Config.sounds.volume)
                settle.restart();
        }
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }
}
