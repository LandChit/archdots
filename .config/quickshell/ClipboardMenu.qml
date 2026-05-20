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

    ListModel { id: clipModel }
    property string filterText: ""

    onVisibleChanged: {
        if (visible) {
            clipModel.clear()
            filterText = ""
            clipSearch.text = ""
            listProc.running = true
            clipSearch.forceActiveFocus()
            clipList.currentIndex = 0
        }
    }

    function pasteEntry(idx) {
        if (idx < 0 || idx >= clipModel.count) return
        const entry = clipModel.get(idx)
        // Use the binary-safe paste script
        const scriptPath = Qt.resolvedUrl("./scripts/clipboard-paste.sh").toString().replace("file://", "")
        pasteProc.command = ["bash", scriptPath, entry.entryId]
        pasteProc.running = true
        root.visible = false
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                const tab = line.indexOf("\t")
                const id  = tab >= 0 ? line.substring(0, tab) : line
                const preview = tab >= 0 ? line.substring(tab + 1).trim() : ""
                const isImg = preview.startsWith("[[") || preview === ""
                clipModel.append({
                    entryId:  id,
                    preview:  isImg ? "Image" : preview,
                    isImage:  isImg
                })
            }
        }
    }
    Process { id: pasteProc; command: [] }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: root.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 580; height: 500
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
                        id: clipSearch
                        anchors { fill: parent; leftMargin: 32; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                        color: Palette.fg
                        font { family: Palette.font; pixelSize: 14 }
                        clip: true
                        onTextChanged: root.filterText = text.toLowerCase()
                        Keys.onEscapePressed: root.visible = false
                        Keys.onReturnPressed: root.pasteEntry(clipList.currentIndex)
                        Keys.onDownPressed:   clipList.currentIndex = Math.min(clipList.currentIndex + 1, clipList.count - 1)
                        Keys.onUpPressed:     clipList.currentIndex = Math.max(clipList.currentIndex - 1, 0)
                    }
                    Text {
                        visible: clipSearch.text.length === 0
                        anchors { fill: parent; leftMargin: 32; rightMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        text: "Search clipboard…"
                        color: Palette.muted
                        font { family: Palette.font; pixelSize: 14 }
                    }
                }

                ListView {
                    id: clipList
                    width: parent.width
                    height: parent.height - 46
                    clip: true
                    currentIndex: 0
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    model: clipModel

                    delegate: Rectangle {
                        required property int    index
                        required property string entryId
                        required property string preview
                        required property bool   isImage

                        readonly property bool shown: root.filterText === "" ||
                            preview.toLowerCase().includes(root.filterText)

                        visible: shown
                        height: shown ? 38 : 0
                        width: clipList.width
                        radius: 6
                        color: clipList.currentIndex === index ? Palette.surface : "transparent"

                        Row {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            spacing: 8
                            visible: parent.shown

                            Text {
                                visible: isImage
                                text: "󰋩"
                                color: Palette.accent
                                font { family: Palette.font; pixelSize: 14 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: clipList.width - 32
                                text: preview.replace(/\n/g, " ").substring(0, 80)
                                color: clipList.currentIndex === index ? Palette.fg : Palette.muted
                                font { family: Palette.font; pixelSize: 12 }
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: clipList.currentIndex = index
                            onClicked: root.pasteEntry(index)
                        }
                    }
                }
            }
        }
    }
}
