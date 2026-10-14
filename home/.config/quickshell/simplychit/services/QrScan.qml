pragma Singleton

import QtQuick
import Quickshell

// Reads a QR code off the screen: drag a box round it (slurp), and what it
// says is copied, with a notification. zbarimg's -Sbinary hands the bytes
// back as they are; without it, UTF-8 text comes out as Shift-JIS mojibake.
//
// qs -c simplychit ipc call qr scan
Singleton {
    function scan(): void {
        // the 0.3 s lets whatever opened this (a panel, the launcher) fade
        // out of the grab
        Quickshell.execDetached(["sh", "-c", `
            sleep 0.3
            G=$(slurp) || exit 0
            T=$(grim -g "$G" - | zbarimg -q --raw -Sbinary -) || {
                notify-send -a SimplyChit -t 3000 -- "No QR code found" "Drag a box round the whole code."
                exit 0
            }
            printf '%s' "$T" | wl-copy
            # -- : scanned text may start with "-"
            notify-send -a SimplyChit -t 4000 -- "QR code copied" "$T"
        `]);
    }
}
