pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// The games scratchpad's lists, and the question "add this to games?".
//
// The games are the shipped ~/.config/hypr/games.json (minus games.disabled)
// and your games.classes; Hyprland makes a rule for each
// (hypr/config/helpers/games.lua). Every change here is written to
// settings.json and then applied without a reload, by
// `hyprctl eval 'require("config.helpers.games").refresh()'`.
//
// The question comes up (modules/games/GamesDialog.qml) for a window
//   · moved into special:games (SUPER+SHIFT+G, the mouse, hyprctl) whose
//     class is in no list, while games.ask is on;
//   · opening anywhere while games.detect is on, when it looks like a game:
//     Wayland's content type "game", a Wine/Proton .exe class, gamescope, or a
//     game launcher's variable in its environment.
// Yes adds its class to games.classes; No adds it to games.ignored, and it is
// not asked about again (Settings > Games lists both).
Singleton {
    id: root

    readonly property string workspace: "special:games"
    readonly property string listPath: Quickshell.env("HOME") + "/.config/hypr/games.json"

    property var shipped: []
    readonly property var own: (Config.games.classes ?? []).map(entryOf).filter(e => e !== null)
    readonly property var disabled: Config.games.disabled ?? []
    readonly property var ignored: Config.games.ignored ?? []
    readonly property var entries: shipped.map(entryOf).filter(e => e !== null && !disabled.includes(e.name)).concat(own)

    // the question on screen: { address, cls, title, name, icon, detected }
    property var asking: null
    property var queue: []
    // classes asked about (or queued) since the shell started
    property var asked: ({})

    // launchers and tools that run games but are not games themselves
    readonly property var launchers: ["steam", "steamwebhelper", "net.lutris.Lutris", "lutris", "heroic", "com.heroicgameslauncher.hgl", "org.prismlauncher.PrismLauncher", "PrismLauncher", "bottles", "com.usebottles.bottles", "org.quickshell", "explorer.exe", "winecfg.exe", "steam.exe"]
    // variables a game launcher puts in a game's environment
    readonly property var launcherVars: ["SteamAppId", "STEAM_COMPAT_APP_ID", "LUTRIS_GAME_UUID", "HEROIC_APP_NAME", "GAMEID"]

    // ── the lists ───────────────────────────────────────────────────────────

    function entryOf(value: var): var {
        if (typeof value === "string")
            return value === "" ? null : { name: value, class: value, title: "", fullscreen: true };
        if (value && typeof value === "object" && typeof value.class === "string" && value.class !== "")
            return {
                name: typeof value.name === "string" && value.name !== "" ? value.name : value.class,
                class: value.class,
                title: typeof value.title === "string" ? value.title : "",
                fullscreen: value.fullscreen !== false
            };
        return null;
    }

    // Hyprland's regexes are RE2; JS has no inline flags, so (?i) becomes "i".
    function regex(pattern: string): var {
        const insensitive = pattern.includes("(?i)");
        try {
            return new RegExp(pattern.split("(?i)").join(""), insensitive ? "i" : "");
        } catch (e) {
            return null;
        }
    }

    function matches(entry: var, cls: string, title: string): bool {
        const c = regex(entry.class);
        if (!c || !c.test(cls))
            return false;
        if (entry.title === "")
            return true;
        const t = regex(entry.title);
        return t !== null && t.test(title);
    }

    function isListed(cls: string, title: string): bool {
        return entries.some(e => matches(e, cls, title));
    }

    function isIgnored(cls: string): bool {
        return ignored.includes(cls);
    }

    // ^…$ around the class, its regex characters escaped
    function exact(cls: string): string {
        return "^" + cls.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$";
    }

    // ── changing them ───────────────────────────────────────────────────────

    function rawClasses(): var {
        return JSON.parse(JSON.stringify(Config.games.classes ?? []));
    }

    // Config.set one key after another (each reads the file the last wrote),
    // then apply the lists in Hyprland
    function write(pairs: var): void {
        if (pairs.length === 0) {
            apply.restart();
            return;
        }
        Config.set(pairs[0][0], pairs[0][1]);
        Qt.callLater(() => write(pairs.slice(1)));
    }

    function add(cls: string, name: string): void {
        if (cls === "")
            return;
        const pairs = [];
        if (!own.some(e => e.class === exact(cls)))
            pairs.push(["games.classes", rawClasses().concat([{ name: name !== "" ? name : cls, class: exact(cls) }])]);
        if (isIgnored(cls))
            pairs.push(["games.ignored", ignored.filter(c => c !== cls)]);
        write(pairs);
    }

    function addEntry(entry: var): void {
        write([["games.classes", rawClasses().concat([entry])]]);
    }

    function remove(index: int): void {
        const list = rawClasses();
        list.splice(index, 1);
        write([["games.classes", list]]);
    }

    function setFullscreen(index: int, on: bool): void {
        const list = rawClasses();
        let item = list[index];
        if (typeof item === "string")
            item = { name: item, class: item };
        if (on)
            delete item.fullscreen;
        else
            item.fullscreen = false;
        list[index] = item;
        write([["games.classes", list]]);
    }

    function ignore(cls: string): void {
        if (!isIgnored(cls))
            write([["games.ignored", ignored.concat([cls])]]);
    }

    function unignore(cls: string): void {
        delete asked[cls];
        write([["games.ignored", ignored.filter(c => c !== cls)]]);
    }

    function setDisabled(name: string, off: bool): void {
        const list = disabled.filter(n => n !== name);
        if (off)
            list.push(name);
        write([["games.disabled", list]]);
    }

    Timer {
        id: apply

        // after FileView has written settings.json
        interval: 400
        onTriggered: Quickshell.execDetached(["hyprctl", "eval", "require(\"config.helpers.games\").refresh()"])
    }

    // ── the question ────────────────────────────────────────────────────────

    // A window to ask about: looked up in `hyprctl clients`, then asked about
    // unless listed, ignored or asked already. `detected` windows must look
    // like a game first. `forced` (IPC `games ask`) asks about any window
    // in no list, wherever it is.
    function consider(address: string, detected: bool, forced: bool): void {
        const hex = address.replace(/^0x/, "");
        if (hex === "")
            return;
        lookup.createObject(root, { address: "0x" + hex, detected: detected, forced: forced, tries: 0 }).running = true;
    }

    function judge(client: var, detected: bool, forced: bool): void {
        const cls = client.class ?? "";
        const title = client.title ?? "";
        if (cls === "" || isIgnored(cls) || isListed(cls, title))
            return;
        if (forced) {
            delete asked[cls];
            enqueue(client, false);
            return;
        }
        if (asked[cls] || launchers.includes(cls))
            return;
        if (!detected) {
            if (Config.games.ask && (client.workspace?.name ?? "") === workspace)
                enqueue(client, false);
            return;
        }
        if (!Config.games.detect)
            return;
        if (client.contentType === "game" || /\.exe$/i.test(cls) || cls === "gamescope") {
            enqueue(client, true);
            return;
        }
        if ((client.pid ?? 0) > 0) {
            const check = environ.createObject(root, { client: client });
            check.running = true;
        }
    }

    function enqueue(client: var, detected: bool): void {
        const cls = client.class;
        if (asked[cls])
            return;
        asked[cls] = true;
        const entry = DesktopEntries.heuristicLookup(cls);
        const question = {
            address: client.address,
            cls: cls,
            title: client.title ?? "",
            name: entry && entry.name ? entry.name : (client.title || cls),
            icon: entry && entry.icon ? entry.icon : "",
            detected: detected
        };
        if (asking === null)
            asking = question;
        else
            queue = queue.concat([question]);
    }

    function next(): void {
        asking = queue.length > 0 ? queue[0] : null;
        queue = queue.slice(1);
    }

    // Yes: add it, and put the window in games, fullscreen
    function answerYes(): void {
        const q = asking;
        if (!q)
            return;
        add(q.cls, q.name);
        Quickshell.execDetached(["hyprctl", "eval", "require(\"config.helpers.games\").take(\"" + q.address + "\")"]);
        next();
    }

    function answerNo(): void {
        if (asking)
            ignore(asking.cls);
        next();
    }

    // one per window asked about: its entry in `hyprctl clients`; a window not
    // listed yet (just mapped) gets two more tries
    Component {
        id: lookup

        Process {
            id: query

            property string address
            property bool detected
            property bool forced
            property int tries

            command: ["hyprctl", "clients", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    let client = null;
                    try {
                        client = JSON.parse(text).find(c => c.address === query.address) ?? null;
                    } catch (e) {}
                    if (client)
                        root.judge(client, query.detected, query.forced);
                    else if (query.tries < 2)
                        retry.createObject(root, { address: query.address, detected: query.detected, forced: query.forced, tries: query.tries + 1 });
                    query.destroy();
                }
            }
        }
    }

    Component {
        id: retry

        Timer {
            id: wait

            property string address
            property bool detected
            property bool forced
            property int tries

            interval: 300
            running: true
            onTriggered: {
                lookup.createObject(root, { address: address, detected: detected, forced: forced, tries: tries }).running = true;
                wait.destroy();
            }
        }
    }

    // one per window checked: a launcher's variable in its environment
    Component {
        id: environ

        Process {
            id: proc

            property var client

            command: ["sh", "-c", "tr '\\0' '\\n' < /proc/\"$1\"/environ 2>/dev/null", "sh", String(client.pid)]
            stdout: StdioCollector {
                onStreamFinished: {
                    const found = text.split("\n").some(line => {
                        const eq = line.indexOf("=");
                        const value = line.slice(eq + 1);
                        return eq > 0 && root.launcherVars.includes(line.slice(0, eq)) && value !== "" && value !== "0";
                    });
                    if (found)
                        root.enqueue(proc.client, true);
                    proc.destroy();
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (event.name === "movewindowv2") {
                const parts = event.data.split(",");
                if (parts[parts.length - 1] === root.workspace)
                    root.consider(parts[0], false, false);
            } else if (event.name === "openwindow") {
                root.consider(event.data.split(",")[0], true, false);
            }
        }
    }

    FileView {
        path: root.listPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.shipped = JSON.parse(text()).games ?? [];
            } catch (e) {
                root.shipped = [];
            }
        }
    }
}
