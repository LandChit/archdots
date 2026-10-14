import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.widgets

// The wallpapers in Config.wallpaper.directory, newest first, with
// thumbnails. Enter sets one everywhere and recolours everything from it;
// Shift+Enter sets it on the focused screen only.
ListPanel {
    id: root

    name: "wallpaper"
    glyph: "\u{f0e09}"
    placeholder: "Search wallpapers"
    hints: ["↕ navigate", "↵ apply", "⇧↵ this screen only", "esc close"]
    listHeight: 470

    function filter(): void {
        const needle = query.trim().toLowerCase();
        items = Theme.available.filter(p => p.slice(p.lastIndexOf("/") + 1).toLowerCase().includes(needle));
    }

    onOpened: {
        Theme.rescan();
        filter();
    }
    onQueryChanged: Qt.callLater(filter)
    onActivated: (path, modifiers) => {
        if (modifiers & Qt.ShiftModifier)
            Theme.applyTo(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "", path);
        else
            Theme.apply(path);
        close();
    }

    Connections {
        target: Theme

        function onAvailableChanged(): void {
            if (root.shown)
                root.filter();
        }
    }

    delegate: Rectangle {
        id: row

        required property string modelData
        required property int index
        readonly property bool selected: ListView.isCurrentItem && ListView.view.showSelection
        readonly property bool active: modelData === Theme.current
        readonly property string fileName: modelData.slice(modelData.lastIndexOf("/") + 1)

        width: ListView.view.width
        implicitHeight: 66
        radius: 12
        color: selected ? Colours.selection : area.containsMouse ? Colours.hover : "transparent"
        border.width: 1
        border.color: selected ? Colours.selectionBorder : active ? Colours.alpha(Colours.accent, 0.35) : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 12

            Rectangle {
                implicitWidth: 96
                implicitHeight: 54
                radius: 8
                color: Colours.alpha(Colours.accent, 0.12)
                clip: true

                Image {
                    anchors.fill: parent
                    source: "file://" + row.modelData
                    sourceSize: Qt.size(192, 108)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                BarText {
                    Layout.fillWidth: true
                    text: row.fileName.replace(/\.[^.]+$/, "")
                    px: 13
                    elide: Text.ElideRight
                }
                BarText {
                    Layout.fillWidth: true
                    text: row.active ? "Current" : row.fileName
                    px: 11
                    color: row.active ? Colours.accentBright : Colours.subtext
                    elide: Text.ElideRight
                }
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
}
