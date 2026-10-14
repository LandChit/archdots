pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification daemon (org.freedesktop.Notifications), its history, the
// do-not-disturb flag, and the shell's own toasts.
//
//   popups   what is on screen now: D-Bus notifications and toasts alike
//   history  the last 50 D-Bus notifications, newest first (toasts are not kept)
//
// DND hides popups but still records history; critical notifications show
// anyway. It is deliberately not persisted: a restart clears
// it, so a muted session never outlives the reason it was muted.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    property var history: []
    property int nextToast: 1

    readonly property int maxHistory: 50

    function plain(text: string): string {
        return (text ?? "").replace(/<[^>]+>/g, "").trim();
    }

    function iconOf(n: Notification): string {
        if (n.image !== "")
            return n.image;
        if (n.appIcon !== "")
            return n.appIcon.startsWith("/") ? "file://" + n.appIcon : Quickshell.iconPath(n.appIcon, "dialog-information");
        const entry = n.desktopEntry !== "" ? DesktopEntries.heuristicLookup(n.desktopEntry) : null;
        return Quickshell.iconPath(entry ? entry.icon : "dialog-information", "dialog-information");
    }

    // A message from the shell itself (TODO C9): same card as a notification,
    // never in the history, shown even under DND only if `important`.
    function toast(title: string, body: string, glyph: string, important: bool): void {
        if (dnd && !important)
            return;
        const id = "toast-" + nextToast++;
        popups = [{ key: id, toast: true, summary: title, body: body, glyph: glyph, appName: "archdots", urgency: important ? 2 : 1, timeout: 3500 }].concat(popups).slice(0, 6);
    }

    function dismissPopup(key: string): void {
        const popup = popups.find(p => p.key === key);
        popups = popups.filter(p => p.key !== key);
        if (popup && popup.notification && popup.notification.tracked && popup.closeOnDismiss)
            popup.notification.dismiss();
    }

    function clearHistory(): void {
        history = [];
    }

    function removeFromHistory(key: string): void {
        history = history.filter(h => h.key !== key);
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            const critical = n.urgency === NotificationUrgency.Critical;
            const entry = {
                key: "n-" + n.id + "-" + Date.now(),
                toast: false,
                notification: n,
                appName: n.appName,
                summary: root.plain(n.summary),
                body: root.plain(n.body),
                icon: root.iconOf(n),
                urgency: critical ? 2 : n.urgency === NotificationUrgency.Low ? 0 : 1,
                time: Qt.formatTime(new Date(), "hh:mm"),
                // -1 means "the server decides": 5 s; critical waits for you
                timeout: critical ? 0 : n.expireTimeout > 0 ? n.expireTimeout : 5000,
                actions: n.actions.map(a => ({ id: a.identifier, text: a.text, action: a })),
                closeOnDismiss: true
            };
            if (!n.transient)
                root.history = [entry].concat(root.history).slice(0, root.maxHistory);
            if (!root.dnd || critical)
                root.popups = [entry].concat(root.popups.filter(p => !(p.notification && p.notification.id === n.id))).slice(0, 6);
            // a notification closed by its app takes its card with it
            n.closed.connect(() => {
                root.popups = root.popups.filter(p => p.notification !== n);
            });
        }
    }
}
