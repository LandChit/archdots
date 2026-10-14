import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

ColumnLayout {
    id: page

    spacing: 14

    readonly property var islandNames: ({
        workspaces: "Workspaces",
        special: "Special workspaces",
        title: "Window title",
        media: "What's playing",
        resources: "Status and meters",
        clock: "Clock"
    })

    // moves `name` within bar.<side> by `by`, or into the other side when it
    // runs off the end; by = 0 takes it off the bar
    function moveIsland(side: string, name: string, by: int): void {
        const other = side === "left" ? "right" : "left";
        const list = Array.from(Config.bar[side]);
        const i = list.indexOf(name);
        list.splice(i, 1);
        if (by === 0) {
            Config.set("bar." + side, list);
            return;
        }
        const j = i + by;
        if (j >= 0 && j <= list.length) {
            list.splice(j, 0, name);
            Config.set("bar." + side, list);
            return;
        }
        // off the inner end of the left side, or the inner start of the right
        const otherList = Array.from(Config.bar[other]);
        if (side === "left")
            otherList.unshift(name);
        else
            otherList.push(name);
        Config.set("bar." + side, list);
        Config.set("bar." + other, otherList);
    }

    function addIsland(name: string): void {
        Config.set("bar.right", Array.from(Config.bar.right).concat([name]));
    }

    component IslandList: Section {
        id: list

        property string side

        Repeater {
            model: Config.bar[list.side]

            Setting {
                required property string modelData
                required property int index

                label: page.islandNames[modelData] ?? modelData
                help: page.islandNames[modelData] ? "" : "not an island this bar knows; it is skipped"

                RowLayout {
                    spacing: 6

                    Button {
                        text: "\u{f0141}"
                        enabled: list.side === "right" || index > 0
                        onClicked: page.moveIsland(list.side, modelData, -1)
                    }
                    Button {
                        text: "\u{f0142}"
                        enabled: list.side === "left" || index < Config.bar[list.side].length - 1
                        onClicked: page.moveIsland(list.side, modelData, 1)
                    }
                    Button {
                        text: "Remove"
                        onClicked: page.moveIsland(list.side, modelData, 0)
                    }
                }
            }
        }
    }

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

    IslandList {
        title: "Left side"
        description: "Left to right. Moving one past the end puts it on the other side."
        side: "left"
    }

    IslandList {
        title: "Right side"
        side: "right"

        Setting {
            id: addRow

            readonly property var missing: Object.keys(page.islandNames).filter(n => !Config.bar.left.includes(n) && !Config.bar.right.includes(n))

            visible: missing.length > 0
            label: "Add an island"
            help: "it goes at the right end"

            Dropdown {
                fieldWidth: 200
                options: addRow.missing.map(n => [n, page.islandNames[n]])
                value: ""
                onChosen: v => page.addIsland(v)
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
