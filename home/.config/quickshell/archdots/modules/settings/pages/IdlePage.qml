import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

ColumnLayout {
    spacing: 14

    component Times: Section {
        id: times

        required property string source
        readonly property var values: Config.idle[source]

        Repeater {
            model: [["dim", "Dim the screen"], ["lock", "Lock"], ["screenOff", "Turn the screens off"], ["suspend", "Suspend"]]

            Setting {
                required property var modelData

                label: modelData[1]
                help: "minutes idle; 0 is never"
                NumberField {
                    value: times.values[modelData[0]]
                    from: 0
                    to: 600
                    step: 0.5
                    suffix: " min"
                    onEdited: v => Config.set("idle." + times.source + "." + modelData[0], v)
                }
            }
        }
    }

    PageTitle {
        title: "Idle & power"
        description: "Stay awake (SUPER+SHIFT+I) and apps that inhibit idle, such as a playing video, pause all of these."
    }

    Times {
        title: "On AC power"
        source: "ac"
    }
    Times {
        title: "On battery"
        source: "battery"
        visible: Battery.available
    }

    Section {
        title: "Battery"
        visible: Battery.available

        Setting {
            label: "Low warning at"
            NumberField {
                value: Config.battery.lowPercent
                to: 100
                suffix: "%"
                onEdited: v => Config.set("battery.lowPercent", v)
            }
        }
        Setting {
            label: "Critical warning at"
            NumberField {
                value: Config.battery.criticalPercent
                to: 100
                suffix: "%"
                onEdited: v => Config.set("battery.criticalPercent", v)
            }
        }
        Setting {
            label: "Then, at"
            help: "after a 30 s countdown you can cancel"
            RowLayout {
                spacing: 8
                NumberField {
                    value: Config.battery.actionPercent
                    to: 50
                    suffix: "%"
                    onEdited: v => Config.set("battery.actionPercent", v)
                }
                Dropdown {
                    fieldWidth: 130
                    options: [["suspend", "suspend"], ["hibernate", "hibernate"], ["poweroff", "power off"], ["none", "do nothing"]]
                    value: Config.battery.criticalAction
                    onChosen: v => Config.set("battery.criticalAction", v)
                }
            }
        }
    }

    Section {
        title: "Power profile"

        Setting {
            label: PowerProfile.available ? "Profile" : "Not available"
            help: PowerProfile.available ? "click to cycle saver → balanced → performance" : "needs power-profiles-daemon, or TLP's tlp-pd: sudo systemctl enable --now tlp-pd"
            Button {
                visible: PowerProfile.available
                text: PowerProfile.label
                onClicked: PowerProfile.cycle()
            }
        }
    }

    Section {
        title: "Lock screen"
        description: "Off: hyprlock locks the screen. On: the shell's own lock screen does, with hyprlock as the fallback if the shell is not answering."

        Setting {
            label: "Use the shell's lock screen"
            help: "try the preview first, and keep a TTY (Ctrl+Alt+F2) in reach the first time"
            RowLayout {
                spacing: 8
                Button {
                    text: "Preview"
                    onClicked: Quickshell.execDetached(["qs", "-c", "archdots", "ipc", "call", "lock", "preview"])
                }
                Switch {
                    checked: Config.lock.enabled
                    onToggled: v => Config.set("lock.enabled", v)
                }
            }
        }
    }
}
