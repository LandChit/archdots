import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.modules.lock

// The login screen: greetd runs it inside cage (install.sh --greeter):
//   [default_session]
//   command = "env HOME=/var/lib/simplychit/greeter QT_WAYLAND_DISABLE_WINDOWDECORATION=1 cage -s -d -- qs -p /usr/share/simplychit/shell/greeter.qml"
//   user = "greeter"
// It looks like the lock screen. The palette and the wallpaper are copies in
// that HOME (.cache/wal/colors.json, .local/state/simplychit/wallpaper), since
// it cannot read yours; greetd's own user has / as its home.
//
// Not under greetd (no GREETD_SOCK) it is a preview: nothing logs in, and
// Esc quits. qs -p ~/.config/quickshell/simplychit/greeter.qml
ShellRoot {
    id: root

    readonly property bool preview: !Greetd.available
    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/simplychit/greeter.json"
    property string message: preview ? "Preview: nothing logs in here. Esc closes it." : ""
    property bool busy: false
    property string pending: ""
    property string lastUser: ""
    property string lastSession: ""
    // [{ name, exec }] from /usr/share/wayland-sessions
    property var sessions: []
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex] ?? null

    function login(user: string, password: string): void {
        if (busy || user === "")
            return;
        if (preview) {
            message = "Preview: would log " + user + " in to " + (session ? session.name : "Hyprland");
            return;
        }
        message = "";
        busy = true;
        pending = password;
        Greetd.createSession(user);
    }

    function remember(user: string): void {
        stateFile.setText(JSON.stringify({ user: user, session: session ? session.name : "" }) + "\n");
    }

    function command(): var {
        // field codes (%U, %f, ...) mean nothing here
        const exec = session ? session.exec : "uwsm start hyprland.desktop";
        return exec.replace(/%[a-zA-Z]/g, "").split(" ").filter(part => part !== "");
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (error)
                root.message = message;
            if (responseRequired) {
                Greetd.respond(root.pending);
                root.pending = "";
            }
        }
        // greetd ends the session itself after a failed login; a
        // cancelSession() here fails ("Connection refused", found in a VM)
        function onAuthFailure(message: string): void {
            root.busy = false;
            root.message = "Wrong password";
        }
        function onReadyToLaunch(): void {
            root.remember(Greetd.user);
            Greetd.launch(root.command());
        }
        function onError(error: string): void {
            root.busy = false;
            root.message = error;
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.lastUser = saved.user ?? "";
                root.lastSession = saved.session ?? "";
            } catch (e) {}
            sessionList.running = true;
        }
        onLoadFailed: sessionList.running = true
    }

    Process {
        id: sessionList

        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do [ -r \"$f\" ] || continue; printf '%s\\t%s\\n' \"$(sed -n 's/^Name=//p' \"$f\" | head -1)\" \"$(sed -n 's/^Exec=//p' \"$f\" | head -1)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(l => l.includes("\t")).map(l => ({
                            name: l.split("\t")[0],
                            exec: l.split("\t")[1]
                        }));
                root.sessions = found;
                // the last one used, else Hyprland under uwsm, else the first
                let i = found.findIndex(s => s.name === root.lastSession);
                if (i < 0)
                    i = found.findIndex(s => s.exec.includes("uwsm"));
                root.sessionIndex = Math.max(0, i);
            }
        }
    }

    // One ordinary window: cage has no layer-shell, and shows its one window
    // fullscreen. (As a preview it is a normal window.)
    FloatingWindow {
        id: win

        title: "SimplyChit login"
        color: "black"
        implicitWidth: 1280
        implicitHeight: 800

        LockContent {
            id: content

            anchors.fill: parent
            screenName: win.screen ? win.screen.name : ""
            askUser: true
            message: root.message
            busy: root.busy
            actions: [[(root.session ? root.session.name : "Hyprland") + "  \u{f0142}", "session"], ["Restart", "reboot"], ["Shut down", "poweroff"]]
            onSubmitted: password => {
                root.login(content.user, password);
                content.password = "";
            }
            onEscaped: {
                if (root.preview)
                    Qt.quit();
            }
            onAction: which => {
                if (which === "session" && root.sessions.length > 0)
                    root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length;
                else if (root.preview)
                    root.message = "Preview: would " + (which === "reboot" ? "restart" : "shut down");
                else
                    Quickshell.execDetached(["systemctl", which]);
            }

            Component.onCompleted: {
                content.user = root.lastUser;
                focusInput();
            }

            Connections {
                target: root

                function onLastUserChanged(): void {
                    if (content.user === "") {
                        content.user = root.lastUser;
                        content.focusInput();
                    }
                }
            }
        }
    }
}
