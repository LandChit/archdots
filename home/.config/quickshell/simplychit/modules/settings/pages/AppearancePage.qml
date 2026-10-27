import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

ColumnLayout {
    id: page

    // The screen the thumbnails pick for, with a wallpaper per screen; the
    // primary one until another is chosen.
    property string screen: ""
    readonly property bool perScreen: Config.wallpaper.perMonitor && Quickshell.screens.length > 1
    readonly property string target: !perScreen ? "" : Quickshell.screens.some(s => s.name === screen) ? screen : Screens.primary ? Screens.primary.name : ""
    readonly property string shown: target !== "" ? Theme.wallpaperFor(target) : Theme.current

    spacing: 14

    Component.onCompleted: Theme.rescan()

    PageTitle {
        title: "Appearance"
        description: "Everything is coloured from the wallpaper by pywal16. Changes apply straight away."
    }

    Section {
        title: "Wallpaper"

        Setting {
            label: "A wallpaper per screen"
            help: "pick each screen's on its own; the colours come from the primary screen's (Displays)"

            Switch {
                checked: Config.wallpaper.perMonitor
                onToggled: v => Config.set("wallpaper.perMonitor", v)
            }
        }
        Setting {
            visible: page.perScreen
            label: "Screen"
            help: "the one the wallpapers below are for"

            Choice {
                options: Quickshell.screens.map(s => [s.name, Screens.primary && s.name === Screens.primary.name ? s.name + " (primary)" : s.name])
                value: page.target
                onChosen: v => page.screen = v
            }
        }
        Setting {
            label: page.target !== "" ? "Wallpaper on " + page.target : "Current wallpaper"
            help: page.shown === "" ? "none yet" : page.shown.replace(Quickshell.env("HOME"), "~")

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
        Flow {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 8

            Repeater {
                model: Theme.available

                Rectangle {
                    id: thumb

                    required property string modelData
                    readonly property bool active: modelData === page.shown

                    width: 132
                    height: 74
                    radius: 9
                    color: Colours.alpha(Colours.accent, 0.12)
                    border.width: active ? 2 : 1
                    border.color: active ? Colours.accentBright : thumbArea.containsMouse ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.18)

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + thumb.modelData
                        sourceSize: Qt.size(264, 148)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MouseArea {
                        id: thumbArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.target !== "")
                                Theme.setFor(page.target, thumb.modelData);
                            else
                                Theme.apply(thumb.modelData);
                        }
                    }
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
