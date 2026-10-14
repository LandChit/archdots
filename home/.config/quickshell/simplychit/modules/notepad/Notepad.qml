import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// A scratch note in the middle of the screen. Saved as you type (and on
// close) to ~/.local/share/simplychit/notepad.md, plain text, so any editor
// can open it too, and edits made there show up here. Esc closes.
//
// qs -c simplychit ipc call panel toggle notepad
// qs -c simplychit ipc call notepad append "call the plumber"   (adds a line)
Panel {
    id: root

    name: "notepad"
    implicitWidth: 560
    implicitHeight: 440

    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/simplychit"
    property bool dirty: false
    // set while the file's text goes in, so that is not taken for an edit
    property bool loading: false

    // a line at the end, saved at once, open or not
    function append(line: string): void {
        const t = area.text;
        root.loading = true;
        area.text = t + (t === "" || t.endsWith("\n") ? "" : "\n") + line + "\n";
        root.loading = false;
        dirty = true;
        save();
    }

    function save(): void {
        saveTimer.stop();
        if (!dirty)
            return;
        file.setText(area.text);
        dirty = false;
    }

    onOpened: {
        file.reload();
        area.forceActiveFocus();
    }
    onShownChanged: {
        if (!shown)
            save();
    }

    FileView {
        id: file

        path: root.dataDir + "/notepad.md"
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        // no file yet is the normal first open
        printErrors: false
        onLoaded: {
            if (root.dirty)
                return;
            root.loading = true;
            area.text = text();
            root.loading = false;
        }
        // deleted elsewhere: start empty rather than write the old text back
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound || root.dirty)
                return;
            root.loading = true;
            area.text = "";
            root.loading = false;
        }
    }

    // FileView does not create the folder it writes into
    Process {
        running: true
        command: ["mkdir", "-p", root.dataDir]
    }

    Timer {
        id: saveTimer

        interval: 600
        onTriggered: root.save()
    }

    Rectangle {
        anchors.fill: parent
        y: (1 - root.reveal) * 10
        opacity: root.reveal
        radius: 18
        color: Colours.panel
        border.width: 1
        border.color: Colours.panelBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                BarText {
                    text: "\u{f082e}  Notepad"
                    px: 14
                    font.weight: Font.Medium
                }
                Item {
                    Layout.fillWidth: true
                }
                BarText {
                    text: root.dirty ? "editing…" : "saved"
                    px: 10.5
                    color: Colours.hint
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                TextArea {
                    id: area

                    wrapMode: TextArea.Wrap
                    color: Colours.foreground
                    selectionColor: Colours.alpha(Colours.accentBright, 0.45)
                    selectedTextColor: Colours.foreground
                    placeholderText: "Write anything. It is kept until you delete it."
                    placeholderTextColor: Colours.hint
                    font.family: "JetBrainsMono NF"
                    font.pointSize: 12.5 * 0.75
                    background: null

                    onTextChanged: {
                        if (!root.loading) {
                            root.dirty = true;
                            saveTimer.restart();
                        }
                    }

                    Keys.onEscapePressed: root.close()
                }
            }

            BarText {
                text: "~/.local/share/simplychit/notepad.md · esc close"
                px: 10
                color: Colours.hint
            }
        }
    }
}
