import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.widgets

// The wallpapers in Config.wallpaper.directory, newest first, with
// thumbnails. Enter sets one everywhere and recolours everything from it.
// With a wallpaper per screen (wallpaper.perMonitor) and more than one
// screen, it asks for the screen first; the primary screen's recolours.
ListPanel {
    id: root

    // The screen being picked for; "" is every screen, or not chosen yet.
    property string target: ""
    readonly property bool perScreen: Config.wallpaper.perMonitor && Quickshell.screens.length > 1
    readonly property bool choosingScreen: perScreen && target === ""

    name: "wallpaper"
    glyph: choosingScreen ? "\u{f0379}" : "\u{f0e09}"
    placeholder: choosingScreen ? "Which screen?" : target !== "" ? "Wallpaper for " + target : "Search wallpapers"
    hints: choosingScreen ? ["↕ navigate", "↵ choose screen", "esc close"] : ["↕ navigate", "↵ apply", "esc close"]
    listHeight: 470

    function filter(): void {
        const needle = query.trim().toLowerCase();
        if (choosingScreen) {
            const screens = Quickshell.screens.map(s => s.name).filter(n => n.toLowerCase().includes(needle));
            const focused = Hyprland.focusedMonitor ? screens.indexOf(Hyprland.focusedMonitor.name) : -1;
            defaultIndex = Math.max(0, focused);
            items = screens;
            return;
        }
        defaultIndex = 0;
        items = Theme.available.filter(p => p.slice(p.lastIndexOf("/") + 1).toLowerCase().includes(needle));
    }

    onOpened: {
        target = "";
        Theme.rescan();
        filter();
    }
    onQueryChanged: Qt.callLater(filter)
    onActivated: item => {
        if (choosingScreen) {
            target = item;
            if (query === "")
                filter();
            else
                query = "";
            return;
        }
        if (target !== "")
            Theme.setFor(target, item);
        else
            Theme.apply(item);
        close();
    }


    Connections {
        target: Theme

        function onAvailableChanged(): void {
            if (root.shown && !root.choosingScreen)
                root.filter();
        }
    }

    delegate: Rectangle {
        id: row

        required property string modelData
        required property int index
        readonly property bool selected: ListView.isCurrentItem && ListView.view.showSelection
        readonly property bool isScreen: root.choosingScreen
        readonly property bool primary: isScreen && Screens.primary !== null && Screens.primary.name === modelData
        readonly property string picture: isScreen ? Theme.wallpaperFor(modelData) : modelData
        readonly property bool active: !isScreen && modelData === (root.target !== "" ? Theme.wallpaperFor(root.target) : Theme.current)
        readonly property string fileName: modelData.slice(modelData.lastIndexOf("/") + 1)
        readonly property var screen: Quickshell.screens.find(s => s.name === modelData) ?? null

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
                    source: row.picture === "" ? "" : "file://" + row.picture
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
                    text: row.isScreen ? row.modelData + (row.screen && row.screen.model !== "" ? " · " + row.screen.model : "") : row.fileName.replace(/\.[^.]+$/, "")
                    px: 13
                    elide: Text.ElideRight
                }
                BarText {
                    Layout.fillWidth: true
                    text: row.isScreen ? (row.primary ? "Primary · the colours come from here" : row.picture.slice(row.picture.lastIndexOf("/") + 1)) : row.active ? "Current" : row.fileName
                    px: 11
                    color: row.active || row.primary ? Colours.accentBright : Colours.subtext
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
