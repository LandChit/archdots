import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// QR codes both ways. Opened, it shows the clipboard's text as a QR code
// (qrencode); edit the text and press Enter to encode something else, or copy
// the code as an image. "Scan a region" reads a code off the screen and copies
// what it says (services/QrScan.qml).
//
// qs -c simplychit ipc call qr open|scan
Panel {
    id: root

    name: "qr"
    implicitWidth: 380
    implicitHeight: column.implicitHeight + 32

    readonly property string image: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/simplychit-qr.png"
    property string text: ""
    // why there is no code to show, if there is none
    property string problem: ""

    function encode(value: string): void {
        text = value;
        problem = "";
        qrImage.source = "";
        if (value === "") {
            problem = "The clipboard has no text";
            return;
        }
        encoder.command = ["qrencode", "-s", "8", "-m", "2", "-o", image, value];
        encoder.running = true;
    }

    onOpened: {
        paste.running = true;
        keys.forceActiveFocus();
    }

    Process {
        id: paste

        // text only: an image on the clipboard is not something to encode
        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            onStreamFinished: root.encode(text)
        }
    }

    Process {
        id: encoder

        stderr: StdioCollector {
            id: encodeErrors
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                qrImage.source = "file://" + root.image;
            } else {
                const err = encodeErrors.text.trim();
                root.problem = err.includes("too large") ? "Too long for a QR code" : err || "qrencode failed";
            }
        }
    }

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: root.close()
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
            id: column

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 12

            BarText {
                text: "\u{f0432}  QR code"
                px: 14
                font.weight: Font.Medium
            }

            // the code: dark on white whatever the theme, which is what
            // phone cameras read best
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 260
                implicitHeight: 260
                radius: 12
                color: root.problem === "" ? "white" : Colours.alpha(Colours.accent, 0.08)

                Image {
                    id: qrImage

                    anchors.fill: parent
                    anchors.margins: 6
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    cache: false
                    visible: root.problem === ""
                }

                BarText {
                    anchors.centerIn: parent
                    width: parent.width - 30
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: root.problem !== ""
                    text: root.problem
                    color: Colours.subtext
                }
            }

            TextField {
                Layout.fillWidth: true
                fieldWidth: 340
                value: root.text
                placeholder: "Text to encode, then Enter"
                onEdited: v => root.encode(v)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: "Copy image"
                    enabled: root.problem === ""
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", root.image]);
                        root.close();
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Button {
                    text: "Scan a region"
                    primary: true
                    onClicked: {
                        root.close();
                        QrScan.scan();
                    }
                }
            }
        }
    }
}
