import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Hyprland
import qs.config

// The session lock (ext-session-lock), checked with PAM. Opt-in: with
// lock.enabled off (the default) `ipc call lock lock` refuses and
// hypr/Scripts/lock.sh runs hyprlock instead.
//
// If the shell ever dies while locked, Hyprland shows its "lock died"
// screen. misc.allow_session_lock_restore (theme.lua) lets another locker
// take over: switch to a TTY (Ctrl+Alt+F2), log in, and run
//   hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'
// then go back (Ctrl+Alt+F1) and unlock with hyprlock.
Scope {
    id: root

    property string message: ""
    property bool busy: false
    property string pending: ""
    property bool previewing: false

    function authenticate(password: string): void {
        if (busy || password === "")
            return;
        message = "";
        busy = true;
        pending = password;
        pam.start();
    }

    PamContext {
        id: pam

        config: Config.lock.pamConfig
        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(root.pending);
                root.pending = "";
            }
        }
        onCompleted: result => {
            root.busy = false;
            if (result === PamResult.Success) {
                session.locked = false;
                root.message = "";
            } else {
                root.message = result === PamResult.MaxTries ? "Too many attempts" : "Wrong password";
            }
        }
        onError: () => {
            root.busy = false;
            root.message = "Could not check the password";
        }
    }

    WlSessionLock {
        id: session

        surface: WlSessionLockSurface {
            color: "black"

            LockContent {
                id: content

                anchors.fill: parent
                screenName: parent.screen ? parent.screen.name : ""
                message: root.message
                busy: root.busy
                onSubmitted: password => {
                    root.authenticate(password);
                    content.password = "";
                }
                Component.onCompleted: focusInput()
            }
        }
    }

    // A preview in an ordinary window: the same screen, nothing locked.
    // Esc closes it; the password field does nothing here.
    PanelWindow {
        visible: root.previewing
        screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "simplychit-lock-preview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        LockContent {
            id: previewContent

            anchors.fill: parent
            screenName: parent.screen ? parent.screen.name : ""
            message: "Preview: Esc to close"
            onEscaped: root.previewing = false
            onSubmitted: root.previewing = false
        }

        onVisibleChanged: {
            if (visible)
                previewContent.focusInput();
        }
    }

    IpcHandler {
        target: "lock"

        // "ok" when locked (or already locked); lock.sh falls back to
        // hyprlock on anything else.
        function lock(): string {
            if (!Config.lock.enabled)
                return "disabled";
            root.message = "";
            session.locked = true;
            return "ok";
        }
        function isLocked(): bool {
            return session.locked;
        }
        function preview(): void {
            root.previewing = true;
        }
    }
}
