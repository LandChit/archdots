import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// One screen's wallpaper, on the background layer. A change crossfades: the
// new picture loads (asynchronously) under the old one, then the old one
// fades out (Config.wallpaper.transitionMs).
PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property string path: Theme.wallpaperFor(modelData.name)

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Colours.background
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "simplychit-background"

    property Image front: one

    function show(): void {
        const back = front === one ? two : one;
        back.source = path === "" ? "" : "file://" + path;
    }

    onPathChanged: show()
    Component.onCompleted: show()

    component Picture: Image {
        id: picture

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(root.modelData.width, root.modelData.height)
        opacity: 0

        onStatusChanged: {
            if (status !== Image.Ready || picture === root.front)
                return;
            const old = root.front;
            root.front = picture;
            z = 0;
            old.z = 1;
            opacity = 1;
            fade.target = old;
            fade.start();
        }
    }

    Picture {
        id: one
    }
    Picture {
        id: two
    }

    NumberAnimation {
        id: fade

        property: "opacity"
        to: 0
        duration: Config.wallpaper.transitionMs
        easing.type: Easing.InOutQuad
    }
}
