pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property string font:   "JetBrainsMono NF"
    readonly property int    radius: 8
    readonly property int    gap:    8

    property color bg:      "#1e1e2e"
    property color fg:      "#cdd6f4"
    property color color0:  "#1e1e2e"
    property color color1:  "#f38ba8"
    property color color2:  "#a6e3a1"
    property color color3:  "#f9e2af"
    property color color4:  "#89b4fa"
    property color color5:  "#f5c2e7"
    property color color6:  "#94e2d5"
    property color color7:  "#bac2de"
    property color color8:  "#585b70"
    property color color9:  "#f38ba8"
    property color color10: "#a6e3a1"
    property color color11: "#f9e2af"
    property color color12: "#89b4fa"
    property color color13: "#f5c2e7"
    property color color14: "#94e2d5"
    property color color15: "#a6adc8"

    property color accent:  color1
    property color surface: Qt.lighter(bg, 1.5)
    property color border:  Qt.rgba(fg.r, fg.g, fg.b, 0.12)
    property color muted:   Qt.rgba(fg.r, fg.g, fg.b, 0.5)

    property FileView _file: FileView {
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.cache/wal/colors.json"
        onTextChanged: root._parse(text)
    }

    function _parse(json) {
        if (!json || json.trim() === "") return
        try {
            const d = JSON.parse(json)
            bg      = d.special.background
            fg      = d.special.foreground
            color0  = d.colors.color0;  color1  = d.colors.color1
            color2  = d.colors.color2;  color3  = d.colors.color3
            color4  = d.colors.color4;  color5  = d.colors.color5
            color6  = d.colors.color6;  color7  = d.colors.color7
            color8  = d.colors.color8;  color9  = d.colors.color9
            color10 = d.colors.color10; color11 = d.colors.color11
            color12 = d.colors.color12; color13 = d.colors.color13
            color14 = d.colors.color14; color15 = d.colors.color15
        } catch(e) {
            console.warn("[Palette] parse error:", e)
        }
    }
}
