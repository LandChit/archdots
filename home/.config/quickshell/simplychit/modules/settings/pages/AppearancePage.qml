import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

ColumnLayout {
    spacing: 14

    PageTitle {
        title: "Appearance"
        description: "Everything is coloured from the wallpaper by pywal16. Changes apply straight away."
    }

    Section {
        title: "Wallpaper"

        Setting {
            label: "Current wallpaper"
            help: Theme.current === "" ? "none yet" : Theme.current.replace(Quickshell.env("HOME"), "~")

            RowLayout {
                spacing: 6
                Button {
                    text: "Choose…"
                    onClicked: Panels.open("wallpaper")
                }
                Button {
                    text: "Random"
                    onClicked: Theme.next(true)
                }
            }
        }
        Setting {
            label: "Change it every"
            help: "minutes, picking another one from the folder; 0 is off"

            NumberField {
                value: Config.wallpaper.cycleMinutes
                from: 0
                to: 1440
                step: 5
                onEdited: v => Config.set("wallpaper.cycleMinutes", v)
            }
        }
        Setting {
            label: "Crossfade"
            help: "milliseconds when the wallpaper changes; 0 is a cut"

            NumberField {
                value: Config.wallpaper.transitionMs
                from: 0
                to: 5000
                step: 100
                onEdited: v => Config.set("wallpaper.transitionMs", v)
            }
        }
        Setting {
            label: "Wallpaper folder"

            TextField {
                value: Config.wallpaper.directory
                onEdited: v => {
                    Config.set("wallpaper.directory", v);
                    Qt.callLater(Theme.rescan);
                }
            }
        }
    }

    Section {
        title: "Colours"

        Setting {
            label: "Mode"
            help: "a light or a dark palette from the same wallpaper"

            Choice {
                options: [["dark", "Dark"], ["light", "Light"]]
                value: Config.theme.mode
                onChosen: v => Theme.setMode(v)
            }
        }
        Setting {
            label: "Colour backend"
            help: "how pywal16 picks colours; some need extra Python packages and fall back to the current palette if missing"

            Dropdown {
                options: Theme.backends.map(b => [b, b])
                value: Config.theme.backend
                onChosen: v => Theme.setBackend(v)
            }
        }
        Setting {
            label: "Opacity"
            help: "of the bar's islands and the panels; lower lets more of the wallpaper through"

            NumberField {
                value: Config.appearance.opacity
                from: 0.5
                to: 1
                step: 0.05
                onEdited: v => Config.set("appearance.opacity", v)
            }
        }
    }
}
