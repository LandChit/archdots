pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// UPower's display device: the laptop battery, or nothing on a desktop.
Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool available: device !== null && device.ready && device.isLaptopBattery
    // 0..100
    readonly property int percent: available ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: available && device.state === UPowerDeviceState.Charging
    readonly property bool onBattery: UPower.onBattery
}
