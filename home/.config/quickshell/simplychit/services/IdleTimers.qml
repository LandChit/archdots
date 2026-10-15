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

    // The laptop panel through brightnessctl, external monitors over DDC/CI
    // (Brightness.ddcDisplays). Each external level is saved to a runtime
    // file before dimming and put back from it; the lock keeps a slow dim
    // (ddcutil takes a moment per monitor) and a quick wake from crossing.
    function dim(on: bool): void {
        const displays = Object.keys(Brightness.ddcDisplays)
            .filter(name => !/^(eDP|LVDS|DSI)-/.test(name))
            .map(name => String(Brightness.ddcDisplays[name]));
        Quickshell.execDetached(["flock", Quickshell.env("XDG_RUNTIME_DIR") + "/simplychit-dim.lock", "sh", "-c", `
            saved="$XDG_RUNTIME_DIR/simplychit-dim"
            if [ "$1" = on ]; then
                # already dim: saving again would keep the dimmed levels
                [ -e "$saved" ] && exit 0
                : > "$saved"
                brightnessctl -s set 10
                shift
                for d in "$@"; do
                    level=$(ddcutil --display "$d" getvcp 10 --terse | awk '{print $4}')
                    [ -n "$level" ] || continue
                    echo "$d $level" >> "$saved"
                    ddcutil --noverify --display "$d" setvcp 10 10
                done
            else
                [ -e "$saved" ] || exit 0
                brightnessctl -r
                while read -r d level; do
                    ddcutil --noverify --display "$d" setvcp 10 "$level"
                done < "$saved"
                rm -f "$saved"
            fi
        `, "sh", on ? "on" : "off"].concat(displays));
    }

    Step {
        minutes: root.times.dim
        onIsIdleChanged: root.dim(isIdle)
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
