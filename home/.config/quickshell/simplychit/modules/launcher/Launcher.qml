import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import qs.services
import qs.widgets

// The app launcher, and its modes, picked by the first character:
//
//   (none)  apps: favourites first, then by how often each is opened
//   ?       web search            =  calculator (also any plain arithmetic)
//   /       files under ~ (fd)    @  open windows
//   !       run a command         >  actions: power, panels, unhide apps
//
// Ctrl+P pins the selected app to the top, Ctrl+H hides it.
ListPanel {
    id: root

    name: "launcher"
    // typing highlights the app Enter would open
    selectOnSearch: true
    glyph: "󰍉"
    placeholder: "Search apps   ? web  = calc  / files  @ windows  ! run  > actions"
    hints: ["↕ navigate", "↵ open", "^P pin", "^H hide", "esc close"]
    panelWidth: 560

    readonly property string mode: "?=/@!>".includes(query.charAt(0)) ? query.charAt(0) : ""
    readonly property string term: (mode === "" ? query : query.slice(1)).trim()
    property var fileResults: []

    // ── items ────────────────────────────────────────────────────────────
    // Every row is { title, subtitle, icon or glyph, hint, run() }, plus
    // `appId` on app rows.

    function appRow(entry: DesktopEntry): var {
        const pinned = Config.launcher.favourites.includes(entry.id);
        return {
            appId: entry.id,
            title: entry.name,
            subtitle: (pinned ? "★ " : "") + (entry.genericName || entry.comment || ""),
            icon: entry.icon || "application-x-executable",
            run: () => {
                usage.bump(entry.id);
                if (entry.runInTerminal)
                    Quickshell.execDetached(["sh", "-c", Config.apps.terminal + " -e " + entry.execString.replace(/%[a-zA-Z]/g, "")]);
                else
                    entry.execute();
            }
        };
    }

    function apps(): var {
        const needle = term.toLowerCase();
        const favourites = Config.launcher.favourites;
        const hidden = Config.launcher.hidden;
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay && !hidden.includes(e.id));
        // keywords comes through as a list, whatever the type file says
        const matching = needle === "" ? all : all.filter(e => [e.name, e.genericName, e.keywords, e.id].some(f => String(f ?? "").toLowerCase().includes(needle)));
        // a name that starts with the query beats one that merely contains it
        const score = e => {
            const pin = favourites.indexOf(e.id);
            return [pin < 0 ? 1e6 : pin, needle !== "" && !e.name.toLowerCase().startsWith(needle) ? 1 : 0, -usage.count(e.id)];
        };
        matching.sort((a, b) => {
            const sa = score(a), sb = score(b);
            for (let i = 0; i < sa.length; i++)
                if (sa[i] !== sb[i])
                    return sa[i] - sb[i];
            return a.name.localeCompare(b.name);
        });
        return matching.map(appRow);
    }

    function webRow(text: string): var {
        return {
            title: "Search for \"" + text + "\"",
            subtitle: "Web search",
            icon: "internet-web-browser",
            run: () => Qt.openUrlExternally(Config.launcher.searchUrl.replace("%s", encodeURIComponent(text)))
        };
    }

    // Only digits, operators, brackets and dots get as far as evaluation, so
    // Function() here cannot run anything but arithmetic. ^ is power.
    function calculate(text: string): string {
        if (!/^[0-9+\-*/%^().\s]+$/.test(text) || !/[0-9]/.test(text))
            return "";
        try {
            const value = Function("return (" + text.replace(/\^/g, "**") + ")")();
            return typeof value === "number" && isFinite(value) ? String(Math.round(value * 1e10) / 1e10) : "";
        } catch (e) {
            return "";
        }
    }

    function calcRow(result: string): var {
        return {
            title: result,
            subtitle: term + " = " + result + " · Enter copies it",
            glyph: "󰃬",
            hint: "copy ↵",
            run: () => Quickshell.clipboardText = result
        };
    }

    function windowRows(): var {
        const needle = term.toLowerCase();
        return Hyprland.toplevels.values
            .filter(t => t.wayland !== null)
            .map(t => ({ t: t, cls: (t.lastIpcObject && t.lastIpcObject.class) || "" }))
            .filter(w => needle === "" || (w.t.title + " " + w.cls).toLowerCase().includes(needle))
            .map(w => ({
                title: w.t.title,
                subtitle: w.cls + (w.t.workspace ? " · workspace " + w.t.workspace.name : ""),
                icon: (DesktopEntries.heuristicLookup(w.cls) || {}).icon || "",
                glyph: "󰖲",
                hint: "focus ↵",
                run: () => w.t.wayland.activate()
            }));
    }

    function actionRows(): var {
        const rows = Power.actions.map(a => ({
            title: a.label,
            subtitle: "Session",
            glyph: a.glyph,
            hint: "run ↵",
            run: () => Power.run(a.id)
        }));
        rows.push({ title: "Settings", subtitle: "Open", glyph: "\u{f0493}", hint: "open ↵", run: () => SettingsState.show("") });
        const panels = [["wallpaper", "Wallpaper", "󰸉"], ["control", "Control centre", "󰒓"], ["clipboard", "Clipboard history", "󰅌"], ["emoji", "Emoji", "󰞅"], ["screenshot", "Screenshot", "󰄀"], ["keybinds", "Keybinds", "󰌌"], ["notifications", "Notifications", "󰂚"], ["notepad", "Notepad", "\u{f082e}"], ["qr", "QR code of the clipboard", "\u{f0432}"]];
        for (const [panel, label, glyph] of panels)
            rows.push({ title: label, subtitle: "Open", glyph: glyph, hint: "open ↵", run: () => Qt.callLater(() => Panels.open(panel)) });
        rows.push({ title: "Scan a QR code", subtitle: "Drag a box round it; what it says is copied", glyph: "\u{f0432}", hint: "scan ↵", run: () => QrScan.scan() });
        rows.push({ title: Config.theme.mode === "light" ? "Dark mode" : "Light mode", subtitle: "Theme · re-runs pywal16 on the wallpaper", glyph: "\u{f0594}", hint: "switch ↵", run: () => Theme.setMode(Config.theme.mode === "light" ? "dark" : "light") });
        rows.push({ title: "Random wallpaper", subtitle: "Theme", glyph: "\u{f0e09}", hint: "run ↵", run: () => Theme.next(true) });
        for (const backend of Theme.backends)
            if (backend !== Config.theme.backend)
                rows.push({ title: "Scheme: " + backend, subtitle: "Theme · pywal16 colour backend", glyph: "\u{f03d8}", hint: "use ↵", run: () => Theme.setBackend(backend) });
        for (const id of Config.launcher.hidden) {
            const entry = DesktopEntries.byId(id);
            rows.push({ title: "Unhide " + (entry ? entry.name : id), subtitle: "Hidden app", glyph: "󰈈", hint: "unhide ↵", run: () => Config.set("launcher.hidden", Config.launcher.hidden.filter(h => h !== id)) });
        }
        const needle = term.toLowerCase();
        return needle === "" ? rows : rows.filter(r => r.title.toLowerCase().includes(needle));
    }

    function fileRows(): var {
        return fileResults.map(path => ({
            title: path.slice(path.lastIndexOf("/") + 1),
            subtitle: path.replace(Quickshell.env("HOME"), "~"),
            glyph: path.endsWith("/") ? "󰉋" : "󰈔",
            run: () => Qt.openUrlExternally("file://" + path)
        }));
    }

    function runRows(): var {
        if (term === "")
            return [];
        return [{
            title: term,
            subtitle: "Run · Shift+Enter in a terminal",
            glyph: "󰆍",
            hint: "run ↵",
            run: () => Quickshell.execDetached(["sh", "-c", term]),
            runInTerminal: () => Quickshell.execDetached(["sh", "-c", Config.apps.terminal + " -e sh -c " + JSON.stringify(term + "; exec $SHELL")])
        }];
    }

    function rebuild(): void {
        let rows;
        defaultIndex = 0;
        switch (mode) {
        case "?":
            rows = term === "" ? [] : [webRow(term)];
            break;
        case "=":
            rows = calculate(term) === "" ? [] : [calcRow(calculate(term))];
            break;
        case "/":
            rows = fileRows();
            break;
        case "@":
            rows = windowRows();
            break;
        case "!":
            rows = runRows();
            break;
        case ">":
            rows = actionRows();
            break;
        default:
            rows = apps();
            const result = calculate(term);
            if (result !== "")
                rows.unshift(calcRow(result));
            else if (term !== "") {
                // the web row goes first but Enter still opens the best app
                rows.unshift(webRow(term));
                if (rows.length > 1)
                    defaultIndex = 1;
            }
        }
        items = rows;
    }

    function togglePinned(list: string, item: var): void {
        if (!item || !item.appId)
            return;
        const current = Config.launcher[list];
        Config.set("launcher." + list, current.includes(item.appId) ? current.filter(id => id !== item.appId) : current.concat([item.appId]));
    }

    onOpened: rebuild()
    // Deferred: this handler can run before `mode` and `term` have caught up
    // with the new query, and the list then lags one keystroke behind.
    // callLater also folds a burst of keys into one rebuild.
    onQueryChanged: Qt.callLater(() => {
        if (mode === "/")
            fileSearch.restart();
        rebuild();
    })
    onActivated: (item, modifiers) => {
        if ((modifiers & Qt.ShiftModifier) && item.runInTerminal)
            item.runInTerminal();
        else
            item.run();
        close();
    }
    onOtherKey: event => {
        if (!(event.modifiers & Qt.ControlModifier) || mode !== "")
            return;
        const item = items[list.currentIndex];
        if (event.key === Qt.Key_P)
            togglePinned("favourites", item);
        else if (event.key === Qt.Key_H)
            togglePinned("hidden", item);
        else
            return;
        event.accepted = true;
    }

    // The entries are read in the background at startup; the first open can
    // come before they are.
    Connections {
        target: DesktopEntries.applications

        function onValuesChanged(): void {
            if (root.shown)
                root.rebuild();
        }
    }

    // A pin or hide lands in settings.json and comes back through Config.
    Connections {
        target: Config.launcher

        function onFavouritesChanged(): void {
            if (root.shown)
                root.rebuild();
        }
        function onHiddenChanged(): void {
            if (root.shown)
                root.rebuild();
        }
    }

    // Open with the search already filled in, so a keybind can go straight to
    // a mode: qs -c simplychit ipc call launcher open "@"
    IpcHandler {
        target: "launcher"

        function open(text: string): void {
            Panels.open("launcher");
            Qt.callLater(() => root.query = text);
        }
    }

    UsageCounts {
        id: usage

        file: "launcher"
        importFrom: Quickshell.env("HOME") + "/.local/share/fabric-launcher/counts.json"
    }

    // fd as you type, a beat after the last key.
    Timer {
        id: fileSearch

        interval: 150
        onTriggered: {
            fd.running = false;
            if (root.term.length < 2) {
                root.fileResults = [];
                root.rebuild();
                return;
            }
            // Not --hidden: dot-folders (caches, IDE state, plugins) bury the
            // files anyone opens from a launcher.
            fd.command = ["fd", "--max-results", "40", "--absolute-path", "--ignore-case", "--fixed-strings", root.term, Quickshell.env("HOME")];
            fd.running = true;
        }
    }

    Process {
        id: fd

        stdout: StdioCollector {
            onStreamFinished: {
                root.fileResults = text.split("\n").filter(line => line !== "");
                if (root.mode === "/")
                    root.rebuild();
            }
        }
    }

    delegate: ListRow {
        required property var modelData

        title: modelData.title
        subtitle: modelData.subtitle ?? ""
        icon: modelData.icon ?? ""
        glyph: modelData.glyph ?? ""
        hint: modelData.hint ?? "open ↵"
    }
}
