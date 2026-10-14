import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

ColumnLayout {
    spacing: 14

    PageTitle {
        title: "Default apps"
        description: "What SUPER+RETURN, SUPER+B, SUPER+E and Ctrl+Shift+Esc start. The keybinds pick these up when Hyprland's config is reloaded."
    }

    Section {
        title: "Programs"

        Repeater {
            model: [["terminal", "Terminal", "also used by the launcher for terminal apps"], ["browser", "Browser", ""], ["fileManager", "File manager", ""], ["processManager", "Process manager", ""]]

            Setting {
                required property var modelData

                label: modelData[1]
                help: modelData[2]
                TextField {
                    fieldWidth: 320
                    value: Config.apps[modelData[0]]
                    onEdited: v => Config.set("apps." + modelData[0], v)
                }
            }
        }
    }

    RowLayout {
        Button {
            primary: true
            text: "Apply now (reload Hyprland)"
            onClicked: Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
}
