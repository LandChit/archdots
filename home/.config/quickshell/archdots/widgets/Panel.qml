import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// A panel's window: shown while Panels.current is its name, on the screen it
// was opened on. It takes the keyboard while open, and a click outside it
// closes it. `reveal` runs 0 → 1 as it opens and back as it closes; the window
// stays mapped until it is back at 0, so content can animate on it.
PanelWindow {
    id: root

    required property string name
    readonly property bool shown: Panels.current === name
    property real reveal: shown ? 1 : 0
    property bool closeOnOutsideClick: true
    property int layer: WlrLayer.Top

    // Each time the panel opens, before it is visible: reset and refresh here.
    signal opened

    function close(): void {
        Panels.close(name);
    }

    screen: Panels.screen
    visible: shown || reveal > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: layer
    WlrLayershell.namespace: "archdots-" + name
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onShownChanged: {
        if (shown)
            opened();
    }

    Behavior on reveal {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown && root.closeOnOutsideClick
        onCleared: root.close()
    }
}
