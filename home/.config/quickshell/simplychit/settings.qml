//@ pragma UseQApplication

import QtQuick
import Quickshell
import qs.modules.settings
import qs.services

// The settings app on its own, for when the shell is not running:
//   qs -p ~/.config/quickshell/simplychit/settings.qml
// It edits the same settings.json; changes reach a running shell live and
// the Hyprland config on its next reload.
ShellRoot {
    SettingsWindow {}
    DisplayOverlays {}

    Component.onCompleted: SettingsState.show("")

    Connections {
        target: SettingsState

        function onOpenChanged(): void {
            if (!SettingsState.open)
                Qt.quit();
        }
    }
}
