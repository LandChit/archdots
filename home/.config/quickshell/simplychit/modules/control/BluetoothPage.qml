import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.widgets

// Paired devices first, then anything found while scanning. Click a paired
// device to connect or disconnect it, an unpaired one to pair. Devices that
// need a passkey typed in still need bluetoothctl.
ColumnLayout {
    id: root

    property bool active: false
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)) : []

    // stop a scan the user started when the page goes away
    onActiveChanged: {
        if (!active && adapter && adapter.discovering)
            adapter.discovering = false;
    }

    spacing: 4

    BarText {
        visible: root.adapter === null
        text: "No Bluetooth adapter"
        color: Colours.subtext
        Layout.margins: 8
    }
    BarText {
        visible: root.adapter !== null && !root.adapter.enabled
        text: "Bluetooth is off"
        color: Colours.subtext
        Layout.margins: 8
    }

    InfoRow {
        visible: root.adapter !== null && root.adapter.enabled
        glyph: root.adapter && root.adapter.discovering ? "\u{f0b7c}" : "\u{f0349}"
        title: root.adapter && root.adapter.discovering ? "Scanning… (click to stop)" : "Scan for devices"
        onClicked: root.adapter.discovering = !root.adapter.discovering
    }

    Repeater {
        model: root.adapter && root.adapter.enabled ? root.devices.filter(d => d.paired || root.adapter.discovering) : []

        InfoRow {
            required property var modelData

            glyph: "\u{f00af}"
            title: modelData.name || modelData.address
            subtitle: modelData.pairing ? "Pairing…" : modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Not paired · click to pair"
            trailing: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
            active: modelData.connected

            onClicked: {
                if (modelData.connected)
                    modelData.disconnect();
                else if (modelData.paired)
                    modelData.connect();
                else if (!modelData.pairing)
                    modelData.pair();
            }
        }
    }
}
