import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The bar's layout: one default, and per screen either the default or a
// layout of its own (bar.monitors, keyed by the monitor's description so it
// follows the monitor to another port). Rules in services/BarLayout.qml.
ColumnLayout {
    id: page

    spacing: 14

    // "" is the default layout, else a connected screen's port name
    property string scope: ""

    readonly property var screen: scope === "" ? null : Quickshell.screens.find(s => s.name === scope) ?? null
    // the bar.monitors entry this screen uses, or the one a change would make:
    // Hyprland's description of it, else the port name
    readonly property string screenKey: {
        if (!screen)
            return "";
        const existing = BarLayout.keyFor(screen);
        if (existing !== "")
            return existing;
        const monitor = Displays.monitors.find(m => m.name === screen.name);
        return monitor && monitor.description ? monitor.description : screen.name;
    }
    readonly property var override: screen ? BarLayout.overrideFor(screen) : ({})
    readonly property bool ownLayout: screen !== null && BarLayout.hasOwnLayout(override)
    readonly property bool editable: scope === "" || ownLayout
    // what is shown and edited: { left, center, right }
    readonly property var layout: ownLayout ? BarLayout.layoutFor(screen) : defaultLayout
    readonly property var defaultLayout: ({
        left: BarLayout.normalize(Config.bar.left),
        center: BarLayout.normalize(Config.bar.center),
        right: BarLayout.normalize(Config.bar.right)
    })
    readonly property var placed: [].concat(layout.left, layout.center, layout.right)

    function writeOverride(entry: var): void {
        const monitors = Object.assign({}, Config.bar.monitors ?? {});
        if (Object.keys(entry).length === 0)
            delete monitors[screenKey];
        else
            monitors[screenKey] = entry;
        Config.set("bar.monitors", monitors);
    }

    function save(next: var): void {
        if (scope === "") {
            for (const [s] of BarLayout.sections)
                if (JSON.stringify(next[s]) !== JSON.stringify(defaultLayout[s]))
                    Config.set("bar." + s, next[s]);
        } else {
            writeOverride(Object.assign({}, override, next));
        }
    }

    function copyLayout(): var {
        return { left: Array.from(layout.left), center: Array.from(layout.center), right: Array.from(layout.right) };
    }

    // by -1 / +1 within a section; past either end it moves into the
    // neighbouring section. by 0 takes it off the bar.
    function move(section: string, name: string, by: int): void {
        const next = copyLayout();
        const order = BarLayout.sections.map(s => s[0]);
        const list = next[section];
        const i = list.indexOf(name);
        list.splice(i, 1);
        if (by !== 0) {
            const j = i + by;
            if (j >= 0 && j <= list.length) {
                list.splice(j, 0, name);
            } else {
                const k = order.indexOf(section) + (by < 0 ? -1 : 1);
                if (k < 0 || k >= order.length)
                    return;
                if (by < 0)
                    next[order[k]].push(name);
                else
                    next[order[k]].unshift(name);
            }
        }
        save(next);
    }

    // The old show switches would keep a widget hidden after adding it.
    function add(section: string, name: string): void {
        const next = copyLayout();
        next[section].push(name);
        const flag = ({ media: "showMedia", cpu: "showCpu", battery: "showBattery" })[name];
        if (scope === "") {
            save(next);
            if (flag && Config.bar[flag] === false)
                Config.set("bar." + flag, true);
            return;
        }
        const entry = Object.assign({}, override, next);
        if (flag && (override[flag] ?? Config.bar[flag]) === false)
            entry[flag] = true;
        writeOverride(entry);
    }

    function setOwnLayout(on: bool): void {
        const entry = Object.assign({}, override);
        for (const [s] of BarLayout.sections)
            delete entry[s];
        if (on)
            Object.assign(entry, {
                left: Array.from(defaultLayout.left),
                center: Array.from(defaultLayout.center),
                right: Array.from(defaultLayout.right)
            });
        writeOverride(entry);
    }

    function setBarOn(screen: var, on: bool): void {
        const list = Config.bar.excluded.filter(k => !Screens.matches(screen, k));
        if (!on) {
            const monitor = Displays.monitors.find(m => m.name === screen.name);
            list.push(monitor && monitor.description ? monitor.description : screen.name);
        }
        Config.set("bar.excluded", list);
    }

    component WidgetSection: Section {
        id: section

        property string key

        Repeater {
            model: page.layout[section.key]

            Setting {
                required property string modelData
                required property int index

                label: BarLayout.widgets[modelData] ?? modelData

                RowLayout {
                    spacing: 6

                    Button {
                        text: "\u{f0141}"
                        enabled: page.editable && !(section.key === "left" && index === 0)
                        onClicked: page.move(section.key, modelData, -1)
                    }
                    Button {
                        text: "\u{f0142}"
                        enabled: page.editable && !(section.key === "right" && index === page.layout.right.length - 1)
                        onClicked: page.move(section.key, modelData, 1)
                    }
                    Button {
                        text: "Remove"
                        enabled: page.editable
                        onClicked: page.move(section.key, modelData, 0)
                    }
                }
            }
        }

        Setting {
            visible: page.editable && page.layout[section.key].length === 0 && addRow.missing.length === 0
            label: "Empty"
            help: "move a widget here with its arrows"
        }

        Setting {
            id: addRow

            readonly property var missing: Object.keys(BarLayout.widgets).filter(n => !page.placed.includes(n))

            visible: page.editable && missing.length > 0
            label: page.layout[section.key].length === 0 ? "Empty: add a widget" : "Add a widget"
            help: "at the end of this section"

            Dropdown {
                fieldWidth: 240
                options: addRow.missing.map(n => [n, BarLayout.widgets[n]])
                value: ""
                onChosen: v => page.add(section.key, v)
            }
        }
    }

    PageTitle {
        title: "Bar"
        description: "One default layout for every screen; any screen can have its own instead. Widgets next to each other among indicators, volume, CPU and battery share one island."
    }

    Section {
        title: "Layout for"

        Setting {
            label: "Screen"
            help: page.scope === "" ? "every screen without a layout of its own" : (page.screen ? page.screen.model : "")

            Dropdown {
                fieldWidth: 240
                options: [["", "Default"]].concat(Quickshell.screens.map(s => [s.name, s.name + (s.model ? " · " + s.model : "") + (BarLayout.hasOwnLayout(BarLayout.overrideFor(s)) ? " (own)" : "")]))
                value: page.scope
                onChosen: v => page.scope = v
            }
        }
        Setting {
            visible: page.screen !== null
            label: "Use the default layout"
            help: page.ownLayout ? "off: this screen has its own, below" : "on: change the default to change this screen"

            Switch {
                checked: !page.ownLayout
                onToggled: v => page.setOwnLayout(!v)
            }
        }
    }

    WidgetSection {
        title: "Left"
        description: page.editable ? "Left to right. Moving one past either end puts it in the next section." : "The default layout, as this screen shows it."
        key: "left"
    }
    WidgetSection {
        title: "Centre"
        key: "center"
    }
    WidgetSection {
        title: "Right"
        key: "right"
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
                    checked: !BarLayout.isExcluded(modelData)
                    onToggled: v => page.setBarOn(modelData, v)
                }
            }
        }
    }
}
