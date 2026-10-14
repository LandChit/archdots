import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

ColumnLayout {
    id: page

    spacing: 14

    function toggleExcluded(name: string, on: bool): void {
        const list = Config.bar.excluded.filter(n => n !== name);
        Config.set("bar.excluded", on ? list : list.concat([name]));
    }

    PageTitle {
        title: "Bar"
        description: "What the bar shows. Per-screen differences: bar.monitors in settings.json (CUSTOMIZING.md)."
    }

    Section {
        title: "Islands"

        Setting {
            label: "What's playing"
            Switch {
                checked: Config.bar.showMedia
                onToggled: v => Config.set("bar.showMedia", v)
            }
        }
        Setting {
            label: "CPU temperature"
            Switch {
                checked: Config.bar.showCpu
                onToggled: v => Config.set("bar.showCpu", v)
            }
        }
        Setting {
            label: "Battery"
            help: "only on a machine that has one"
            Switch {
                checked: Config.bar.showBattery
                onToggled: v => Config.set("bar.showBattery", v)
            }
        }
    }

    Section {
        title: "Clock and title"

        Setting {
            label: "Clock"
            Choice {
                options: [["hh:mm AP", "12-hour"], ["HH:mm", "24-hour"], ["HH:mm:ss", "with seconds"]]
                value: Config.bar.clockFormat
                onChosen: v => Config.set("bar.clockFormat", v)
            }
        }
        Setting {
            label: "Clock format"
            help: "Qt's date format, for anything else"
            TextField {
                fieldWidth: 160
                value: Config.bar.clockFormat
                onEdited: v => Config.set("bar.clockFormat", v)
            }
        }
        Setting {
            label: "Title when nothing has focus"
            TextField {
                fieldWidth: 160
                value: Config.bar.emptyTitle
                onEdited: v => Config.set("bar.emptyTitle", v)
            }
        }
        Setting {
            label: "Longest window title"
            help: "characters"
            NumberField {
                value: Config.bar.titleChars
                from: 5
                to: 120
                onEdited: v => Config.set("bar.titleChars", v)
            }
        }
    }

    Section {
        title: "Screens"
        description: "Turn the bar off on a screen."

        Repeater {
            model: Quickshell.screens

            Setting {
                required property ShellScreen modelData

                label: modelData.name
                help: modelData.model
                Switch {
                    checked: !Config.bar.excluded.includes(modelData.name)
                    onToggled: v => page.toggleExcluded(modelData.name, v)
                }
            }
        }
    }
}
