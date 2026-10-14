import QtQuick
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The accent-tinted anchor of the bar. Click for the calendar.
Island {
    color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.35), 0.92)
    border.color: Colours.alpha(Colours.accent, 0.55)

    SystemClock {
        id: clock

        // Ticking every second costs a redraw a second, so only when shown.
        precision: Config.bar.clockFormat.includes("s") ? SystemClock.Seconds : SystemClock.Minutes
    }

    BarText {
        color: Colours.highlight
        text: Qt.formatDateTime(clock.date, Config.bar.clockFormat)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Panels.toggle("calendar")
        }
    }
}
