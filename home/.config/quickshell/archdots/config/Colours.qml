pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The pywal16 palette, read straight from ~/.cache/wal/colors.json and watched,
// so a wallpaper change recolours the shell without a restart. The defaults are
// the palette at the time of writing, so the shell still looks right before
// pywal16 has ever run.
Singleton {
    id: root

    readonly property color background: wal.special.background
    readonly property color foreground: wal.special.foreground
    // color4 is the accent everywhere: bar, borders, GTK.
    readonly property color accent: wal.colors.color4
    // color12 is a distinct colour only under --cols16 dual.
    readonly property color accentBright: wal.colors.color12
    readonly property color highlight: wal.colors.color7

    // The island surface:
    // alpha(mix(background, color4, 0.22), 0.88)
    readonly property color island: alpha(mix(background, accent, 0.22), 0.88)
    readonly property color islandBorder: alpha(accent, 0.28)
    // Panels and cards: the island surface, more opaque.
    readonly property color panel: alpha(mix(background, accent, 0.22), 0.92)
    readonly property color panelBorder: alpha(accent, 0.28)
    // Behind full-screen menus.
    readonly property color scrim: Qt.rgba(8 / 255, 10 / 255, 14 / 255, 0.62)
    readonly property color subtext: alpha(foreground, 0.55)
    readonly property color hint: alpha(foreground, 0.50)
    // Keyboard selection: a different hue from hover (accent), not just a
    // stronger alpha, so a hovered row and a selected row are told apart.
    readonly property color selection: alpha(accentBright, 0.18)
    readonly property color selectionBorder: alpha(accentBright, 0.50)
    readonly property color hover: alpha(accent, 0.10)

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // GTK's mix(): t = 0 is a, t = 1 is b.
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: wal

            property JsonObject special: JsonObject {
                property string background: "#080c14"
                property string foreground: "#c1c2c4"
            }

            property JsonObject colors: JsonObject {
                property string color4: "#483930"
                property string color7: "#8c9097"
                property string color12: "#ac6c4a"
            }
        }
    }
}
