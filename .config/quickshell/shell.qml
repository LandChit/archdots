import QtQuick
import Quickshell
import Quickshell.Io
import "./"


ShellRoot {
    id: root

    // ── per-screen status bar ─────────────────────────────────────
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    // ── global popup singletons ───────────────────────────────────
    AppLauncher   { id: launcher }
    EmojiPicker   { id: emojiPicker }
    ClipboardMenu { id: clipMenu }
    PowerMenu     { id: powerMenu }

    // ── notification manager ──────────────────────────────────────
    NotificationPopup {}

    // ── FIFO IPC: keybinds write to /tmp/qs-ipc to toggle popups ──
    // Usage: exec, echo launcher > /tmp/qs-ipc
    Process {
        running: true
        command: [
            "bash", "-c",
            "mkfifo /tmp/qs-ipc 2>/dev/null; " +
            "while read -r cmd < /tmp/qs-ipc; do echo \"$cmd\"; done"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                const cmd = line.trim()
                if      (cmd === "launcher")  launcher.visible    = !launcher.visible
                else if (cmd === "emoji")     emojiPicker.visible = !emojiPicker.visible
                else if (cmd === "clipboard") clipMenu.visible    = !clipMenu.visible
                else if (cmd === "powermenu") powerMenu.visible   = !powerMenu.visible
                else if (cmd === "closeall")  {
                    launcher.visible    = false
                    emojiPicker.visible = false
                    clipMenu.visible    = false
                    powerMenu.visible   = false
                }
            }
        }
    }
}
