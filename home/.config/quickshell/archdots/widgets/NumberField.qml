import QtQuick
import QtQuick.Layouts
import qs.config
import qs.widgets

// A number with − / + buttons and a typed value. `edited(v)` reports changes,
// clamped to from..to and rounded to `step`'s decimals.
RowLayout {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property string suffix: ""
    property int decimals: step < 1 ? (step < 0.1 ? 2 : 1) : 0
    signal edited(real value)

    function commit(v: real): void {
        if (isNaN(v))
            return;
        v = Math.max(from, Math.min(to, v));
        edited(Number(v.toFixed(decimals)));
    }

    spacing: 4

    component Button: Rectangle {
        property string glyph
        signal pressed

        implicitWidth: 26
        implicitHeight: 26
        radius: 8
        color: area.containsMouse ? Colours.hover : Colours.alpha(Colours.accent, 0.10)

        BarText {
            anchors.centerIn: parent
            text: parent.glyph
        }
        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressed()
        }
    }

    Button {
        glyph: "−"
        onPressed: root.commit(root.value - root.step)
    }

    Rectangle {
        implicitWidth: 72
        implicitHeight: 26
        radius: 8
        color: Colours.alpha(Colours.accent, 0.08)
        border.width: 1
        border.color: input.activeFocus ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.22)

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: Colours.foreground
            font.family: "JetBrainsMono NF"
            font.pointSize: 12 * 0.75
            text: activeFocus ? text : root.value.toFixed(root.decimals) + root.suffix
            validator: DoubleValidator {}
            onEditingFinished: root.commit(parseFloat(text))
            onActiveFocusChanged: {
                if (activeFocus)
                    text = root.value.toFixed(root.decimals);
            }
        }
    }

    Button {
        glyph: "+"
        onPressed: root.commit(root.value + root.step)
    }
}
