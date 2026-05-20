import QtQuick
import Quickshell
import Quickshell.Notifications
import "./"

// Notification server – replaces dunst.
// Toasts appear top-right on every screen.
Item {
    id: root

    NotificationServer {
        id: srv
        keepOnReload: true
        onNotification: function(n) {
            notifModel.append({
                nid:      n.id,
                appName:  n.appName  || "",
                summary:  n.summary  || "",
                body:     n.body     || "",
                urgency:  n.urgency,
                timeout:  n.expireTimeout > 0 ? n.expireTimeout : 5000,
                obj:      n
            })
        }
    }

    ListModel { id: notifModel }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData

            anchors { top: true; right: true }
            exclusiveZone: 0
            color: "transparent"
            width: 320
            height: toastCol.implicitHeight + 8

            Column {
                id: toastCol
                anchors { top: parent.top; right: parent.right; margins: 6 }
                spacing: 6

                Repeater {
                    model: notifModel
                    delegate: Rectangle {
                        required property int    index
                        required property string summary
                        required property string body
                        required property int    urgency
                        required property int    timeout
                        required property var    obj

                        width: 308
                        height: inner.implicitHeight + 20
                        radius: Palette.radius
                        color: urgency === 2 ? Qt.darker(Palette.color9, 1.2) : Palette.surface
                        border { color: urgency === 2 ? Palette.color9 : Palette.border; width: 1 }

                        Column {
                            id: inner
                            anchors { fill: parent; margins: 10 }
                            spacing: 4

                            Text {
                                text: summary
                                color: Palette.fg
                                font { family: Palette.font; pixelSize: 13; bold: true }
                                width: parent.width; elide: Text.ElideRight
                            }
                            Text {
                                visible: body.length > 0
                                text: body
                                color: Palette.muted
                                font { family: Palette.font; pixelSize: 12 }
                                width: parent.width
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3; elide: Text.ElideRight
                            }
                        }

                        // Slide in from right
                        NumberAnimation on x {
                            from: 320; to: 0
                            duration: 180; easing.type: Easing.OutCubic
                        }

                        Timer {
                            interval: timeout; running: true
                            onTriggered: { obj.close(); notifModel.remove(index) }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: { obj.close(); notifModel.remove(index) }
                        }
                    }
                }
            }
        }
    }
}
