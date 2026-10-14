pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

// Dim → lock → screens off → suspend after Config.idle's minutes, the AC or
// the battery set depending on the power source. 0 turns a step off.
//
// Paused while stay-awake is on (Idle.inhibited, SUPER+SHIFT+I); idle
// inhibitors from apps (a video playing) are respected too. Locking before a
// suspend, and turning the screens back on after one, stay with hypridle,
// which follows logind's sleep signals.
Singleton {
    id: root

    readonly property var times: Battery.onBattery ? Config.idle.battery : Config.idle.ac

    component Step: IdleMonitor {
        id: step

        required property real minutes
        property bool restarting: false

        enabled: minutes > 0 && !Idle.inhibited && !restarting
        timeout: Math.max(1, Math.round(minutes * 60))
        respectInhibitors: true

        // An enabled IdleMonitor keeps the timeout it registered with and
        // ignores later changes (quickshell 0.3.2), so the defaults it starts
        // with would stick after settings.json loads, and the AC/battery
        // switch would do nothing. Turning it off and on registers it again.
        onTimeoutChanged: {
            restarting = true;
            Qt.callLater(() => step.restarting = false);
        }
    }

    Step {
        minutes: root.times.dim
        onIsIdleChanged: Quickshell.execDetached(isIdle ? ["brightnessctl", "-s", "set", "10"] : ["brightnessctl", "-r"])
    }

    Step {
        minutes: root.times.lock
        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached(["loginctl", "lock-session"]);
        }
    }

    Step {
        minutes: root.times.screenOff
        onIsIdleChanged: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"" + (isIdle ? "disable" : "enable") + "\" })"])
    }

    Step {
        minutes: root.times.suspend
        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached(["systemctl", "suspend"]);
        }
    }
}
