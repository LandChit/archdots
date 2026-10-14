pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The wallpaper and the palette that follows it.
//
// The shell draws the wallpaper itself (modules/wallpaper/Background.qml), so a
// screen can have its own picture and a change crossfades. Picking a
// wallpaper for every screen also re-runs pywal16 over it, which recolours:
//
//   · the shell, live: config/Colours.qml watches ~/.cache/wal/colors.json
//   · GTK: colors-gtk.css copied next to each gtk.css (GTK cannot import from
//     the cache; see .gitignore and DEVELOPMENT.md)
//   · Hyprland's borders: `hyprctl reload` re-reads colors-hyprland.lua
//
// and re-points ~/.local/state/simplychit/wallpaper, which hyprlock's config
// names, so the lock screen shows the same picture.
//
// Wallpapers per screen are kept in ~/.local/state/simplychit/wallpapers.json:
// { "default": path, "monitors": { "DP-1": path } }.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: home + "/.local/state/simplychit"
    readonly property string pointer: stateDir + "/wallpaper"
    readonly property string directory: Config.wallpaper.directory.replace(/^~/, home)

    property string current: ""
    property var perMonitor: ({})
    property var available: []
    property bool working: false
    readonly property list<string> backends: ["wal", "colorthief", "colorz", "haishoku", "fast_colorthief", "modern_colorthief", "okthief"]

    function wallpaperFor(monitor: string): string {
        return perMonitor[monitor] ?? current;
    }

    // Every screen, and the palette with it.
    function apply(path: string): void {
        current = path;
        perMonitor = {};
        save();
        pointerSetter.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && ln -sfn \"$2\" \"$1.new\" && mv -T \"$1.new\" \"$1\"", "sh", pointer, path];
        pointerSetter.running = true;
        repaint("", "");
    }

    // One screen only; the palette stays with the main wallpaper.
    function applyTo(monitor: string, path: string): void {
        const next = Object.assign({}, perMonitor);
        next[monitor] = path;
        perMonitor = next;
        save();
    }

    // The new value goes to wal directly: Config only sees it once
    // settings.json has been re-read, which is after this returns.
    function setMode(mode: string): void {
        Config.set("theme.mode", mode);
        repaint(mode, Config.theme.backend);
    }

    function setBackend(backend: string): void {
        Config.set("theme.backend", backend);
        repaint(Config.theme.mode, backend);
    }

    function next(random: bool): void {
        if (available.length === 0)
            return;
        const others = available.filter(p => p !== current);
        const pool = others.length > 0 ? others : available;
        apply(random ? pool[Math.floor(Math.random() * pool.length)] : pool[(Math.max(0, available.indexOf(current)) ) % pool.length]);
    }

    function repaint(mode: string, backend: string): void {
        if (current === "")
            return;
        mode = mode || Config.theme.mode;
        backend = backend || Config.theme.backend;
        wal.running = false;
        // flags in step with install.sh's WAL_ARGS: --cols16 dual makes colours
        // 8-15 distinct rather than copies of 0-7
        wal.command = ["wal", "-i", current, "--cols16", "dual", "-n", "-q", "--backend", backend].concat(mode === "light" ? ["-l"] : []);
        working = true;
        wal.running = true;
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ default: current, monitors: perMonitor }, null, 2) + "\n");
    }

    function rescan(): void {
        lister.running = true;
    }

    // Waits for wal to exit, not a fixed delay: an image pywal16 has not seen
    // takes seconds to analyse, and copying early spreads the old palette.
    Process {
        id: wal

        onExited: code => {
            root.working = false;
            if (code !== 0)
                console.warn("wal exited with " + code + " (backend " + Config.theme.backend + "); the palette is unchanged");
            sync.running = true;
        }
    }

    // GTK's three copies (two for the theme, one next to the gtk.css that
    // libadwaita reads), then Hyprland.
    Process {
        id: sync

        command: ["sh", "-c", `
            C="\${XDG_CACHE_HOME:-$HOME/.cache}/wal"
            for t in "$HOME/.themes/simplychit/gtk-3.0/colors.css" "$HOME/.themes/simplychit/gtk-4.0/colors.css" "$HOME/.config/gtk-4.0/colors.css"; do
                [ -d "$(dirname "$t")" ] && cp "$C/colors-gtk.css" "$t"
            done
            hyprctl reload >/dev/null
        `]
    }

    Process {
        id: pointerSetter
    }

    Process {
        id: lister

        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \\) -printf '%T@ %p\\n' | sort -rn | cut -d' ' -f2-", "sh", root.directory]
        stdout: StdioCollector {
            onStreamFinished: root.available = text.split("\n").filter(l => l !== "")
        }
    }

    FileView {
        id: stateFile

        path: root.stateDir + "/wallpapers.json"
        printErrors: false
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.current = state.default ?? "";
                root.perMonitor = state.monitors ?? {};
            } catch (e) {}
        }
        // First run under the shell: take over what the old setup and hyprlock
        // were already showing, through the pointer.
        onLoadFailed: pointerReader.running = true
    }

    Process {
        id: pointerReader

        command: ["readlink", "-f", root.pointer]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.current === "")
                    root.current = text.trim();
            }
        }
    }

    Timer {
        interval: Math.max(1, Config.wallpaper.cycleMinutes) * 60000
        running: Config.wallpaper.cycleMinutes > 0
        repeat: true
        onTriggered: root.next(true)
    }

    Component.onCompleted: rescan()
}
