import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./"

PanelWindow {
    id: root
    visible: false
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            emojiSearch.text = ""
            emojiSearch.forceActiveFocus()
            root.filtered = root.all
        }
    }

    property var all: [
        {e:"😀",n:"grinning"},{e:"😃",n:"smiley"},{e:"😄",n:"smile"},{e:"😁",n:"grin"},
        {e:"😆",n:"laughing"},{e:"😅",n:"sweat smile"},{e:"🤣",n:"rofl"},{e:"😂",n:"joy"},
        {e:"🙂",n:"slightly smiling"},{e:"😊",n:"blush"},{e:"😇",n:"innocent"},
        {e:"🥰",n:"smiling hearts"},{e:"😍",n:"heart eyes"},{e:"🤩",n:"star struck"},
        {e:"😘",n:"kissing heart"},{e:"😋",n:"yum"},{e:"😛",n:"tongue"},
        {e:"😜",n:"winking tongue"},{e:"🤪",n:"zany"},{e:"🤑",n:"money mouth"},
        {e:"🤗",n:"hugging"},{e:"🤭",n:"hand over mouth"},{e:"🤫",n:"shushing"},
        {e:"🤔",n:"thinking"},{e:"🤐",n:"zipper mouth"},{e:"😐",n:"neutral"},
        {e:"😶",n:"no mouth"},{e:"😏",n:"smirk"},{e:"😒",n:"unamused"},
        {e:"🙄",n:"eye roll"},{e:"😬",n:"grimacing"},{e:"🤥",n:"lying"},
        {e:"😌",n:"relieved"},{e:"😔",n:"pensive"},{e:"😪",n:"sleepy"},
        {e:"😴",n:"sleeping"},{e:"😷",n:"mask"},{e:"🤒",n:"thermometer"},
        {e:"🤕",n:"bandage"},{e:"🤢",n:"nauseated"},{e:"🤮",n:"vomiting"},
        {e:"🤧",n:"sneezing"},{e:"🥵",n:"hot"},{e:"🥶",n:"cold"},
        {e:"🥴",n:"woozy"},{e:"😵",n:"dizzy"},{e:"🤯",n:"exploding head"},
        {e:"🥳",n:"partying"},{e:"😎",n:"sunglasses"},{e:"🤓",n:"nerd"},
        {e:"🧐",n:"monocle"},{e:"😕",n:"confused"},{e:"😟",n:"worried"},
        {e:"🙁",n:"frowning"},{e:"😮",n:"open mouth"},{e:"😲",n:"astonished"},
        {e:"😳",n:"flushed"},{e:"🥺",n:"pleading"},{e:"😦",n:"frowning open"},
        {e:"😨",n:"fearful"},{e:"😰",n:"anxious"},{e:"😢",n:"cry"},
        {e:"😭",n:"sob"},{e:"😱",n:"scream"},{e:"😖",n:"confounded"},
        {e:"😣",n:"persevering"},{e:"😞",n:"disappointed"},{e:"😩",n:"weary"},
        {e:"🥱",n:"yawning"},{e:"😤",n:"triumph"},{e:"😡",n:"pouting"},
        {e:"😠",n:"angry"},{e:"🤬",n:"symbols mouth"},{e:"😈",n:"smiling devil"},
        {e:"💀",n:"skull"},{e:"💩",n:"poop"},{e:"🤡",n:"clown"},
        {e:"👻",n:"ghost"},{e:"👽",n:"alien"},{e:"🤖",n:"robot"},
        {e:"👋",n:"wave"},{e:"🤚",n:"raised back hand"},{e:"✋",n:"raised hand"},
        {e:"🖖",n:"vulcan salute"},{e:"👌",n:"ok hand"},{e:"🤌",n:"pinched fingers"},
        {e:"✌️",n:"victory"},{e:"🤞",n:"crossed fingers"},{e:"🤟",n:"love you"},
        {e:"🤘",n:"horns"},{e:"🤙",n:"call me"},{e:"👈",n:"pointing left"},
        {e:"👉",n:"pointing right"},{e:"👆",n:"pointing up"},{e:"👇",n:"pointing down"},
        {e:"👍",n:"thumbs up"},{e:"👎",n:"thumbs down"},{e:"✊",n:"raised fist"},
        {e:"👊",n:"oncoming fist"},{e:"👏",n:"clapping"},{e:"🙌",n:"raising hands"},
        {e:"🙏",n:"folded hands"},{e:"💪",n:"flexed biceps"},
        {e:"❤️",n:"red heart"},{e:"🧡",n:"orange heart"},{e:"💛",n:"yellow heart"},
        {e:"💚",n:"green heart"},{e:"💙",n:"blue heart"},{e:"💜",n:"purple heart"},
        {e:"🖤",n:"black heart"},{e:"🤍",n:"white heart"},{e:"💔",n:"broken heart"},
        {e:"💕",n:"two hearts"},{e:"💖",n:"sparkling heart"},{e:"💘",n:"heart arrow"},
        {e:"⭐",n:"star"},{e:"🌟",n:"glowing star"},{e:"✨",n:"sparkles"},
        {e:"🔥",n:"fire"},{e:"💥",n:"collision"},{e:"❄️",n:"snowflake"},
        {e:"💧",n:"droplet"},{e:"🌈",n:"rainbow"},{e:"⚡",n:"lightning"},
        {e:"🌙",n:"moon"},{e:"☀️",n:"sun"},{e:"🌊",n:"wave water"},
        {e:"💻",n:"laptop"},{e:"🖥️",n:"desktop"},{e:"📱",n:"phone"},
        {e:"⌨️",n:"keyboard"},{e:"🖱️",n:"mouse"},{e:"📷",n:"camera"},
        {e:"🎵",n:"music note"},{e:"🎮",n:"gamepad"},{e:"📚",n:"books"},
        {e:"✏️",n:"pencil"},{e:"📌",n:"pushpin"},{e:"🔑",n:"key"},
        {e:"🔒",n:"locked"},{e:"🔓",n:"unlocked"},{e:"⚙️",n:"gear"},
        {e:"🔧",n:"wrench"},{e:"🔨",n:"hammer"},{e:"💡",n:"bulb"},
        {e:"🔋",n:"battery"},{e:"📦",n:"package"},{e:"🗑️",n:"trash"},
        {e:"🍕",n:"pizza"},{e:"🍔",n:"burger"},{e:"🍜",n:"noodles"},
        {e:"🍣",n:"sushi"},{e:"🍦",n:"ice cream"},{e:"🍰",n:"cake"},
        {e:"🍺",n:"beer"},{e:"☕",n:"coffee"},{e:"🧃",n:"juice"},
        {e:"🐶",n:"dog"},{e:"🐱",n:"cat"},{e:"🐰",n:"rabbit"},
        {e:"🦊",n:"fox"},{e:"🐻",n:"bear"},{e:"🐼",n:"panda"},
        {e:"🐯",n:"tiger"},{e:"🦁",n:"lion"},{e:"🐸",n:"frog"},
        {e:"🐧",n:"penguin"},{e:"🦆",n:"duck"},{e:"🦅",n:"eagle"},
        {e:"⚽",n:"soccer"},{e:"🏀",n:"basketball"},{e:"🎾",n:"tennis"},
        {e:"🏋️",n:"weightlifter"},{e:"🚗",n:"car"},{e:"✈️",n:"airplane"},
        {e:"🚀",n:"rocket"},{e:"🏠",n:"house"},{e:"🏖️",n:"beach"},
        {e:"🎉",n:"party popper"},{e:"🎊",n:"confetti"},{e:"🎁",n:"gift"},
        {e:"🏆",n:"trophy"},{e:"🥇",n:"gold medal"},{e:"🎯",n:"bullseye"},
        {e:"🎨",n:"palette"},{e:"🎭",n:"performing arts"},{e:"🎬",n:"clapper"},
        {e:"📢",n:"loudspeaker"},{e:"📣",n:"megaphone"},{e:"🔔",n:"bell"},
        {e:"💬",n:"speech bubble"},{e:"💭",n:"thought bubble"},{e:"❓",n:"question"},
        {e:"❗",n:"exclamation"},{e:"✅",n:"check mark"},{e:"❌",n:"cross mark"},
        {e:"⚠️",n:"warning"},{e:"🚫",n:"no entry"},{e:"💯",n:"hundred"},
        {e:"🆕",n:"new"},{e:"🆒",n:"cool"},{e:"🆓",n:"free"},
    ]

    property var filtered: all

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: root.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 440; height: 420
            color: Palette.bg
            radius: Palette.radius
            border { color: Palette.border; width: 1 }
            MouseArea { anchors.fill: parent }

            Column {
                anchors { fill: parent; margins: 12 }
                spacing: 8

                Rectangle {
                    width: parent.width; height: 38
                    color: Palette.surface
                    radius: Palette.radius
                    border { color: Palette.accent; width: 1 }

                    TextInput {
                        id: emojiSearch
                        anchors { fill: parent; margins: 8 }
                        color: Palette.fg
                        font { family: Palette.font; pixelSize: 14 }
                        clip: true
                        onTextChanged: {
                            const q = text.toLowerCase()
                            root.filtered = q
                                ? root.all.filter(x => x.n.includes(q))
                                : root.all
                        }
                        Keys.onEscapePressed: root.visible = false
                    }
                    Text {
                        visible: emojiSearch.text.length === 0
                        anchors { fill: parent; margins: 8 }
                        verticalAlignment: Text.AlignVCenter
                        text: "Search emoji…"
                        color: Palette.muted
                        font { family: Palette.font; pixelSize: 14 }
                    }
                }

                GridView {
                    width: parent.width
                    height: parent.height - 46
                    clip: true
                    cellWidth: 46; cellHeight: 46
                    model: root.filtered

                    delegate: Rectangle {
                        required property var modelData
                        width: 42; height: 42
                        radius: 6
                        color: hov ? Palette.surface : "transparent"
                        property bool hov: false

                        Text {
                            anchors.centerIn: parent
                            text: modelData.e
                            font.pixelSize: 22
                        }

                        ToolTip.visible: hov
                        ToolTip.text: modelData.n

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: parent.hov = true
                            onExited:  parent.hov = false
                            onClicked: {
                                copyProc.command = ["bash", "-c",
                                    "printf '%s' '" + parent.modelData.e + "' | wl-copy"]
                                copyProc.running = true
                                root.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    Process { id: copyProc; command: [] }
}
