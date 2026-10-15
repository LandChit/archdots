import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// One screen's wallpaper, on the background layer. A change crossfades: the
// new picture loads (asynchronously) under the old one, then the old one
// fades out (Config.wallpaper.transitionMs) and lets go of its image.
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
        const target = path === "" ? "" : "file://" + path;
        const back = front === one ? two : one;
        if (String(front.source) === target) {
            // back to what is showing before the other one loaded: drop that
            if (!fade.running)
                back.source = "";
            return;
        }
        // The back one may hold the picture already (picked again while it
        // was still fading out). Setting the same source loads nothing, so no
        // status change would ever bring it to the front.
        if (String(back.source) === target && back.status === Image.Ready)
            reveal(back);
        else
            back.source = target;
    }

    // `picture` (loaded) to the front; the old one fades out above it.
    function reveal(picture: Image): void {
        const old = front;
        fade.stop();
        front = picture;
        picture.z = 0;
        old.z = 1;
        picture.opacity = 1;
        fade.target = old;
        fade.start();
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
            if (status === Image.Ready && picture !== root.front)
                root.reveal(picture);
            else if (status === Image.Error)
                console.warn("wallpaper: cannot load " + source + " (for .webp, install qt6-imageformats)");
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
        // a full-size picture per screen is a lot to keep hidden
        onFinished: {
            if (target && target !== root.front)
                target.source = "";
        }
    }
}
