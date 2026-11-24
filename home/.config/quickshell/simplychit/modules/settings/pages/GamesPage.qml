import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// The games scratchpad: its options, your games, the shipped ones, and the
// apps answered "not a game". Every change is written to settings.json and
// applied at once (services/Games.qml).
ColumnLayout {
    id: page

    spacing: 14

    // open windows in no list, for "Add an open window": [[class, label], …]
    property var openWindows: []

    function option(key: string, on: bool): void {
        Games.write([["games." + key, on]]);
    }

    Process {
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {}
                const seen = {};
                page.openWindows = list.filter(c => {
                    const cls = c.class ?? "";
                    if (cls === "" || seen[cls] || Games.isListed(cls, c.title ?? "") || Games.launchers.includes(cls))
                        return false;
                    seen[cls] = true;
                    return true;
                }).map(c => [c.class, c.class + (c.title ? "  ·  " + c.title : "")]);
            }
        }
    }

    PageTitle {
        title: "Games"
        description: "Games open in their own scratchpad (SUPER+G shows or hides it), fullscreen, over whatever you were doing; hiding it leaves them running. SUPER+SHIFT+G sends any window there and back."
    }

    Section {
        title: "Behaviour"

        Setting {
            label: "Open on the primary screen"
            help: "games show on the primary screen (Displays) whichever screen has focus"
            Switch {
                checked: Config.games.primaryMonitor
                onToggled: v => page.option("primaryMonitor", v)
            }
        }
        Setting {
            label: "Ask about windows moved in"
            help: "a window sent to games that is in no list: add it to your games?"
            Switch {
                checked: Config.games.ask
                onToggled: v => page.option("ask", v)
            }
        }
        Setting {
            label: "Ask about games as they open"
            help: "a window that looks like a game (Wine, Steam, Lutris, Heroic, gamescope) and is in no list"
            Switch {
                checked: Config.games.detect
                onToggled: v => page.option("detect", v)
            }
        }
    }

    Section {
        title: "Your games"
        description: "Matched by window class, a regular expression (^…$ for an exact one; hyprctl clients shows a window's class). Fullscreen off opens one windowed."

        Repeater {
            model: Games.own

            Setting {
                required property var modelData
                required property int index

                label: modelData.name
                help: modelData.class + (modelData.title !== "" ? "  ·  title " + modelData.title : "")

                RowLayout {
                    spacing: 10

                    BarText {
                        text: "Fullscreen"
                        px: 11
                        color: Colours.subtext
                    }
                    Switch {
                        checked: modelData.fullscreen
                        onToggled: v => Games.setFullscreen(index, v)
                    }
                    Button {
                        text: "Remove"
                        onClicked: Games.remove(index)
                    }
                }
            }
        }

        Setting {
            visible: Games.own.length === 0
            label: "None yet"
            help: "add one below, or answer yes when asked"
        }

        Setting {
            visible: page.openWindows.length > 0
            label: "Add an open window"
            help: "by its exact class"

            Dropdown {
                fieldWidth: 300
                options: page.openWindows
                value: ""
                onChosen: v => {
                    Games.add(v, (page.openWindows.find(o => o[0] === v) ?? [v, v])[1].split("  ·  ").pop());
                    page.openWindows = page.openWindows.filter(o => o[0] !== v);
                }
            }
        }

        Setting {
            label: "Add by class"
            help: "a regular expression, Enter to add"

            TextField {
                fieldWidth: 300
                placeholder: "^Albion Online$"
                value: ""
                onEdited: v => {
                    if (v.trim() !== "")
                        Games.addEntry({ name: v.trim().replace(/^\^|\$$/g, ""), class: v.trim() });
                    value = "";
                }
            }
        }
    }

    Section {
        title: "Shipped games"
        description: "The list that comes with SimplyChit (~/.config/hypr/games.json). Switch one off to leave it where it opens."

        Repeater {
            model: Games.shipped.map(Games.entryOf).filter(e => e !== null)

            Setting {
                required property var modelData

                label: modelData.name
                help: modelData.class
                Switch {
                    checked: !Games.disabled.includes(modelData.name)
                    onToggled: v => Games.setDisabled(modelData.name, !v)
                }
            }
        }
    }

    Section {
        title: "Not games"
        description: "Apps you answered No for: not asked about again."

        Repeater {
            model: Games.ignored

            Setting {
                required property string modelData

                label: modelData

                RowLayout {
                    spacing: 6

                    Button {
                        text: "Add as a game"
                        onClicked: Games.add(modelData, modelData)
                    }
                    Button {
                        text: "Ask again"
                        onClicked: Games.unignore(modelData)
                    }
                }
            }
        }

        Setting {
            visible: Games.ignored.length === 0
            label: "None"
        }
    }
}
