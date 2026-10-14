import QtQuick
import Quickshell
import qs.widgets

// Region, window, whole screen, or the whole screen after 5 s. Every shot is
// saved to ~/Pictures/screenshots and copied, as fabric's menu did.
//
// The menu closes first and the grab waits for it to fade, so the scrim is
// never in the picture. The filename is expanded once into $F: repeating
// $(date …) would re-run the clock and could name a file that does not exist.
CardMenu {
    id: root

    name: "screenshot"
    footer: "←→ navigate · ↵ capture · esc cancel"

    function capture(grab: string): void {
        const dir = Quickshell.env("HOME") + "/Pictures/screenshots";
        Quickshell.execDetached(["sh", "-c",
            "sleep 0.3; mkdir -p \"$1\"; F=\"$1/Screenshot-$(date +%F_%T).png\"; "
            + grab + " \"$F\" && wl-copy < \"$F\" && notify-send -t 2500 \"Screenshot saved\" \"$(basename \"$F\")\"",
            "sh", dir]);
    }

    cards: [
        { label: "Region", glyph: "\u{f0a6d}", hint: "Drag a box", run: () => capture("REGION=$(slurp) || exit 0; grim -g \"$REGION\"") },
        { label: "Window", glyph: "\u{f05af}", hint: "The focused window", run: () => capture("G=$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(\"%d,%d %dx%d\" % (*w[\"at\"], *w[\"size\"]))') || exit 0; grim -g \"$G\"") },
        { label: "Screen", glyph: "\u{f0379}", hint: "Everything", run: () => capture("grim") },
        { label: "Delay 5s", glyph: "\u{f051b}", hint: "Then the whole screen", run: () => capture("sleep 5; grim") }
    ]
}
