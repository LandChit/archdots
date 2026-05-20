import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./"

FloatingWindow {
    id: root
    visible: false

    WlrLayerShell.layer: WlrLayerShell.Layer.Overlay
    WlrLayerShell.keyboardFocus: WlrLayerShell.KeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    ListModel { id: allApps }
    ListModel { id: filteredApps }
    property bool appsLoaded: false

    onVisibleChanged: {
        if (visible) {
            if (!appsLoaded) appsProc.running = true
            searchField.text = ""
            searchField.forceActiveFocus()
            appList.currentIndex = 0
        }
    }

    function filterApps(query) {
        filteredApps.clear()
        const q = query.toLowerCase()
        for (let i = 0; i < allApps.count; i++) {
            const app = allApps.get(i)
            if (!q || app.name.toLowerCase().includes(q))
                filteredApps.append(app)
        }
        appList.currentIndex = 0
    }

    function launch(idx) {
        if (idx < 0 || idx >= filteredApps.count) return
        const app = filteredApps.get(idx)
        launchProc.command = ["bash", "-c", app.exec + " &"]
        launchProc.running = true
        root.visible = false
    }

    Process {
        id: appsProc
        command: ["bash", "-c", [
            "find /usr/share/applications ~/.local/share/applications",
            "     -name '*.desktop' 2>/dev/null |",
            "while IFS= read -r f; do",
            "  grep -q '^NoDisplay=true' \"$f\" 2>/dev/null && continue",
            "  name=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-)",
            "  exec=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2- |",
            "         sed 's/ %[uUfFdDnNickvm]//g;s/%[uUfFdDnNickvm]//g')",
            "  [ -z \"$name\" ] && continue",
            "  printf '%s\\t%s\\n' \"$name\" \"$exec\"",
            "done | sort -f"
        ].join(" ")]
        stdout: SplitParser {
            onRead: function(line) {
                const t = line.indexOf("\t")
                if (t < 0) return
                allApps.append({ name: line.substring(0, t), exec: line.substring(t + 1) })
            }
        }
        onRunningChanged: {
            if (!running) { root.appsLoaded = true; root.filterApps(searchField.text) }
        }
    }
    Process { id: launchProc; command: [] }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: root.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 580; height: 480
            color: Palette.bg
            radius: Palette.radius
            border { color: Palette.border; width: 1 }
            MouseArea { anchors.fill: parent }

            Column {
                anchors { fill: parent; margins: 12 }
                spacing: 8

                Rectangle {
                    width: parent.width; height: 38
                    color: Palette.surface
                    radius: Palette.radius
                    border { color: Palette.accent; width: 1 }

                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: ""; font { family: Palette.font; pixelSize: 16 }; color: Palette.accent
                    }
                    TextInput {
                        id: searchField
                        anchors { fill: parent; leftMargin: 32; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                        color: Palette.fg
                        font { family: Palette.font; pixelSize: 14 }
                        clip: true
                        onTextChanged: root.filterApps(text)
                        Keys.onEscapePressed: root.visible = false
                        Keys.onReturnPressed: root.launch(appList.currentIndex)
                        Keys.onDownPressed:   appList.currentIndex = Math.min(appList.currentIndex + 1, filteredApps.count - 1)
                        Keys.onUpPressed:     appList.currentIndex = Math.max(appList.currentIndex - 1, 0)
                    }
                    Text {
                        visible: searchField.text.length === 0
                        anchors { fill: parent; leftMargin: 32; rightMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        text: "Search applications…"
                        color: Palette.muted
                        font { family: Palette.font; pixelSize: 14 }
                    }
                }

                ListView {
                    id: appList
                    width: parent.width
                    height: parent.height - 46
                    model: filteredApps
                    clip: true
                    currentIndex: 0
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property int    index
                        required property string name
                        required property string exec
                        width: appList.width; height: 38
                        radius: 6
                        color: appList.currentIndex === index ? Palette.surface : "transparent"

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                            text: name
                            color: appList.currentIndex === index ? Palette.fg : Palette.muted
                            font { family: Palette.font; pixelSize: 13 }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: appList.currentIndex = index
                            onClicked: root.launch(index)
                        }
                    }
                }
            }
        }
    }
}
