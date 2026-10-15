import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// The first-run welcome (services/FirstRun.qml): a few steps through the
// choices that matter on day one, each a shortcut into settings.json like the
// settings app's pages, then the keybinds worth knowing. Keyboard and app
// changes reach Hyprland when it reloads, which Finish does if any were made.
FloatingWindow {
    id: root

    readonly property var steps: [["welcome", "Welcome"], ["look", "Look"], ["input", "Keyboard"], ["apps", "Apps"], ["keys", "Keys"]]
    property int step: 0
    // set by a keyboard or app change; Finish then reloads Hyprland
    property bool reloadNeeded: false

    function finish(): void {
        if (reloadNeeded)
            Quickshell.execDetached(["hyprctl", "reload"]);
        FirstRun.done();
    }

    title: "SimplyChit welcome"
    visible: FirstRun.open
    implicitWidth: 760
    implicitHeight: 560
    minimumSize: Qt.size(640, 480)
    color: Colours.mix(Colours.background, Colours.accent, 0.08)

    // closed from the title bar or a keybind: done too, just without the reload
    onVisibleChanged: {
        if (!visible && FirstRun.open)
            FirstRun.done();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 18

        // where you are
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.steps

                RowLayout {
                    id: crumb

                    required property var modelData
                    required property int index

                    spacing: 8

                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: 11
                        color: crumb.index <= root.step ? Colours.alpha(Colours.accentBright, 0.32) : "transparent"
                        border.width: 1
                        border.color: crumb.index === root.step ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.3)

                        BarText {
                            anchors.centerIn: parent
                            text: crumb.index + 1
                            px: 10
                        }
                    }
                    BarText {
                        text: crumb.modelData[1]
                        color: crumb.index === root.step ? Colours.foreground : Colours.subtext
                    }
                    Rectangle {
                        visible: crumb.index < root.steps.length - 1
                        implicitWidth: 18
                        implicitHeight: 1
                        color: Colours.alpha(Colours.accent, 0.3)
                    }
                }
            }
        }

        Flickable {
            id: scroller

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: page.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Loader {
                id: page

                width: scroller.width
                sourceComponent: [welcomeStep, lookStep, inputStep, appsStep, keysStep][root.step]
                onSourceComponentChanged: scroller.contentY = 0
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                visible: root.step < root.steps.length - 1
                text: "Skip setup"
                onClicked: root.finish()
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                visible: root.step > 0
                text: "Back"
                onClicked: root.step--
            }
            Button {
                primary: true
                text: root.step === 0 ? "Get started" : root.step < root.steps.length - 1 ? "Next" : "Finish"
                onClicked: {
                    if (root.step < root.steps.length - 1)
                        root.step++;
                    else
                        root.finish();
                }
            }
        }
    }

    Component {
        id: welcomeStep

        ColumnLayout {
            spacing: 14

            PageTitle {
                title: "Welcome to SimplyChit"
                description: "A few choices to make this desktop yours: the wallpaper and colours, your keyboard, your apps, and the keys worth knowing. Each one can be changed again later in Settings."
            }
            BarText {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: "Everything is coloured from the wallpaper, so picking one is the biggest change you can make. Skip setup keeps the defaults; this window does not come back on its own, but the launcher's > Welcome opens it again."
                color: Colours.subtext
                wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: lookStep

        ColumnLayout {
            spacing: 14

            PageTitle {
                title: "Look"
                description: "The colours of the bar, panels, apps and terminal all follow the wallpaper."
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
            }
        }
    }

    Component {
        id: inputStep

        ColumnLayout {
            spacing: 14

            PageTitle {
                title: "Keyboard and touchpad"
                description: "Applied when you finish. More options, per device too, on the Input page in Settings."
            }
            Section {
                title: "Keyboard"

                Setting {
                    label: "Layouts"
                    help: "comma separated, e.g. us,de; to switch between several, add grp:alt_shift_toggle under Options on the Input page"
                    TextField {
                        value: Config.input.kb_layout
                        onEdited: v => {
                            Config.set("input.kb_layout", v);
                            root.reloadNeeded = true;
                        }
                    }
                }
            }
            Section {
                title: "Touchpad"

                Setting {
                    label: "Natural scrolling"
                    help: "content follows your fingers, as on a phone"
                    Switch {
                        checked: Config.input.touchpad.natural_scroll
                        onToggled: v => {
                            Config.set("input.touchpad.natural_scroll", v);
                            root.reloadNeeded = true;
                        }
                    }
                }
                Setting {
                    label: "Tap to click"
                    Switch {
                        checked: Config.input.touchpad.tap_to_click
                        onToggled: v => {
                            Config.set("input.touchpad.tap_to_click", v);
                            root.reloadNeeded = true;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: appsStep

        ColumnLayout {
            spacing: 14

            PageTitle {
                title: "Apps"
                description: "What the launch keys start: the command, as you would type it in a terminal. Applied when you finish."
            }
            Section {
                title: "Programs"

                Repeater {
                    model: [["terminal", "Terminal", "SUPER + Enter; also the drop-down terminal (SUPER + `)"], ["browser", "Browser", "SUPER + B"], ["fileManager", "File manager", "SUPER + E"]]

                    Setting {
                        id: program

                        required property var modelData

                        label: modelData[1]
                        help: modelData[2]
                        TextField {
                            fieldWidth: 280
                            value: Config.apps[program.modelData[0]]
                            onEdited: v => {
                                Config.set("apps." + program.modelData[0], v);
                                root.reloadNeeded = true;
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: keysStep

        ColumnLayout {
            id: keys

            // id -> what it is called here; the keys come from the binds as
            // they are now (keybind.lua's list, after remaps)
            readonly property var wanted: [["launcher", "Launcher: apps, files, calculator, > actions"], ["terminal", "Terminal"], ["scratchpad-terminal", "Drop-down terminal"], ["browser", "Browser"], ["file-manager", "Files"], ["control-centre", "Control centre: Wi-Fi, Bluetooth, sound"], ["notifications", "Notifications"], ["wallpaper", "Wallpaper"], ["settings", "Settings"], ["close", "Close a window"], ["power-menu", "Power menu"], ["cheatsheet", "Every keybind"]]
            readonly property var names: ({ RETURN: "Enter", SPACE: "Space", SLASH: "/", COMMA: ",", PERIOD: ".", ESCAPE: "Esc", GRAVE: "`", MINUS: "-", PRINT: "PrtSc", CONTROL: "Ctrl" })
            property var rows: []

            function load(text: string): void {
                let list;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    return;
                }
                rows = wanted.map(([id, label]) => {
                    const bind = list.find(b => b.id === id);
                    return bind && !bind.disabled ? { label: label, keys: bind.keys.split("+").map(k => k.trim()).map(k => names[k] ?? k) } : null;
                }).filter(r => r !== null);
            }

            spacing: 14

            FileView {
                path: Quickshell.env("HOME") + "/.cache/simplychit/keybinds.json"
                printErrors: false
                onLoaded: keys.load(text())
            }

            PageTitle {
                title: "Keys worth knowing"
                description: "SUPER is the Windows key. SUPER + / shows every keybind at any time, and the Keybinds page in Settings changes them."
            }

            Section {
                title: "Keybinds"

                Repeater {
                    model: keys.rows

                    Setting {
                        id: bind

                        required property var modelData

                        label: modelData.label

                        Row {
                            spacing: 4

                            Repeater {
                                model: bind.modelData.keys

                                Rectangle {
                                    id: keycap

                                    required property string modelData

                                    implicitWidth: Math.max(26, cap.implicitWidth + 14)
                                    implicitHeight: 24
                                    radius: 6
                                    color: Colours.alpha(Colours.accent, 0.12)
                                    border.width: 1
                                    border.color: Colours.alpha(Colours.accent, 0.3)

                                    BarText {
                                        id: cap

                                        anchors.centerIn: parent
                                        text: keycap.modelData
                                        px: 10.5
                                    }
                                }
                            }
                        }
                    }
                }
            }

            BarText {
                visible: keys.rows.length === 0
                text: "The list appears once Hyprland has loaded this config."
                color: Colours.hint
            }
        }
    }
}
