import QtQuick
import qs.config

// A line of text, committed with Enter or on leaving the field.
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property int fieldWidth: 240
    signal edited(string value)

    implicitWidth: fieldWidth
    implicitHeight: 30
    radius: 9
    color: Colours.alpha(Colours.accent, 0.08)
    border.width: 1
    border.color: input.activeFocus ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.22)

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: Colours.foreground
        font.family: "JetBrainsMono NF"
        font.pointSize: 12 * 0.75
        clip: true
        text: root.value
        onEditingFinished: {
            if (text !== root.value)
                root.edited(text);
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === "" && !input.activeFocus
            text: root.placeholder
            color: Colours.hint
            font: input.font
        }
    }
}
