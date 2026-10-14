import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.config
import qs.widgets

// Wi-Fi networks, connected first, then by signal. Click to connect or
// disconnect. A secured network you have not joined before asks for its
// password here (fabric could only point you at nmcli).
ColumnLayout {
    id: root

    property bool active: false
    property string askingFor: ""
    property string status: ""

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.filter(d => d.type === DeviceType.Wired && d.connected)
    readonly property var networks: wifi ? wifi.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []

    readonly property var bars: [[0.25, "\u{f091f}"], [0.5, "\u{f0922}"], [0.75, "\u{f0925}"], [2, "\u{f0928}"]]

    function barsFor(strength: real): string {
        for (const [bound, glyph] of bars)
            if (strength < bound)
                return glyph;
        return bars[bars.length - 1][1];
    }

    // Scan only while the page is on screen.
    onActiveChanged: {
        if (wifi)
            wifi.scannerEnabled = active;
        if (!active)
            askingFor = "";
    }

    spacing: 4

    Repeater {
        model: root.wired

        InfoRow {
            required property var modelData

            glyph: "\u{f0200}"
            title: modelData.name
            subtitle: "Wired · connected"
            active: true
        }
    }

    BarText {
        visible: root.wifi === null
        text: "No Wi-Fi device"
        color: Colours.subtext
        Layout.margins: 8
    }
    BarText {
        visible: root.wifi !== null && !Networking.wifiEnabled
        text: "Wi-Fi is off"
        color: Colours.subtext
        Layout.margins: 8
    }

    Repeater {
        model: Networking.wifiEnabled ? root.networks : []

        InfoRow {
            id: row

            required property var modelData
            readonly property bool secured: modelData.security !== WifiSecurityType.Open

            glyph: root.barsFor(modelData.signalStrength)
            title: modelData.name
            subtitle: modelData.stateChanging ? "Connecting…" : modelData.connected ? "Connected" : modelData.known ? "Saved" : secured ? "Secured" : "Open"
            trailing: Math.round(modelData.signalStrength * 100) + "%"
            active: modelData.connected

            onClicked: {
                root.status = "";
                if (modelData.connected)
                    modelData.disconnect();
                else if (modelData.known || !secured)
                    modelData.connect();
                else
                    root.askingFor = root.askingFor === modelData.name ? "" : modelData.name;
            }

            Connections {
                target: row.modelData

                function onConnectionFailed(): void {
                    root.status = "Could not join " + row.modelData.name;
                }
            }

            Rectangle {
                visible: root.askingFor === row.modelData.name
                width: parent.width
                height: visible ? 32 : 0
                radius: 9
                color: Colours.alpha(Colours.accent, 0.10)
                border.width: 1
                border.color: Colours.alpha(Colours.accent, 0.30)

                TextInput {
                    id: psk

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Colours.foreground
                    font.family: "JetBrainsMono NF"
                    font.pointSize: 12 * 0.75
                    focus: parent.visible
                    onVisibleChanged: {
                        text = "";
                        if (visible)
                            forceActiveFocus();
                    }
                    Keys.onReturnPressed: {
                        row.modelData.connectWithPsk(text);
                        root.askingFor = "";
                    }
                    Keys.onEscapePressed: root.askingFor = ""

                    BarText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password, then Enter"
                        px: 11
                        color: Colours.hint
                        visible: psk.text === ""
                    }
                }
            }
        }
    }

    BarText {
        visible: root.status !== ""
        text: root.status
        px: 11
        color: Colours.subtext
        Layout.margins: 6
    }
}
