import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// One setting: label and optional help on the left, its control on the right
// (the default property).
Item {
    id: root

    property string label: ""
    property string help: ""
    default property alias control: holder.data

    Layout.fillWidth: true
    implicitHeight: Math.max(48, text.implicitHeight + 18, holder.childrenRect.height + 14)

    ColumnLayout {
        id: text

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: holder.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        BarText {
            Layout.fillWidth: true
            text: root.label
            wrapMode: Text.Wrap
        }
        BarText {
            Layout.fillWidth: true
            visible: root.help !== ""
            text: root.help
            px: 10.5
            color: Colours.subtext
            wrapMode: Text.Wrap
        }
    }

    Item {
        id: holder

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
