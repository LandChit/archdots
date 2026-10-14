import QtQuick
import qs.config

// The faint dot between meters in an island.
BarText {
    text: "·"
    px: 10
    color: Colours.alpha(Colours.foreground, 0.30)
    leftPadding: 2
    rightPadding: 2
}
