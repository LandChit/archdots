import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// Clipboard history from cliphist. Enter copies the entry back, Delete
// removes it from the history.
//
// Image entries get real thumbnails: each is decoded once into
// $XDG_RUNTIME_DIR/archdots-clipboard/ (tmpfs, gone at logout) and loaded
// asynchronously, so large images no longer stall the panel or fall back to
// a generic icon as they did in fabric. The selected image is also shown
// large under the list.
//
// cliphist's own "id<TAB>preview" line is what it wants back to decode or
// delete an entry. It is passed as an argument ("$1"), never pasted into
// the shell text, so nothing in a clipboard entry can run as a command.
ListPanel {
    id: root

    name: "clipboard"
    glyph: "\u{f014c}"
    placeholder: "Search clipboard…"
    hints: ["↕ navigate", "↵ copy", "del delete", "esc close"]
    panelWidth: 520
    listHeight: selectedImage !== "" ? 300 : 520

    readonly property string cacheDir: Quickshell.env("XDG_RUNTIME_DIR") + "/archdots-clipboard"
    property var history: []
    readonly property var selected: list.showSelection && list.currentIndex >= 0 ? items[list.currentIndex] : null
    readonly property string selectedImage: selected && selected.isImage ? selected.file : ""

    function parse(text: string): var {
        const rows = [];
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t");
            if (tab < 0)
                continue;
            const id = line.slice(0, tab);
            const preview = line.slice(tab + 1);
            const binary = preview.match(/^\[\[ binary data .*?(\w+)(?: (\d+x\d+))? \]\]/);
            const format = binary ? binary[1].toLowerCase() : "";
            const isImage = binary !== null && ["png", "jpeg", "jpg", "gif", "webp", "bmp"].includes(format);
            rows.push({
                line: line,
                id: id,
                preview: preview,
                isImage: isImage,
                format: format,
                file: isImage ? cacheDir + "/" + id + "." + format : "",
                title: isImage ? "Image · " + format + (binary[2] ? " · " + binary[2] : "") : preview.replace(/\s+/g, " ").slice(0, 200)
            });
        }
        return rows;
    }

    function filter(): void {
        const needle = query.trim().toLowerCase();
        items = needle === "" ? history : history.filter(r => r.preview.toLowerCase().includes(needle));
    }

    function remove(row: var): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "sh", row.line]);
        history = history.filter(r => r.id !== row.id);
        filter();
    }

    onOpened: {
        items = [];
        lister.running = true;
    }
    onQueryChanged: Qt.callLater(filter)
    onActivated: (row, modifiers) => {
        const type = row.isImage ? " --type image/" + (row.format === "jpg" ? "jpeg" : row.format) : "";
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy" + type, "sh", row.line]);
        close();
    }
    onOtherKey: event => {
        if (event.key !== Qt.Key_Delete || !list.showSelection)
            return;
        const row = items[list.currentIndex];
        if (row)
            remove(row);
        event.accepted = true;
    }

    Process {
        id: lister

        command: ["sh", "-c", "mkdir -p \"$1\" && cliphist list", "sh", root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.history = root.parse(text);
                root.filter();
            }
        }
    }

    delegate: Rectangle {
        id: row

        required property var modelData
        required property int index
        readonly property bool selectedRow: ListView.isCurrentItem && ListView.view.showSelection
        property bool decoded: false

        width: ListView.view.width
        implicitHeight: modelData.isImage ? 64 : 44
        radius: 12
        color: selectedRow ? Colours.selection : area.containsMouse ? Colours.hover : "transparent"
        border.width: 1
        border.color: selectedRow ? Colours.selectionBorder : "transparent"

        // Decode this image once, the first time its row is built.
        Process {
            running: row.modelData.isImage
            command: ["sh", "-c", "[ -s \"$2\" ] || printf '%s' \"$1\" | cliphist decode > \"$2\"", "sh", row.modelData.line, row.modelData.file]
            onExited: row.decoded = true
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                implicitWidth: row.modelData.isImage ? 48 : 28
                implicitHeight: row.modelData.isImage ? 48 : 28
                radius: 8
                color: Colours.alpha(Colours.accent, 0.12)
                clip: true

                Image {
                    anchors.fill: parent
                    visible: row.modelData.isImage
                    source: row.decoded ? "file://" + row.modelData.file : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
                BarText {
                    anchors.centerIn: parent
                    visible: !row.modelData.isImage
                    text: "\u{f018f}"
                    px: 14
                    color: Colours.alpha(Colours.foreground, 0.7)
                }
            }

            BarText {
                Layout.fillWidth: true
                text: row.modelData.title
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.ListView.view.clickedRow(row.index)
        }
    }

    // The selected image, large.
    Rectangle {
        y: root.list.height + 8
        width: parent.width
        height: 210
        visible: root.selectedImage !== ""
        radius: 12
        color: Colours.alpha(Colours.accent, 0.08)

        Image {
            anchors.fill: parent
            anchors.margins: 6
            source: root.selectedImage !== "" ? "file://" + root.selectedImage : ""
            sourceSize: Qt.size(960, 420)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }
    }
}
