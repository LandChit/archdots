pragma Singleton

import QtQuick
import Quickshell
import qs.config

// What each bar shows, for Bar.qml and the settings app's Bar page.
//
// bar.left / bar.center / bar.right are the default layout: widget names, in
// order. A screen can have its own in bar.monitors, keyed by Hyprland's
// description of the monitor ("BOE 0x094D", so it follows the monitor to
// another port or dock) or by port name ("eDP-1"); an entry with any of
// left/center/right uses its own layout, with the default for the sections
// it leaves out. Other bar keys work per screen too ({"showCpu": false}).
Singleton {
    id: root

    readonly property var widgets: ({
        workspaces: "Workspaces",
        special: "Special workspaces",
        title: "Window title",
        media: "What's playing",
        indicators: "Indicators (recording, awake, do not disturb)",
        volume: "Volume",
        cpu: "CPU temperature",
        battery: "Battery",
        clock: "Clock"
    })
    // drawn together in one island when next to each other (Status.qml)
    readonly property var statusParts: ["indicators", "volume", "cpu", "battery"]
    readonly property var sections: [["left", "Left"], ["center", "Centre"], ["right", "Right"]]

    // Older settings name the four status parts "resources" as one; anything
    // unknown is dropped.
    function normalize(list: var): var {
        const out = [];
        for (const name of Array.from(list ?? []))
            for (const n of name === "resources" ? statusParts : [name])
                if (widgets[n] !== undefined && !out.includes(n))
                    out.push(n);
        return out;
    }

    // The bar.monitors key that applies to `screen`, or "".
    function keyFor(screen: var): string {
        const monitors = Config.bar.monitors ?? {};
        return Object.keys(monitors).find(k => Screens.matches(screen, k)) ?? "";
    }

    function overrideFor(screen: var): var {
        const key = keyFor(screen);
        return key === "" ? {} : (Config.bar.monitors[key] ?? {});
    }

    // Lists read from settings.json are not JS arrays (Array.isArray is
    // false on them), so a section counts when it is there at all.
    function has(override: var, section: string): bool {
        return override[section] !== undefined && override[section] !== null;
    }

    function hasOwnLayout(override: var): bool {
        return root.sections.some(([s]) => has(override, s));
    }

    // { left, center, right } for a screen (null: the default). The old
    // showMedia switch still hides its widget.
    function layoutFor(screen: var): var {
        const override = screen ? overrideFor(screen) : {};
        const showMedia = override.showMedia ?? Config.bar.showMedia;
        const out = {};
        for (const [s] of root.sections) {
            const list = normalize(has(override, s) ? override[s] : Config.bar[s]);
            out[s] = list.filter(n => n !== "media" || showMedia !== false);
        }
        return out;
    }

    // [{ name } or { status: [parts] }]: neighbouring status parts share an island
    function groups(list: var): var {
        const out = [];
        for (const name of list) {
            const last = out[out.length - 1];
            if (statusParts.includes(name)) {
                if (last && last.status)
                    last.status.push(name);
                else
                    out.push({ status: [name] });
            } else {
                out.push({ name: name });
            }
        }
        return out;
    }

    function isExcluded(screen: var): bool {
        return Config.bar.excluded.some(k => Screens.matches(screen, k));
    }
}
