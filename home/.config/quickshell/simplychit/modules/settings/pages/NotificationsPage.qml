import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

ColumnLayout {
    spacing: 14

    PageTitle {
        title: "Notifications"
    }

    Section {
        title: "Popups"

        Setting {
            label: "Do not disturb"
            help: "only critical notifications show; the rest still go into the history"
            Switch {
                checked: Notifs.dnd
                onToggled: v => Notifs.dnd = v
            }
        }
        Setting {
            label: "How long a popup stays"
            help: "seconds, unless the app asks for something else; critical ones stay until closed"
            NumberField {
                value: Config.notifications.timeout
                from: 1
                to: 60
                suffix: " s"
                onEdited: v => Config.set("notifications.timeout", v)
            }
        }
    }

    Section {
        title: "Do not disturb every day"

        Setting {
            label: "On a schedule"
            Switch {
                checked: Config.notifications.schedule.enabled
                onToggled: v => Config.set("notifications.schedule.enabled", v)
            }
        }
        Setting {
            label: "From"
            help: "HH:mm"
            TextField {
                fieldWidth: 90
                value: Config.notifications.schedule.from
                onEdited: v => Config.set("notifications.schedule.from", v)
            }
        }
        Setting {
            label: "To"
            help: "HH:mm; may be after midnight"
            TextField {
                fieldWidth: 90
                value: Config.notifications.schedule.to
                onEdited: v => Config.set("notifications.schedule.to", v)
            }
        }
    }

    Section {
        title: "Sounds"
        description: "From the freedesktop sound theme."

        Setting {
            label: "Notification sound"
            help: "when a popup shows; not under do not disturb, and not for apps that ask for silence"
            Switch {
                checked: Config.sounds.notifications
                onToggled: v => Config.set("sounds.notifications", v)
            }
        }
        Setting {
            label: "Volume change sound"
            help: "once the level settles, from the keys, the bar or any app"
            Switch {
                checked: Config.sounds.volume
                onToggled: v => Config.set("sounds.volume", v)
            }
        }
    }

    Section {
        title: "Event toasts"
        description: "Small messages from the shell itself."

        Repeater {
            model: [["charging", "Charger plugged in or out"], ["locks", "Caps Lock and Num Lock"], ["keyboardLayout", "Keyboard layout changes"], ["audioDevice", "Audio output changes"], ["vpn", "VPN connects or disconnects"], ["nowPlaying", "A new track starts"], ["dnd", "Do not disturb switches"]]

            Setting {
                required property var modelData

                label: modelData[1]
                Switch {
                    checked: Config.toasts[modelData[0]]
                    onToggled: v => Config.set("toasts." + modelData[0], v)
                }
            }
        }
    }
}
