pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Monitors: what is connected, applying a layout live, keeping or reverting
// it, and one saved layout ("profile") per set of connected monitors.
//
// Monitors are identified by their description (make, model, serial), not
// the port, which changes between docks and cables. A profile's key is the
// sorted descriptions of everything connected, joined with "|". Profiles live
// in settings.json ("displays.profiles"); hypr/config/monitor.lua applies the
// active one when Hyprland starts, and this applies the matching one live
// whenever a monitor is plugged in or out.
//
// apply() changes the layout at once and asks to keep it: unless keep() is
// called within 15 seconds, revert() puts the old one back, so a mode the
// screen cannot show never leaves you without a picture.
Singleton {
    id: root

    // hyprctl monitors all -j, as given
    property var monitors: []
    // what was live before the change being confirmed
    property var previous: []
    property var pendingDrafts: []
    property int countdown: 0
    readonly property bool confirming: countdown > 0
    property bool identifying: false

    readonly property string currentKey: monitors.map(m => m.description).sort().join("|")
    readonly property var profile: (Config.displays.profiles ?? {})[currentKey] ?? null

    signal refreshed

    function refresh(): void {
        reader.running = true;
    }

    function modeOf(m: var): string {
        return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2);
    }

    // a layout entry from a live monitor
    function draftOf(m: var): var {
        return {
            name: m.name,
            description: m.description,
            enabled: !m.disabled,
            mode: modeOf(m),
            width: m.width,
            height: m.height,
            x: m.x,
            y: m.y,
            scale: m.scale,
            transform: m.transform,
            vrr: m.vrr === true ? 1 : m.vrr === false ? 0 : (m.vrr ?? 0),
            mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
            modes: (m.availableModes ?? []).map(s => s.replace(/Hz$/, ""))
        };
    }

    function specOf(d: var): var {
        if (!d.enabled)
            return { enabled: false };
        const spec = { enabled: true, mode: d.mode, position: Math.round(d.x) + "x" + Math.round(d.y), scale: d.scale, transform: d.transform, vrr: d.vrr };
        if (d.mirror)
            spec.mirror = d.mirror;
        return spec;
    }

    function lua(description: string, spec: var): string {
        const out = "output = " + JSON.stringify("desc:" + description);
        if (!spec.enabled)
            return "hl.monitor({ " + out + ", disabled = true })";
        let s = out + ", mode = " + JSON.stringify(spec.mode) + ", position = " + JSON.stringify(spec.position)
            + ", scale = " + Number(spec.scale) + ", transform = " + Math.round(spec.transform) + ", vrr = " + Math.round(spec.vrr);
        if (spec.mirror)
            s += ", mirror = " + JSON.stringify(spec.mirror);
        return "hl.monitor({ " + s + " })";
    }

    function workspacesLua(workspaces: var): string {
        return Object.keys(workspaces ?? {}).map(ws => "hl.workspace_rule({ workspace = " + JSON.stringify(String(ws)) + ", monitor = " + JSON.stringify("desc:" + workspaces[ws]) + " })").join("; ");
    }

    function run(drafts: var, workspaces: var): void {
        // enabled ones first: never a moment with every screen off
        const ordered = drafts.slice().sort((a, b) => b.enabled - a.enabled);
        const code = ordered.map(d => lua(d.description, specOf(d))).join("; ")
            + (workspaces ? "; " + workspacesLua(workspaces) : "");
        Quickshell.execDetached(["hyprctl", "eval", code]);
        settle.restart();
    }

    function apply(drafts: var): void {
        if (!drafts.some(d => d.enabled))
            return;
        if (!confirming)
            previous = monitors.map(draftOf);
        pendingDrafts = drafts;
        run(drafts, null);
        countdown = 15;
        tick.restart();
    }

    function keep(): void {
        // only a change waiting to be confirmed can be kept
        if (!confirming || pendingDrafts.length === 0)
            return;
        tick.stop();
        countdown = 0;
        const monitorsByDesc = {};
        for (const d of pendingDrafts)
            monitorsByDesc[d.description] = specOf(d);
        save(monitorsByDesc, profile ? profile.workspaces : undefined);
    }

    function revert(): void {
        tick.stop();
        countdown = 0;
        if (previous.length > 0)
            run(previous, null);
    }

    function setWorkspaces(workspaces: var): void {
        const monitorsByDesc = profile ? profile.monitors : Object.fromEntries(monitors.map(m => [m.description, specOf(draftOf(m))]));
        save(monitorsByDesc, workspaces);
        Quickshell.execDetached(["hyprctl", "eval", workspacesLua(workspaces)]);
    }

    function save(monitorsByDesc: var, workspaces: var): void {
        const profiles = Object.assign({}, Config.displays.profiles ?? {});
        profiles[currentKey] = { monitors: monitorsByDesc, workspaces: workspaces ?? {} };
        Config.set("displays.profiles", profiles);
        Qt.callLater(() => Config.set("displays.active", currentKey));
    }

    // A set of monitors with a saved layout gets it, without asking: it is
    // the layout you kept last time this set was connected.
    function applySaved(): void {
        if (!profile || confirming || Config.displays.active === currentKey && !hotplugged)
            return;
        const drafts = monitors.map(m => {
            const saved = profile.monitors[m.description];
            if (!saved)
                return draftOf(m);
            const d = draftOf(m);
            d.enabled = saved.enabled !== false;
            if (saved.mode)
                d.mode = saved.mode;
            if (saved.position) {
                const [x, y] = saved.position.split("x").map(Number);
                d.x = x;
                d.y = y;
            }
            for (const k of ["scale", "transform", "vrr"])
                if (saved[k] !== undefined)
                    d[k] = saved[k];
            d.mirror = saved.mirror ?? "";
            return d;
        });
        hotplugged = false;
        run(drafts, profile.workspaces);
        Config.set("displays.active", currentKey);
    }

    property bool hotplugged: false

    Process {
        id: reader

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.refreshed();
                root.applySaved();
            }
        }
    }

    // re-read once a change has landed
    Timer {
        id: settle

        interval: 700
        onTriggered: root.refresh()
    }

    Timer {
        id: tick

        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0)
                root.revert();
        }
    }

    Timer {
        id: hotplug

        interval: 1200
        onTriggered: {
            root.hotplugged = true;
            root.refresh();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2"].includes(event.name))
                hotplug.restart();
        }
    }

    Component.onCompleted: refresh()
}
