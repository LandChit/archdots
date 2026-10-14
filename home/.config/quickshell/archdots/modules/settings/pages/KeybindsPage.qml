import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.widgets

// Every default keybind, from the list hypr/config/keybind.lua writes to
// ~/.cache/archdots/keybinds.json each time it loads. A change is data in
// settings.json ("keybinds.remap": id -> keys, "keybinds.disabled": ids) and
// takes effect when Hyprland's config is reloaded. Binds of your own stay in
// ~/.config/archdots/hypr/keybind.lua.
ColumnLayout {
    id: page

    spacing: 14

    property var binds: []
    property string capturing: ""
    property string filter: ""

    readonly property var remap: Config.keybinds.remap ?? {}
    readonly property var disabled: Config.keybinds.disabled

    function keysOf(b: var): string {
        return remap[b.id] ?? b.default;
    }

    function setRemap(id: string, keys: string): void {
        const next = Object.assign({}, remap);
        const bind = binds.find(b => b.id === id);
        if (keys === "" || (bind && keys === bind.default))
            delete next[id];
        else
            next[id] = keys;
        Config.set("keybinds.remap", next);
    }

    function setDisabled(id: string, off: bool): void {
        const list = disabled.filter(d => d !== id);
        Config.set("keybinds.disabled", off ? list.concat([id]) : list);
    }

    // Hyprland's spelling: "SUPER + SHIFT + E"
    function comboFrom(event: var): string {
        const named = {
            [Qt.Key_Return]: "RETURN", [Qt.Key_Enter]: "RETURN", [Qt.Key_Space]: "SPACE", [Qt.Key_Tab]: "TAB",
            [Qt.Key_Backspace]: "BACKSPACE", [Qt.Key_Delete]: "DELETE", [Qt.Key_Escape]: "ESCAPE", [Qt.Key_Print]: "PRINT",
            [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
            [Qt.Key_Slash]: "SLASH", [Qt.Key_Period]: "PERIOD", [Qt.Key_Comma]: "COMMA", [Qt.Key_Minus]: "MINUS",
            [Qt.Key_Equal]: "EQUAL", [Qt.Key_Semicolon]: "SEMICOLON", [Qt.Key_Home]: "HOME", [Qt.Key_End]: "END",
            [Qt.Key_PageUp]: "PRIOR", [Qt.Key_PageDown]: "NEXT", [Qt.Key_Insert]: "INSERT"
        };
        const k = event.key;
        let key = named[k] ?? "";
        if (key === "" && k >= Qt.Key_A && k <= Qt.Key_Z)
            key = String.fromCharCode(k);
        else if (key === "" && k >= Qt.Key_0 && k <= Qt.Key_9)
            key = String.fromCharCode(k);
        else if (key === "" && k >= Qt.Key_F1 && k <= Qt.Key_F24)
            key = "F" + (k - Qt.Key_F1 + 1);
        if (key === "")
            return "";
        const mods = [];
        if (event.modifiers & Qt.MetaModifier)
            mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier)
            mods.push("CONTROL");
        if (event.modifiers & Qt.AltModifier)
            mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier)
            mods.push("SHIFT");
        return mods.concat([key]).join(" + ");
    }

    function normal(keys: string): string {
        return keys.toUpperCase().replace(/\s+/g, "").split("+").sort().join("+");
    }

    function conflicts(b: var): var {
        const mine = normal(keysOf(b));
        return binds.filter(o => o.id !== b.id && !disabled.includes(o.id) && normal(keysOf(o)) === mine);
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/archdots/keybinds.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                page.binds = JSON.parse(text());
            } catch (e) {
                page.binds = [];
            }
        }
    }

    PageTitle {
        title: "Keybinds"
        description: "Change or turn off a default. Combos Hyprland already uses go to that bind, not to this window, so type those in instead of pressing them. Changes apply when Hyprland's config is reloaded."
    }

    RowLayout {
        spacing: 8

        TextField {
            fieldWidth: 260
            placeholder: "Filter…"
            value: page.filter
            onEdited: v => page.filter = v
        }
        Button {
            primary: true
            text: "Apply now (reload Hyprland)"
            onClicked: Quickshell.execDetached(["hyprctl", "reload"])
        }
    }

    BarText {
        visible: page.binds.length === 0
        text: "The list appears once Hyprland has loaded this config (~/.cache/archdots/keybinds.json)."
        color: Colours.subtext
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    Repeater {
        model: [...new Set(page.binds.map(b => b.desc.split(":")[0]))]

        Section {
            id: group

            required property string modelData

            title: modelData
            visible: page.binds.some(b => b.desc.startsWith(modelData + ":") && (page.filter === "" || (b.desc + " " + page.keysOf(b)).toLowerCase().includes(page.filter.toLowerCase())))

            Repeater {
                model: page.binds.filter(b => b.desc.startsWith(group.modelData + ":"))

                Setting {
                    id: row

                    required property var modelData
                    readonly property bool off: page.disabled.includes(modelData.id)
                    readonly property bool changed: page.remap[modelData.id] !== undefined
                    readonly property var clash: page.conflicts(modelData)

                    visible: page.filter === "" || (modelData.desc + " " + page.keysOf(modelData)).toLowerCase().includes(page.filter.toLowerCase())
                    label: modelData.desc.slice(modelData.desc.indexOf(":") + 1).trim() + (off ? "  (off)" : "")
                    help: modelData.id + (changed ? " · default " + modelData.default : "")
                        + (clash.length > 0 ? " · same keys as " + clash.map(c => c.id).join(", ") : "")

                    RowLayout {
                        spacing: 6

                        // the keys: shown, typed, or captured
                        Rectangle {
                            implicitWidth: 230
                            implicitHeight: 30
                            radius: 9
                            color: page.capturing === row.modelData.id ? Colours.alpha(Colours.accentBright, 0.20) : Colours.alpha(Colours.accent, 0.08)
                            border.width: 1
                            border.color: row.clash.length > 0 ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 0.7) : page.capturing === row.modelData.id ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.22)
                            opacity: row.off ? 0.5 : 1

                            TextInput {
                                id: keys

                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colours.foreground
                                font.family: "JetBrainsMono NF"
                                font.pointSize: 11 * 0.75
                                text: page.capturing === row.modelData.id ? "press keys… (Esc cancels)" : page.keysOf(row.modelData)
                                readOnly: page.capturing === row.modelData.id
                                onEditingFinished: {
                                    if (page.capturing !== row.modelData.id && text !== page.keysOf(row.modelData))
                                        page.setRemap(row.modelData.id, text.trim());
                                }
                                Keys.onPressed: event => {
                                    if (page.capturing !== row.modelData.id)
                                        return;
                                    event.accepted = true;
                                    if (event.key === Qt.Key_Escape) {
                                        page.capturing = "";
                                        return;
                                    }
                                    const combo = page.comboFrom(event);
                                    if (combo !== "") {
                                        page.capturing = "";
                                        page.setRemap(row.modelData.id, combo);
                                    }
                                }
                            }
                        }
                        Button {
                            text: "Press…"
                            onClicked: {
                                page.capturing = row.modelData.id;
                                keys.forceActiveFocus();
                            }
                        }
                        Button {
                            text: row.off ? "Turn on" : "Turn off"
                            onClicked: page.setDisabled(row.modelData.id, !row.off)
                        }
                        Button {
                            text: "Reset"
                            enabled: row.changed
                            onClicked: page.setRemap(row.modelData.id, "")
                        }
                    }
                }
            }
        }
    }
}
