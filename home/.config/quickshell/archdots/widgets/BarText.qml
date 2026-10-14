import QtQuick
import qs.config

// Text as the bar sets it: the Nerd Font, so glyphs and digits share a face.
Text {
    // Size in CSS pixels, as fabric's bar.css gives it. font.pixelSize only
    // takes whole pixels, so this goes through points (1px = 0.75pt at 96 dpi).
    property real px: 12.5

    color: Colours.foreground
    font.family: "JetBrainsMono NF"
    font.pointSize: px * 0.75
    verticalAlignment: Text.AlignVCenter
}
