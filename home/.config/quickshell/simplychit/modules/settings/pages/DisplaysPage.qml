import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services
import qs.widgets

// Arrange, enable and set up monitors, Windows-style. Drag the screens on the
// canvas (they snap to each other's edges and cannot overlap), pick a screen
// to change its mode, scale, rotation, VRR or mirroring, then Apply: it takes
// effect at once and reverts after 15 seconds unless kept. Kept layouts are
// remembered per set of connected monitors and come back when that set is
// plugged in again.
ColumnLayout {
    id: page

    spacing: 14

    property var drafts: []
    property int selected: 0
    readonly property var current: drafts[selected] ?? null
    readonly property bool dirty: JSON.stringify(drafts.map(Displays.specOf)) !== JSON.stringify(Displays.monitors.map(Displays.draftOf).map(Displays.specOf))

    function load(): void {
        drafts = Displays.monitors.map(Displays.draftOf);
        selected = Math.max(0, Math.min(selected, drafts.length - 1));
    }

    function update(index: int, changes: var): void {
        const next = drafts.slice();
        next[index] = Object.assign({}, next[index], changes);
        drafts = normalised(next);
    }

    // Logical size: what the screen covers in the layout. Scaled, and turned
    // for 90/270 degree rotations.
    function sizeOf(d: var): var {
        const [w, h] = d.mode.split("@")[0].split("x").map(Number);
        const lw = w / d.scale, lh = h / d.scale;
        return d.transform % 2 === 1 ? { w: lh, h: lw } : { w: lw, h: lh };
    }

    // the top-left screen at 0x0
    function normalised(list: var): var {
        const on = list.filter(d => d.enabled && !d.mirror);
        if (on.length === 0)
            return list;
        const minX = Math.min(...on.map(d => d.x)), minY = Math.min(...on.map(d => d.y));
        return list.map(d => Object.assign({}, d, { x: Math.round(d.x - minX), y: Math.round(d.y - minY) }));
    }

    function overlaps(a: var, b: var): bool {
        const sa = sizeOf(a), sb = sizeOf(b);
        return a.x < b.x + sb.w - 1 && a.x + sa.w > b.x + 1 && a.y < b.y + sb.h - 1 && a.y + sa.h > b.y + 1;
    }

    // Snap a dropped screen's edges to the others' within `snap` layout px.
    function placed(index: int, x: real, y: real): var {
        const me = Object.assign({}, drafts[index], { x: x, y: y });
        const size = sizeOf(me);
        const snap = 40;
        let bestX = null, bestY = null;
        for (let i = 0; i < drafts.length; i++) {
            const o = drafts[i];
            if (i === index || !o.enabled || o.mirror)
                continue;
            const so = sizeOf(o);
            for (const [candidate, target] of [[x, o.x + so.w], [x + size.w, o.x], [x, o.x], [x + size.w, o.x + so.w]]) {
                const delta = target - candidate;
                if (Math.abs(delta) < snap && (bestX === null || Math.abs(delta) < Math.abs(bestX)))
                    bestX = delta;
            }
            for (const [candidate, target] of [[y, o.y + so.h], [y + size.h, o.y], [y, o.y], [y + size.h, o.y + so.h]]) {
                const delta = target - candidate;
                if (Math.abs(delta) < snap && (bestY === null || Math.abs(delta) < Math.abs(bestY)))
                    bestY = delta;
            }
        }
        me.x = x + (bestX ?? 0);
        me.y = y + (bestY ?? 0);
        return me;
    }

    Component.onCompleted: {
        Displays.refresh();
        load();
    }

    Connections {
        target: Displays

        function onRefreshed(): void {
            if (!Displays.confirming)
                page.load();
        }
    }

    PageTitle {
        title: "Displays"
        description: "Drag the screens to arrange them. Apply takes effect straight away and goes back after 15 seconds unless you keep it, so a mode a screen cannot show fixes itself. Kept layouts are remembered for this set of monitors."
    }

    // ── the canvas ───────────────────────────────────────────────────────
    Rectangle {
        id: canvas

        Layout.fillWidth: true
        implicitHeight: 300
        radius: 14
        color: Colours.alpha(Colours.background, 0.5)
        border.width: 1
        border.color: Colours.alpha(Colours.accent, 0.16)

        readonly property var placedDrafts: page.drafts.filter(d => d.enabled && !d.mirror)
        // framed from the top-left screen, wherever the layout starts
        readonly property real minX: placedDrafts.length ? Math.min(...placedDrafts.map(d => d.x)) : 0
        readonly property real minY: placedDrafts.length ? Math.min(...placedDrafts.map(d => d.y)) : 0
        readonly property real spanW: Math.max(1, ...placedDrafts.map(d => d.x + page.sizeOf(d).w)) - minX
        readonly property real spanH: Math.max(1, ...placedDrafts.map(d => d.y + page.sizeOf(d).h)) - minY
        // layout px -> canvas px, leaving room to drag past the edges
        readonly property real factor: Math.min((width - 80) / (spanW * 1.3), (height - 60) / (spanH * 1.3))
        readonly property real originX: (width - spanW * factor) / 2
        readonly property real originY: (height - spanH * factor) / 2

        Repeater {
            model: page.drafts.length

            Rectangle {
                id: screen

                required property int index
                readonly property var draft: page.drafts[index]
                readonly property var size: page.sizeOf(draft)

                visible: draft.enabled && !draft.mirror
                x: canvas.originX + (draft.x - canvas.minX) * canvas.factor
                y: canvas.originY + (draft.y - canvas.minY) * canvas.factor
                width: size.w * canvas.factor
                height: size.h * canvas.factor
                radius: 8
                color: page.selected === index ? Colours.alpha(Colours.accentBright, 0.32) : Colours.alpha(Colours.accent, 0.20)
                border.width: 2
                border.color: page.selected === index ? Colours.selectionBorder : Colours.alpha(Colours.accent, 0.40)
                z: drag.active ? 10 : 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: screen.draft.name
                        font.weight: Font.Medium
                    }
                    BarText {
                        Layout.alignment: Qt.AlignHCenter
                        text: screen.draft.mode.split("@")[0] + (screen.draft.scale !== 1 ? " · " + screen.draft.scale + "×" : "")
                        px: 10
                        color: Colours.subtext
                    }
                }

                property point start
                MouseArea {
                    id: drag

                    property bool active: drag.drag.active

                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    drag.target: screen
                    onPressed: {
                        page.selected = screen.index;
                        screen.start = Qt.point(screen.x, screen.y);
                    }
                    onReleased: {
                        const lx = (screen.x - canvas.originX) / canvas.factor + canvas.minX;
                        const ly = (screen.y - canvas.originY) / canvas.factor + canvas.minY;
                        const moved = page.placed(screen.index, lx, ly);
                        const clash = page.drafts.some((o, i) => i !== screen.index && o.enabled && !o.mirror && page.overlaps(moved, o));
                        if (clash) {
                            // back where it was: screens may touch, not overlap
                            screen.x = screen.start.x;
                            screen.y = screen.start.y;
                            page.drafts = page.drafts.slice();
                            return;
                        }
                        page.update(screen.index, { x: moved.x, y: moved.y });
                    }
                }
            }
        }

        BarText {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 12
            text: page.current ? page.current.name + " at " + Math.round(page.current.x) + "×" + Math.round(page.current.y) : ""
            px: 10.5
            color: Colours.hint
        }
    }

    RowLayout {
        spacing: 8

        Repeater {
            model: page.drafts

            Button {
                required property var modelData
                required property int index

                text: modelData.name + (modelData.enabled ? "" : " (off)")
                primary: page.selected === index
                onClicked: page.selected = index
            }
        }
        Item {
            Layout.fillWidth: true
        }
        Button {
            text: "Identify"
            onClicked: {
                Displays.identifying = true;
                identifyTimer.restart();
            }
        }
        Button {
            text: "Undo changes"
            enabled: page.dirty
            onClicked: page.load()
        }
        Button {
            primary: true
            text: "Apply"
            enabled: page.dirty && !Displays.confirming && page.drafts.some(d => d.enabled)
            onClicked: Displays.apply(page.drafts)
        }
    }

    Timer {
        id: identifyTimer

        interval: 2500
        onTriggered: Displays.identifying = false
    }

    // ── the selected screen ──────────────────────────────────────────────
    Section {
        visible: page.current !== null
        title: page.current ? page.current.name + " · " + page.current.description : ""

        Setting {
            label: "Use this screen"
            help: page.drafts.filter(d => d.enabled).length === 1 && page.current && page.current.enabled ? "the only screen on: it stays on" : ""
            Switch {
                checked: page.current ? page.current.enabled : false
                onToggled: v => {
                    if (!v && page.drafts.filter(d => d.enabled).length <= 1)
                        return;
                    page.update(page.selected, { enabled: v });
                }
            }
        }
        Setting {
            label: "Resolution and refresh rate"
            Dropdown {
                fieldWidth: 240
                options: page.current ? [...new Set([page.current.mode].concat(page.current.modes))].map(m => [m, m.replace(/@(\d+)\.\d+$/, " @ $1 Hz")]) : []
                value: page.current ? page.current.mode : ""
                onChosen: v => page.update(page.selected, { mode: v })
            }
        }
        Setting {
            label: "Scale"
            help: "1 is 100%"
            Choice {
                options: [[1, "100%"], [1.25, "125%"], [1.5, "150%"], [1.6, "160%"], [2, "200%"]]
                value: page.current ? page.current.scale : 1
                onChosen: v => page.update(page.selected, { scale: v })
            }
        }
        Setting {
            label: "Rotation"
            Choice {
                options: [[0, "0°"], [1, "90°"], [2, "180°"], [3, "270°"]]
                value: page.current ? page.current.transform : 0
                onChosen: v => page.update(page.selected, { transform: v })
            }
        }
        Setting {
            label: "Variable refresh rate"
            Choice {
                options: [[0, "Off"], [1, "On"], [2, "Fullscreen only"]]
                value: page.current ? page.current.vrr : 0
                onChosen: v => page.update(page.selected, { vrr: v })
            }
        }
        Setting {
            label: "Mirror"
            help: "show another screen's picture instead of its own"
            Dropdown {
                fieldWidth: 200
                options: [["", "No"]].concat(page.drafts.filter((d, i) => i !== page.selected && d.enabled).map(d => [d.name, d.name]))
                value: page.current ? page.current.mirror : ""
                onChosen: v => page.update(page.selected, { mirror: v })
            }
        }
    }

    // ── workspaces ───────────────────────────────────────────────────────
    Section {
        title: "Workspaces"
        description: "Which screen each workspace opens on. Saved with this set of monitors."

        Repeater {
            model: 10

            Setting {
                id: wsRow

                required property int index
                readonly property string ws: String(index + 1)
                readonly property var saved: Displays.profile ? (Displays.profile.workspaces ?? {}) : {}

                label: "Workspace " + ws
                Dropdown {
                    fieldWidth: 260
                    options: [["", "Any (Hyprland decides)"]].concat(Displays.monitors.map(m => [m.description, m.name + " · " + m.description]))
                    value: wsRow.saved[wsRow.ws] ?? ""
                    onChosen: v => {
                        const next = Object.assign({}, wsRow.saved);
                        if (v === "")
                            delete next[wsRow.ws];
                        else
                            next[wsRow.ws] = v;
                        Displays.setWorkspaces(next);
                    }
                }
            }
        }
    }
}
