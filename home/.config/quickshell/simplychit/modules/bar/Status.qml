import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.widgets

// The status widgets that sit next to each other in a bar layout, in one
// island: "indicators" (privacy, recording, stay awake, do not disturb), "volume",
// "cpu" (temperature) and "battery", in the order given. Bar.qml groups
// them; a layout that puts something else between two of them gets two
// islands.
Island {
    id: root

    required property var settings
    property var parts: []

    // (upper bound, glyph): first match wins, the last entry catches the rest
    function pick(icons, value) {
        for (const [bound, glyph] of icons)
            if (value < bound)
                return glyph;
        return icons[icons.length - 1][1];
    }

    function wantedPart(name: string): bool {
        switch (name) {
        case "indicators":
            return Privacy.any || Recorder.recording || Idle.inhibited || Idle.appInhibited || Notifs.dnd;
        case "volume":
            return true;
        case "cpu":
            return root.settings.showCpu !== false;
        case "battery":
            return root.settings.showBattery !== false && Battery.available;
        }
        return false;
    }

    readonly property var shown: parts.filter(p => wantedPart(p))
    // a divider before a part when something other than the indicators came
    // before it: "● 󰕾 50% | 󰍛 45°C | 󰁹 80%"
    function lead(name: string): bool {
        const i = shown.indexOf(name);
        return name !== "indicators" && i > 0 && shown.slice(0, i).some(p => p !== "indicators");
    }

    readonly property bool wanted: shown.length > 0
    readonly property var volumeIcons: [[34, "󰕿"], [67, "󰖀"], [10000, "󰕾"]]
    readonly property var batteryIcons: [[11, "󰂃"], [31, "󰁺"], [51, "󰁼"], [71, "󰁾"], [91, "󰂀"], [10000, "󰁹"]]

    padding: 10

    Repeater {
        model: root.parts

        RowLayout {
            id: part

            required property string modelData

            visible: root.shown.includes(modelData)
            spacing: 0

            Divider {
                visible: root.lead(part.modelData)
            }
            Loader {
                sourceComponent: ({
                    indicators: indicators,
                    volume: volume,
                    cpu: cpu,
                    battery: battery
                })[part.modelData] ?? null
            }
        }
    }

    Component {
        id: indicators

        RowLayout {
            spacing: 0

            // something recording you: microphone, camera, screen; a click
            // lists the apps
            Hot {
                visible: Privacy.any
                onClicked: Panels.toggle("privacy")

                RowLayout {
                    spacing: 0

                    Repeater {
                        model: [[Privacy.screen, "\u{f0379}"], [Privacy.camera, "\u{f0100}"], [Privacy.mic, "\u{f036c}"]].filter(k => k[0].length > 0)

                        BarText {
                            required property var modelData

                            text: modelData[1]
                            leftPadding: 3
                            rightPadding: 3
                            color: Colours.alert
                        }
                    }
                }
            }
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
            // stay awake (SUPER+SHIFT+I), or dimmer while an app keeps the
            // screen awake (a video playing)
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
        }
    }

    Component {
        id: volume

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
                    : root.pick(root.volumeIcons, percent) + " " + percent + "%"
            }
        }
    }

    Component {
        id: cpu

        BarText {
            leftPadding: 5
            rightPadding: 5
            text: CpuTemp.celsius < 0 ? "󰍛 --°C" : "󰍛 " + CpuTemp.celsius + "°C"
        }
    }

    Component {
        id: battery

        Hot {
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    Panels.toggle("battery");
            }

            BarText {
                text: (Battery.charging ? "󰂄" : root.pick(root.batteryIcons, Battery.percent)) + " " + Battery.percent + "%"
            }
        }
    }
}
