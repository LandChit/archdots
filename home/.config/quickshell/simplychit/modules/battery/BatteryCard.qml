import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services
import qs.widgets

// The battery card, centred on the focused screen. Two ways in:
//
//  · Clicking the bar's battery meter opens it as a panel: charge, charging
//    state and time left.
//  · It opens itself to warn while discharging, at Config.battery.lowPercent
//    and criticalPercent. Dismissing snoozes for 5 minutes, but a lower level
//    shows straight away. A low warning goes away by itself after 20 s.
//    Warnings never take the keyboard, so they do not close or steal from
//    whatever you are typing in.
//
// At actionPercent it counts down 30 s and then runs criticalAction (TODO
// C13), unless you plug in or press Cancel.
PanelWindow {
    id: root

    readonly property bool asPanel: Panels.current === "battery"
    // "", "low", "critical", "action"
    property string warning: ""
    property string shownWarning: ""
    property double snoozeUntil: 0
    property int countdown: 0
    property bool cancelled: false

    readonly property bool shown: asPanel || warning !== ""
    property real reveal: shown ? 1 : 0

    readonly property var icons: [[11, "\u{f0083}"], [31, "\u{f007a}"], [51, "\u{f007c}"], [71, "\u{f007e}"], [91, "\u{f0080}"], [10000, "\u{f0079}"]]

    function pick(value) {
        for (const [bound, glyph] of icons)
            if (value < bound)
                return glyph;
        return icons[icons.length - 1][1];
    }

    function levelFor(percent: int): string {
        if (percent <= Config.battery.actionPercent && Config.battery.criticalAction !== "none")
            return "action";
        if (percent <= Config.battery.criticalPercent)
            return "critical";
        if (percent <= Config.battery.lowPercent)
            return "low";
        return "";
    }

    function severity(level: string): int {
        return ["", "low", "critical", "action"].indexOf(level);
    }

    function check(): void {
        if (!Battery.discharging) {
            warning = "";
            shownWarning = "";
            snoozeUntil = 0;
            cancelled = false;
            countdownTimer.stop();
            return;
        }
        const level = levelFor(Battery.percent);
        if (level === "") {
            warning = "";
            shownWarning = "";
            return;
        }
        const worse = severity(level) > severity(shownWarning);
        if (warning === "" && !worse && Date.now() < snoozeUntil)
            return;
        if (level === "action" && cancelled)
            return;
        warning = level;
        shownWarning = level;
        if (level === "action" && !countdownTimer.running) {
            countdown = 30;
            countdownTimer.start();
        }
        if (level === "low")
            autoDismiss.restart();
    }

    function dismiss(): void {
        if (warning === "action") {
            cancelled = true;
            countdownTimer.stop();
        }
        warning = "";
        snoozeUntil = Date.now() + 5 * 60 * 1000;
        Panels.close("battery");
    }

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
    visible: reveal > 0
    implicitWidth: 460
    implicitHeight: 120
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "simplychit-battery"
    WlrLayershell.keyboardFocus: asPanel ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Behavior on reveal {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Connections {
        target: Battery

        function onPercentChanged(): void { root.check(); }
        function onDischargingChanged(): void { root.check(); }
    }
    Connections {
        target: Config.battery

        function onCriticalActionChanged(): void { root.check(); }
    }

    Timer {
        interval: 30000
        running: Battery.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }

    Timer {
        id: autoDismiss

        interval: 20000
        onTriggered: {
            if (root.warning === "low")
                root.dismiss();
        }
    }

    Timer {
        id: countdownTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown > 0)
                return;
            stop();
            if (root.warning === "action" && Battery.discharging)
                Quickshell.execDetached(["systemctl", Config.battery.criticalAction]);
            root.warning = "";
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.asPanel
        onCleared: Panels.close("battery")
    }

    Rectangle {
        id: card

        readonly property bool alarm: root.warning === "critical" || root.warning === "action"
        readonly property color tone: alarm ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1) : root.warning === "low" ? Qt.rgba(232 / 255, 168 / 255, 74 / 255, 1) : Colours.accentBright

        anchors.fill: parent
        anchors.margins: 10
        opacity: root.reveal
        scale: 0.97 + 0.03 * root.reveal
        radius: 18
        color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), 0.94)
        border.width: 1
        border.color: root.warning === "" ? Colours.panelBorder : Colours.alpha(tone, 0.55)

        focus: root.asPanel
        Keys.onEscapePressed: root.dismiss()

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 16
            spacing: 16

            BarText {
                px: 34
                color: card.tone
                text: !Battery.available ? "\u{f0091}" : Battery.charging ? "\u{f0084}" : root.pick(Battery.percent)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                BarText {
                    px: 13.5
                    font.weight: Font.Medium
                    text: !Battery.available ? "No battery"
                        : root.warning === "action" ? "Battery critical · " + Battery.percent + "%"
                        : root.warning === "critical" ? "Battery critical · " + Battery.percent + "%"
                        : root.warning === "low" ? "Battery low · " + Battery.percent + "%"
                        : "Battery · " + Battery.percent + "%"
                }
                BarText {
                    Layout.fillWidth: true
                    px: 11.5
                    color: Colours.subtext
                    wrapMode: Text.WordWrap
                    readonly property string remaining: Battery.duration(Battery.discharging ? Battery.timeToEmpty : Battery.timeToFull)
                    text: !Battery.available ? "This machine runs on mains power."
                        : root.warning === "action" ? Config.battery.criticalAction.charAt(0).toUpperCase() + Config.battery.criticalAction.slice(1) + " in " + root.countdown + " s unless you plug in."
                        : root.warning === "critical" ? "Plug in now — the session is about to end." + (remaining ? " " + remaining + " left." : "")
                        : root.warning === "low" ? "Time to charge." + (remaining ? " " + remaining + " left." : "")
                        : Battery.full ? "Fully charged."
                        : Battery.charging ? "Charging" + (remaining ? " — " + remaining + " until full." : ".")
                        : remaining ? remaining + " remaining." : "Discharging."
                }
            }

            Rectangle {
                implicitWidth: label.implicitWidth + 24
                implicitHeight: 32
                radius: 11
                color: area.containsMouse ? Colours.alpha(card.tone, 0.25) : Colours.alpha(card.tone, 0.12)
                border.width: 1
                border.color: Colours.alpha(card.tone, 0.45)

                BarText {
                    id: label

                    anchors.centerIn: parent
                    text: root.warning === "action" ? "Cancel" : root.warning === "" ? "Close" : "Dismiss"
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                }
            }
        }
    }
}
