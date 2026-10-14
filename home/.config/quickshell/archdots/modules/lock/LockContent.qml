import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// What a locked screen shows: the wallpaper, blurred and dimmed, a clock,
// and the password field. Used by the real lock and by its preview.
Item {
    id: root

    required property string screenName
    property string message: ""
    property bool busy: false
    property alias password: input.text
    signal submitted(string password)
    signal escaped

    function focusInput(): void {
        input.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.background
    }

    Image {
        id: wallpaper

        anchors.fill: parent
        source: Theme.wallpaperFor(root.screenName) === "" ? "" : "file://" + Theme.wallpaperFor(root.screenName)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        brightness: -0.25
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.alpha(Colours.background, 0.35)
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(clock.date, "hh:mm")
            px: 96
            font.weight: Font.Light
            color: Colours.foreground
        }
        BarText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.date, "dddd, d MMMM")
            px: 16
            color: Colours.alpha(Colours.foreground, 0.75)
            Layout.bottomMargin: 30
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 320
            implicitHeight: 46
            radius: 23
            color: Colours.panel
            border.width: 1
            border.color: root.message !== "" ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 0.7) : input.activeFocus ? Colours.selectionBorder : Colours.panelBorder

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: Colours.foreground
                font.family: "JetBrainsMono NF"
                font.pointSize: 14 * 0.75
                readOnly: root.busy
                focus: true
                Keys.onReturnPressed: root.submitted(text)
                Keys.onEnterPressed: root.submitted(text)
                Keys.onEscapePressed: {
                    text = "";
                    root.escaped();
                }

                BarText {
                    anchors.centerIn: parent
                    visible: input.text === ""
                    text: root.busy ? "Checking…" : "Password"
                    color: Colours.hint
                }
            }
        }

        BarText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            text: root.message
            px: 12
            color: Qt.rgba(224 / 255, 96 / 255, 78 / 255, 1)
            visible: text !== ""
        }
    }
}
