import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import qs.config
import qs.services
import qs.widgets

// The switches that would otherwise send you to a terminal: Wi-Fi,
// Bluetooth, alerts (DND), stay awake and the power profile; volume and
// brightness; what is playing; and tabs for networks, Bluetooth devices,
// audio devices and apps, and the tray.
Panel {
    id: root

    name: "control"
    anchors.top: true
    anchors.right: true
    margins.top: 46
    margins.right: 14
    implicitWidth: 420
    implicitHeight: card.implicitHeight + 20

    property string page: "networks"
    readonly property var pages: [["networks", "Networks"], ["bluetooth", "Bluetooth"], ["audio", "Audio"], ["tray", "Tray"]]

    onOpened: {
        keys.forceActiveFocus();
        Brightness.refresh();
    }

    // qs -c archdots ipc call control open audio
    IpcHandler {
        target: "control"

        function open(page: string): void {
            if (root.pages.some(p => p[0] === page))
                root.page = page;
            Panels.open("control");
        }
    }

    Item {
        id: keys

        focus: true
        Keys.onEscapePressed: root.close()
    }

    component Level: RowLayout {
        id: level

        property string glyph: ""
        property real value: 0
        property string text: ""
        signal glyphClicked
        signal moved(real value)

        Layout.fillWidth: true
        spacing: 12

        BarText {
            text: level.glyph
            px: 17
            color: Colours.alpha(Colours.foreground, 0.8)

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: level.glyphClicked()
            }
        }
        Slider {
            Layout.fillWidth: true
            value: level.value
            onMoved: v => level.moved(v)
        }
        BarText {
            Layout.minimumWidth: 40
            horizontalAlignment: Text.AlignRight
            text: level.text
            px: 11
            color: Colours.subtext
        }
    }

    Rectangle {
        id: card

        width: root.implicitWidth
        implicitHeight: column.implicitHeight + 32
        y: (1 - root.reveal) * -10
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
                text: "Control centre"
                px: 15
                font.weight: Font.Medium
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Toggle {
                    glyph: Networking.wifiEnabled ? "\u{f05a9}" : "\u{f05aa}"
                    label: "Wi-Fi"
                    active: Networking.wifiEnabled
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
                Toggle {
                    visible: Bluetooth.defaultAdapter !== null
                    glyph: "\u{f00af}"
                    label: "Bluetooth"
                    active: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
                    onClicked: Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                }
                Toggle {
                    glyph: Notifs.dnd ? "\u{f009b}" : "\u{f009a}"
                    label: "Alerts"
                    active: !Notifs.dnd
                    onClicked: Notifs.dnd = !Notifs.dnd
                }
                Toggle {
                    glyph: "\u{f0176}"
                    label: "Awake"
                    active: Idle.inhibited
                    onClicked: Idle.toggle()
                }
                Toggle {
                    visible: PowerProfile.available
                    glyph: PowerProfile.glyph
                    label: PowerProfile.label
                    active: true
                    onClicked: PowerProfile.cycle()
                }
            }

            Level {
                glyph: Audio.muted ? "\u{f075f}" : "\u{f057e}"
                value: Audio.volume
                text: Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
                onGlyphClicked: Audio.toggleMute()
                onMoved: v => Audio.setVolume(v)
            }

            Level {
                visible: Brightness.percent >= 0
                glyph: "\u{f00e0}"
                value: Brightness.percent / 100
                text: Brightness.percent + "%"
                onMoved: v => Brightness.set(Math.round(v * 100))
            }

            // what is playing
            Rectangle {
                Layout.fillWidth: true
                visible: Media.active !== null
                implicitHeight: 48
                radius: 12
                color: Colours.alpha(Colours.accent, 0.08)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        BarText {
                            Layout.fillWidth: true
                            text: Media.title || (Media.active ? Media.active.identity : "")
                            elide: Text.ElideRight
                        }
                        BarText {
                            Layout.fillWidth: true
                            text: Media.artist
                            px: 10.5
                            color: Colours.subtext
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }

                    Repeater {
                        model: [["\u{f04ae}", () => Media.active.previous()], [Media.playing ? "\u{f03e4}" : "\u{f040a}", () => Media.active.togglePlaying()], ["\u{f04ad}", () => Media.active.next()]]

                        Hot {
                            required property var modelData

                            onClicked: modelData[1]()

                            BarText {
                                text: parent.parent.modelData[0]
                                px: 16
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.pages

                    Rectangle {
                        required property var modelData
                        readonly property bool current: root.page === modelData[0]

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 10
                        color: current ? Colours.alpha(Colours.accentBright, 0.20) : tabArea.containsMouse ? Colours.hover : "transparent"
                        border.width: 1
                        border.color: current ? Colours.alpha(Colours.accentBright, 0.45) : Colours.alpha(Colours.accent, 0.18)

                        BarText {
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            px: 11.5
                            color: parent.current ? Colours.foreground : Colours.subtext
                        }

                        MouseArea {
                            id: tabArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = parent.modelData[0]
                        }
                    }
                }
            }

            // one height for every tab, so the panel does not jump as you switch
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 240
                contentHeight: pageColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: pageColumn

                    width: parent.width

                    NetworksPage {
                        Layout.fillWidth: true
                        visible: active
                        active: root.shown && root.page === "networks"
                    }
                    BluetoothPage {
                        Layout.fillWidth: true
                        visible: active
                        active: root.shown && root.page === "bluetooth"
                    }
                    AudioPage {
                        Layout.fillWidth: true
                        visible: active
                        active: root.shown && root.page === "audio"
                    }
                    TrayPage {
                        Layout.fillWidth: true
                        visible: root.page === "tray"
                        window: root
                    }
                }
            }
        }
    }
}
