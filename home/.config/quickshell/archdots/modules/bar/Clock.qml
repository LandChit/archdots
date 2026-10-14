import QtQuick
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The accent-tinted anchor of the bar. Click for the calendar.
Island {
    required property var settings
    color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.35), 0.92)
    border.color: Colours.alpha(Colours.accent, 0.55)

    SystemClock {
        id: clock

        // Ticking every second costs a redraw a second, so only when shown.
        precision: settings.clockFormat.includes("s") ? SystemClock.Seconds : SystemClock.Minutes
    }

    BarText {
        color: Colours.highlight
        text: Qt.formatDateTime(clock.date, settings.clockFormat)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Panels.toggle("calendar")
        }
    }
}
