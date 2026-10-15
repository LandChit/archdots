import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services
import qs.widgets

// Cheatsheet of every bind Hyprland has right now, read from `hyprctl binds
// -j` each time it opens, so binds added in ~/.config/simplychit/hypr/keybind.lua
// appear with no change here.
//
// Under the Lua config every bind is an opaque `__lua` callback: the combo is
// knowable, the action is not. Only `desc` survives, by convention
// "Group: Label"; the group becomes a heading. Binds without one are listed
// under Undescribed, so a new bind shows up even before it is named.
Panel {
    id: root

    name: "keybinds"
    layer: WlrLayer.Overlay
    closeOnOutsideClick: false
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property var groups: []
    property int total: 0

    readonly property var mods: [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
    readonly property var keyNames: ({ RETURN: "Enter", KP_ENTER: "Enter", ESCAPE: "Esc", PRINT: "PrtSc", SLASH: "/", PERIOD: ".", COMMA: ",", SPACE: "Space", GRAVE: "`", MINUS: "-", TAB: "Tab", BACKSPACE: "Backspace", DELETE: "Del", left: "←", right: "→", up: "↑", down: "↓", "mouse:272": "Left click", "mouse:273": "Right click", mouse_up: "Scroll up", mouse_down: "Scroll down" })
    readonly property var xf86Names: ({ AudioRaiseVolume: "Vol +", AudioLowerVolume: "Vol −", AudioMute: "Mute", AudioMicMute: "Mic mute", MonBrightnessUp: "Bright +", MonBrightnessDown: "Bright −", AudioNext: "Next", AudioPrev: "Prev", AudioPlay: "Play", AudioPause: "Pause" })

    function prettyKey(key: string): string {
        if (keyNames[key] !== undefined)
            return keyNames[key];
        if (key.startsWith("XF86"))
            return xf86Names[key.slice(4)] ?? key.slice(4);
        return key.length === 1 ? key.toUpperCase() : key;
    }

    function combo(bind: var): var {
        const tokens = mods.filter(([bit]) => (bind.modmask ?? 0) & bit).map(([, name]) => name);
        tokens.push(prettyKey(bind.key ?? ""));
        return tokens;
    }

    // Ten workspace binds share one description; fold SUPER+1…0 and the four
    // arrows into one row each, and leave anything else as it is.
    function collapse(combos: var): var {
        if (combos.length < 3)
            return combos;
        const mod = c => c.slice(0, -1).join("+");
        if (combos.some(c => mod(c) !== mod(combos[0])))
            return combos;
        const keys = combos.map(c => c[c.length - 1]);
        if (keys.every(k => /^\d$/.test(k)))
            return [combos[0].slice(0, -1).concat([keys[0] + "…" + keys[keys.length - 1]])];
        if (keys.every(k => "←→↑↓".includes(k) && k.length === 1))
            return [combos[0].slice(0, -1).concat([keys.join("")])];
        return combos;
    }

    function load(text: string): void {
        let binds;
        try {
            binds = JSON.parse(text);
        } catch (e) {
            binds = [];
        }
        const byGroup = {};
        const order = [];
        let count = 0;
        for (const bind of binds) {
            if (bind.submap)
                continue;
            const description = (bind.description ?? "").trim();
            let group = "Undescribed", label = "—";
            if (description !== "") {
                const colon = description.indexOf(":");
                group = colon < 0 ? "Other" : description.slice(0, colon).trim();
                label = colon < 0 ? description : description.slice(colon + 1).trim();
            }
            if (!byGroup[group]) {
                byGroup[group] = {};
                order.push(group);
            }
            (byGroup[group][label] = byGroup[group][label] ?? []).push(combo(bind));
            count++;
        }
        order.sort((a, b) => (a === "Undescribed") - (b === "Undescribed"));
        groups = order.map(g => ({ name: g, rows: Object.keys(byGroup[g]).map(l => ({ label: l, combos: collapse(byGroup[g][l]) })) }));
        total = count;
    }

    onOpened: {
        reader.running = true;
        keys.forceActiveFocus();
    }

    Process {
        id: reader

        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.load(text)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.scrim
        opacity: root.reveal

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Slash || event.key === Qt.Key_Q) {
                root.close();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 3 * 380 + 2 * 24 + 48)
        height: Math.min(parent.height - 80, 820)
        opacity: root.reveal
        scale: 0.97 + 0.03 * root.reveal
        radius: 20
        color: Colours.panel
        border.width: 1
        border.color: Colours.panelBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            RowLayout {
                BarText {
                    Layout.fillWidth: true
                    text: "Keybinds"
                    px: 17
                    font.weight: Font.Medium
                }
                BarText {
                    text: root.total + " binds · esc to close"
                    px: 11
                    color: Colours.hint
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: flow.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Flow {
                    id: flow

                    width: parent.width
                    spacing: 24

                    Repeater {
                        model: root.groups

                        ColumnLayout {
                            id: group

                            required property var modelData

                            width: 380
                            spacing: 4

                            BarText {
                                text: group.modelData.name
                                px: 11
                                font.weight: Font.Medium
                                color: Colours.accentBright
                                Layout.bottomMargin: 2
                            }

                            Repeater {
                                model: group.modelData.rows

                                RowLayout {
                                    id: row

                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: 8

                                    BarText {
                                        Layout.fillWidth: true
                                        text: row.modelData.label
                                        px: 12
                                        elide: Text.ElideRight
                                    }

                                    Repeater {
                                        model: row.modelData.combos

                                        Row {
                                            id: comboRow

                                            required property var modelData

                                            spacing: 3

                                            Repeater {
                                                model: comboRow.modelData

                                                Rectangle {
                                                    required property string modelData

                                                    implicitWidth: keyText.implicitWidth + 10
                                                    implicitHeight: 20
                                                    radius: 5
                                                    color: Colours.alpha(Colours.accent, 0.14)
                                                    border.width: 1
                                                    border.color: Colours.alpha(Colours.accent, 0.30)

                                                    BarText {
                                                        id: keyText

                                                        anchors.centerIn: parent
                                                        text: parent.modelData
                                                        px: 10.5
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
