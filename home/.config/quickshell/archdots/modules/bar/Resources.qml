import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.widgets

// volume · cpu temperature · battery, with the same glyphs as the fabric bar.
Island {
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
        visible: Config.bar.showCpu
    }

    BarText {
        visible: Config.bar.showCpu
        leftPadding: 5
        rightPadding: 5
        text: CpuTemp.celsius < 0 ? "󰍛 --°C" : "󰍛 " + CpuTemp.celsius + "°C"
    }

    Divider {
        visible: Config.bar.showBattery && Battery.available
    }

    Hot {
        visible: Config.bar.showBattery && Battery.available
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                Panels.toggle("battery");
        }

        BarText {
            text: (Battery.charging ? "󰂄" : pick(batteryIcons, Battery.percent)) + " " + Battery.percent + "%"
        }
    }
}
