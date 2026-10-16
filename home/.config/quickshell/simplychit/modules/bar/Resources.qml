import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.widgets

// volume · cpu temperature · battery.
Island {
    required property var settings
    padding: 10

    // (upper bound, glyph): first match wins, the last entry catches the rest
    function pick(icons, value) {
        for (const [bound, glyph] of icons)
            if (value < bound)
                return glyph;
        return icons[icons.length - 1][1];
    }

    readonly property var volumeIcons: [[34, "󰕿"], [67, "󰖀"], [10000, "󰕾"]]
    readonly property var batteryIcons: [[11, "󰂃"], [31, "󰁺"], [51, "󰁼"], [71, "󰁾"], [91, "󰂀"], [10000, "󰁹"]]

    // recording: a click stops it
    Hot {
        visible: Recorder.recording
        onClicked: Recorder.stop()

        BarText {
            text: "\u{f044a} " + Recorder.elapsed
            leftPadding: 3
            rightPadding: 3
            color: Colours.alert
        }
    }

    // stay awake (SUPER+SHIFT+I), or dimmer while an app keeps the screen
    // awake (a video playing), and do-not-disturb, only while on
    BarText {
        visible: Idle.inhibited || Idle.appInhibited
        text: "\u{f0176}"
        leftPadding: 3
        rightPadding: 3
        color: Idle.inhibited ? Colours.accentBright : Colours.subtext
    }
    BarText {
        visible: Notifs.dnd
        text: "\u{f009b}"
        leftPadding: 3
        rightPadding: 3
        color: Colours.accentBright
    }

    Hot {
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                Audio.toggleMute();
        }
        onScrolled: steps => Audio.nudge(steps)

        BarText {
            readonly property int percent: Math.round(Audio.volume * 100)

            text: !Audio.ready ? "󰝟 --%"
                : Audio.muted ? "󰝟 Muted"
                : percent === 0 ? "󰝟 0%"
                : pick(volumeIcons, percent) + " " + percent + "%"
        }
    }

    Divider {
        visible: settings.showCpu
    }

    BarText {
        visible: settings.showCpu
        leftPadding: 5
        rightPadding: 5
        text: CpuTemp.celsius < 0 ? "󰍛 --°C" : "󰍛 " + CpuTemp.celsius + "°C"
    }

    Divider {
        visible: settings.showBattery && Battery.available
    }

    Hot {
        visible: settings.showBattery && Battery.available
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                Panels.toggle("battery");
        }

        BarText {
            text: (Battery.charging ? "󰂄" : pick(batteryIcons, Battery.percent)) + " " + Battery.percent + "%"
        }
    }
}
