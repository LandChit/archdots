import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// What a locked screen shows: the wallpaper, blurred and dimmed, a clock,
// and the password field. Used by the real lock, its preview, and the login
// screen (greeter.qml), which also asks for the user and shows `actions`
// (the session, restart, shut down) under the field.
Item {
    id: root

    required property string screenName
    property string message: ""
    property bool busy: false
    property alias password: input.text
    property bool askUser: false
    property alias user: userInput.text
    // [[label, id], ...] shown as small buttons under the field
    property var actions: []
    signal submitted(string password)
    signal escaped
    signal action(string name)

    function focusInput(): void {
        if (askUser && userInput.text === "")
            userInput.forceActiveFocus();
        else
            input.forceActiveFocus();
    }

    component Field: Rectangle {
        property bool focused: false
        property bool failed: false

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 320
        implicitHeight: 46
        radius: 23
        color: Colours.panel
        border.width: 1
        border.color: failed ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 0.7) : focused ? Colours.selectionBorder : Colours.panelBorder
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

        Field {
            visible: root.askUser
            focused: userInput.activeFocus
            Layout.bottomMargin: 4

            TextInput {
                id: userInput

                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                color: Colours.foreground
                font.family: "JetBrainsMono NF"
                font.pointSize: 14 * 0.75
                readOnly: root.busy
                KeyNavigation.tab: input
                Keys.onReturnPressed: input.forceActiveFocus()
                Keys.onEnterPressed: input.forceActiveFocus()

                BarText {
                    anchors.centerIn: parent
                    visible: userInput.text === ""
                    text: "User"
                    color: Colours.hint
                }
            }
        }

        Field {
            failed: root.message !== ""
            focused: input.activeFocus

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
                KeyNavigation.backtab: root.askUser ? userInput : null
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

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 18
            visible: root.actions.length > 0
            spacing: 8

            Repeater {
                model: root.actions

                Rectangle {
                    required property var modelData

                    implicitWidth: actionLabel.implicitWidth + 24
                    implicitHeight: 30
                    radius: 15
                    color: actionArea.containsMouse ? Colours.hover : Colours.alpha(Colours.panel, 0.7)
                    border.width: 1
                    border.color: Colours.panelBorder

                    BarText {
                        id: actionLabel

                        anchors.centerIn: parent
                        text: parent.modelData[0]
                        px: 11.5
                        color: Colours.alpha(Colours.foreground, 0.85)
                    }
                    MouseArea {
                        id: actionArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.action(parent.modelData[1])
                    }
                }
            }
        }
    }
}
