import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.widgets

ColumnLayout {
    spacing: 14

    PageTitle {
        title: "Input"
        description: "Applied by Hyprland's config when it is reloaded. Settings for one particular device stay in ~/.config/archdots/hypr/input.lua."
    }

    Section {
        title: "Keyboard"

        Setting {
            label: "Layouts"
            help: "comma separated, e.g. us,de"
            TextField {
                value: Config.input.kb_layout
                onEdited: v => Config.set("input.kb_layout", v)
            }
        }
        Setting {
            label: "Variants"
            help: "one per layout, e.g. ,nodeadkeys"
            TextField {
                value: Config.input.kb_variant
                onEdited: v => Config.set("input.kb_variant", v)
            }
        }
        Setting {
            label: "Options"
            help: "xkb options, e.g. grp:alt_shift_toggle,caps:escape"
            TextField {
                value: Config.input.kb_options
                onEdited: v => Config.set("input.kb_options", v)
            }
        }
    }

    Section {
        title: "Pointer and touchpad"

        Setting {
            label: "Pointer speed"
            help: "-1 slowest, 0 default, 1 fastest"
            NumberField {
                value: Config.input.sensitivity
                from: -1
                to: 1
                step: 0.1
                onEdited: v => Config.set("input.sensitivity", v)
            }
        }
        Setting {
            label: "Natural scrolling"
            Switch {
                checked: Config.input.touchpad.natural_scroll
                onToggled: v => Config.set("input.touchpad.natural_scroll", v)
            }
        }
        Setting {
            label: "Tap to click"
            Switch {
                checked: Config.input.touchpad.tap_to_click
                onToggled: v => Config.set("input.touchpad.tap_to_click", v)
            }
        }
        Setting {
            label: "Ignore the touchpad while typing"
            Switch {
                checked: Config.input.touchpad.disable_while_typing
                onToggled: v => Config.set("input.touchpad.disable_while_typing", v)
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
