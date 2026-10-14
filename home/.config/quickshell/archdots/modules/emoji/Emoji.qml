import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// Emoji grid with a group rail, most-used first. Enter or a click copies.
// ↑↓ move by row; ←→ move while the search is empty; PgUp/PgDn change group.
//
// The data is the JSON fabric used (unicode-emoji-json), cached at
// ~/.cache/emoji-picker/; downloaded once if it is missing.
SearchPanel {
    id: root

    name: "emoji"
    glyph: "\u{f0785}"
    placeholder: "Search emoji…"
    hints: ["↕↔ navigate", "↵ copy", "pgup/pgdn group", "esc close"]
    panelWidth: 7 * 46 + 52 + 40

    readonly property string dataFile: Quickshell.env("HOME") + "/.cache/emoji-picker/data-by-emoji.json"
    readonly property string dataUrl: "https://raw.githubusercontent.com/LandChit/unicode-emoji-json/refs/heads/main/data-by-emoji.json"
    readonly property var groups: [["All", "\u{f0570}"], ["Smileys & Emotion", "\u{f01f5}"], ["People & Body", "\u{f0004}"], ["Animals & Nature", "\u{f03e9}"], ["Food & Drink", "\u{f025a}"], ["Travel & Places", "\u{f001d}"], ["Activities", "\u{f0538}"], ["Objects", "\u{f0335}"], ["Symbols", "\u{f0b34}"], ["Flags", "\u{f023b}"]]
    readonly property int columns: 7

    property var emoji: []
    property var shown: []
    property string group: "All"
    property bool moved: false

    function load(text: string): void {
        try {
            const data = JSON.parse(text);
            emoji = Object.keys(data).map((char, i) => ({ char: char, name: data[char].name, group: data[char].group || "", order: i }));
        } catch (e) {
            emoji = [];
        }
        refilter();
    }

    function refilter(): void {
        const needle = query.trim().toLowerCase();
        const list = emoji.filter(e => (group === "All" || e.group === group) && (needle === "" || e.name.includes(needle)));
        list.sort((a, b) => usage.count(b.char) - usage.count(a.char) || a.order - b.order);
        shown = list;
        grid.currentIndex = 0;
        moved = false;
        grid.positionViewAtBeginning();
    }

    function move(delta: int): void {
        if (shown.length === 0)
            return;
        moved = true;
        grid.currentIndex = Math.max(0, Math.min(shown.length - 1, grid.currentIndex + delta));
    }

    function pick(index: int): void {
        const e = shown[index];
        if (!e)
            return;
        usage.bump(e.char);
        Quickshell.clipboardText = e.char;
        close();
    }

    function stepGroup(delta: int): void {
        const names = groups.map(g => g[0]);
        group = names[(names.indexOf(group) + delta + names.length) % names.length];
        refilter();
    }

    onOpened: {
        group = "All";
        if (emoji.length === 0)
            data.reload();
        else
            refilter();
    }
    onQueryChanged: Qt.callLater(refilter)
    onMoveUp: move(-columns)
    onMoveDown: move(columns)
    onMoveLeft: move(-1)
    onMoveRight: move(1)
    onAccepted: pick(grid.currentIndex)
    onOtherKey: event => {
        if (event.key === Qt.Key_PageDown)
            stepGroup(1);
        else if (event.key === Qt.Key_PageUp)
            stepGroup(-1);
        else
            return;
        event.accepted = true;
    }

    UsageCounts {
        id: usage

        file: "emoji"
        importFrom: Quickshell.env("HOME") + "/.local/share/fabric-launcher/emoji-counts.json"
    }

    FileView {
        id: data

        path: root.dataFile
        printErrors: false
        onLoaded: root.load(text())
        onLoadFailed: download.running = true
    }

    Process {
        id: download

        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && curl -fsSL \"$2\" -o \"$1.part\" && mv \"$1.part\" \"$1\"", "sh", root.dataFile, root.dataUrl]
        onExited: code => {
            if (code === 0)
                data.reload();
        }
    }

    RowLayout {
        width: parent.width
        spacing: 8

        GridView {
            id: grid

            Layout.preferredWidth: root.columns * 46
            Layout.preferredHeight: 440
            cellWidth: 46
            cellHeight: 46
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0

            delegate: Rectangle {
                id: cell

                required property var modelData
                required property int index
                readonly property bool selected: GridView.isCurrentItem && root.moved

                width: 44
                height: 44
                radius: 10
                color: selected ? Colours.selection : area.containsMouse ? Colours.hover : "transparent"
                border.width: 1
                border.color: selected ? Colours.selectionBorder : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.char
                    font.pointSize: 18
                    font.family: "Noto Color Emoji"
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pick(cell.index)
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 3

            Repeater {
                model: root.groups

                Rectangle {
                    required property var modelData

                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 10
                    color: root.group === modelData[0] ? Colours.selection : railArea.containsMouse ? Colours.hover : "transparent"
                    border.width: 1
                    border.color: root.group === modelData[0] ? Colours.selectionBorder : "transparent"

                    BarText {
                        anchors.centerIn: parent
                        text: parent.modelData[1]
                        px: 17
                        color: Colours.alpha(Colours.foreground, 0.85)
                    }

                    MouseArea {
                        id: railArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.group = parent.modelData[0];
                            root.refilter();
                        }
                    }
                }
            }
        }
    }

}
