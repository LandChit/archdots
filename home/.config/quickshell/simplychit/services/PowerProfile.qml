pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Power-saver / balanced / performance (TODO 12), through the standard
// power-profiles D-Bus interface. power-profiles-daemon provides it, and so
// does TLP 1.9+'s tlp-pd (TLP itself conflicts with power-profiles-daemon:
// use one or the other). With neither running, `available` is false and the
// control centre hides the toggle.
Singleton {
    id: root

    property bool available: false
    readonly property int profile: PowerProfiles.profile
    readonly property string label: profile === PowerProfile.PowerSaver ? "Saver" : profile === PowerProfile.Performance ? "Performance" : "Balanced"
    readonly property string glyph: profile === PowerProfile.PowerSaver ? "\u{f032a}" : profile === PowerProfile.Performance ? "\u{f04c5}" : "\u{f05d1}"

    // Saver → Balanced → Performance (if the hardware has one) → Saver
    function cycle(): void {
        if (!available)
            return;
        if (profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    Process {
        running: true
        command: ["sh", "-c", "busctl --system status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1 || busctl --system status net.hadess.PowerProfiles >/dev/null 2>&1"]
        onExited: code => root.available = code === 0
    }
}
