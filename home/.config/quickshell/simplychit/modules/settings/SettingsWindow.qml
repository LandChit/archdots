import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// The settings app: a normal window with a page per area. Every page edits
// ~/.config/simplychit/settings.json through Config.set, so what it changes is
// data the shell and the Hyprland config both read, and hand edits keep
// working. Pages are only built while shown.
FloatingWindow {
    id: root

    title: "SimplyChit settings"
    visible: SettingsState.open
    implicitWidth: 1000
    implicitHeight: 700
    minimumSize: Qt.size(820, 520)
    color: Colours.mix(Colours.background, Colours.accent, 0.08)

    onVisibleChanged: {
        if (!visible)
            SettingsState.open = false;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // the sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 210
            color: Colours.alpha(Colours.background, 0.55)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 3

                BarText {
                    text: "Settings"
                    px: 17
                    font.weight: Font.Medium
                    Layout.margins: 8
                    Layout.bottomMargin: 12
                }

                Repeater {
                    model: SettingsState.pages

                    Rectangle {
                        id: item

                        required property var modelData
                        readonly property bool current: SettingsState.page === modelData[0]

                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 10
                        color: current ? Colours.selection : area.containsMouse ? Colours.hover : "transparent"
                        border.width: 1
                        border.color: current ? Colours.selectionBorder : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            spacing: 12

                            BarText {
                                text: item.modelData[2]
                                px: 15
                                color: item.current ? Colours.highlight : Colours.alpha(Colours.foreground, 0.75)
                            }
                            BarText {
                                Layout.fillWidth: true
                                text: item.modelData[1]
                                color: item.current ? Colours.foreground : Colours.alpha(Colours.foreground, 0.8)
                            }
                        }

                        MouseArea {
                            id: area

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsState.page = item.modelData[0]
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                BarText {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    text: "~/.config/simplychit/settings.json"
                    px: 10
                    color: Colours.hint
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        // the page
        Flickable {
            id: scroller

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: loader.height + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Loader {
                id: loader

                x: 28
                y: 24
                width: scroller.width - 56
                active: root.visible
                source: "pages/" + SettingsState.page.charAt(0).toUpperCase() + SettingsState.page.slice(1) + "Page.qml"
                onSourceChanged: scroller.contentY = 0
            }
        }
    }
}
