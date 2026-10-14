pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU package temperature in °C, or -1 when there is no sensor.
//
// The sensor is found once:
// by hwmon driver name, then by thermal zone type. thermal_zone0 is not
// portable (it is a chassis probe on some laptops and a constant 20°C on others).
Singleton {
    id: root

    property string sensor: ""
    property int celsius: -1

    Process {
        running: true
        command: ["sh", "-c", `
            for want in coretemp k10temp zenpower cpu_thermal; do
                for h in /sys/class/hwmon/hwmon*; do
                    [ "$(cat "$h/name" 2>/dev/null)" = "$want" ] || continue
                    for e in temp1_input temp2_input; do
                        [ -r "$h/$e" ] && { echo "$h/$e"; exit; }
                    done
                done
            done
            for want in x86_pkg_temp cpu-thermal soc_thermal acpitz; do
                for z in /sys/class/thermal/thermal_zone*; do
                    [ "$(cat "$z/type" 2>/dev/null)" = "$want" ] && { echo "$z/temp"; exit; }
                done
            done`]
        stdout: StdioCollector {
            onStreamFinished: root.sensor = text.trim()
        }
    }

    FileView {
        id: reading

        path: root.sensor
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 3000
        running: root.sensor !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            reading.reload();
            const milli = parseInt(reading.text());
            root.celsius = isNaN(milli) ? -1 : Math.round(milli / 1000);
        }
    }
}
