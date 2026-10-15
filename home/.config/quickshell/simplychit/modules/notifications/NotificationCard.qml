import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// One notification: icon, app, summary, body, actions, a close
// button. `entry` is an item from Notifs.popups or Notifs.history.
Rectangle {
    id: root

    required property var entry
    property bool inHistory: false
    signal closed

    readonly property bool critical: entry.urgency === 2

    implicitHeight: column.implicitHeight + 22
    radius: 14
    color: Colours.alpha(Colours.mix(Colours.background, Colours.accent, 0.22), entry.urgency === 0 ? 0.85 : 0.94)
    border.width: 1
    border.color: critical ? Qt.rgba(224 / 255, 96 / 255, 78 / 255, 0.55) : Colours.panelBorder

    ColumnLayout {
        id: column

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 11
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 34
                implicitHeight: 34
                radius: 9
                color: Colours.alpha(Colours.accent, root.critical ? 0.25 : 0.12)
                clip: true

                Image {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    visible: (root.entry.icon ?? "") !== ""
                    source: root.entry.icon ?? ""
                    sourceSize: Qt.size(52, 52)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                BarText {
                    Layout.fillWidth: true
                    text: (root.entry.appName || "").toUpperCase() + (root.inHistory && root.entry.time ? "  ·  " + root.entry.time : "")
                    px: 9.5
                    color: Colours.subtext
                    font.letterSpacing: 0.6
                    elide: Text.ElideRight
                }
                BarText {
                    Layout.fillWidth: true
                    text: root.entry.summary
                    px: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            BarText {
                Layout.alignment: Qt.AlignTop
                text: "\u{f0156}"
                px: 13
                color: closeArea.containsMouse ? Colours.foreground : Colours.hint

                MouseArea {
                    id: closeArea

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closed()
                }
            }
        }

        BarText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.entry.body ?? ""
            px: 11.5
            color: Colours.alpha(Colours.foreground, 0.8)
            wrapMode: Text.Wrap
            maximumLineCount: root.inHistory ? 3 : 6
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.inHistory && (root.entry.actions ?? []).filter(a => a.id !== "default").length > 0
            spacing: 6

            Repeater {
                model: (root.entry.actions ?? []).filter(a => a.id !== "default")

                Rectangle {
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 8
                    color: actionArea.containsMouse ? Colours.alpha(Colours.accent, 0.25) : Colours.alpha(Colours.accent, 0.12)

                    BarText {
                        anchors.centerIn: parent
                        text: parent.modelData.text
                        px: 11
                    }

                    MouseArea {
                        id: actionArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            parent.modelData.action.invoke();
                            root.closed();
                        }
                    }
                }
            }
        }
    }

    // a click on the card runs its default action, if it has one
    MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: (root.entry.actions ?? []).some(a => a.id === "default") ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            const action = (root.entry.actions ?? []).find(a => a.id === "default");
            if (action && !root.inHistory) {
                action.action.invoke();
                root.closed();
            }
        }
    }
}
