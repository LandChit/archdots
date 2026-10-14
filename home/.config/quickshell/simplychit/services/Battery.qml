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
    readonly property bool discharging: available && device.state === UPowerDeviceState.Discharging
    readonly property bool full: available && device.state === UPowerDeviceState.FullyCharged
    // seconds; 0 when UPower does not know yet
    readonly property real timeToEmpty: available ? device.timeToEmpty : 0
    readonly property real timeToFull: available ? device.timeToFull : 0

    // "2h 05m" / "35m", or "" when unknown
    function duration(seconds: real): string {
        if (!(seconds > 0))
            return "";
        const minutes = Math.round(seconds / 60);
        const h = Math.floor(minutes / 60), m = minutes % 60;
        return h > 0 ? h + "h " + String(m).padStart(2, "0") + "m" : m + "m";
    }
}
