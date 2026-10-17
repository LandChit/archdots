pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.config

// The notification daemon (org.freedesktop.Notifications), its history, the
// do-not-disturb flag, and the shell's own toasts.
//
//   popups   the D-Bus notifications on screen now (top right)
//   toasts   the shell's own short messages on screen now (bottom middle)
//   history  the last 50 D-Bus notifications, newest first (toasts are not kept)
//
// DND hides popups but still records history; critical notifications show
// anyway. It is deliberately not persisted: a restart clears
// it, so a muted session never outlives the reason it was muted.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    property var toasts: []
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

    // A message from the shell itself (TODO C9): a pill at the bottom of the
    // screen, never in the history, shown even under DND only if `important`.
    // A toast with the same title replaces the old one (Caps Lock on, off).
    function toast(title: string, body: string, glyph: string, important: bool): void {
        if (dnd && !important)
            return;
        const id = "toast-" + nextToast++;
        toasts = toasts.filter(t => t.summary !== title).concat([{ key: id, summary: title, body: body, glyph: glyph, timeout: 3500 }]).slice(-3);
    }

    function dismissToast(key: string): void {
        toasts = toasts.filter(t => t.key !== key);
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

    // The history by app, for the notification centre: one group per app,
    // ordered by each app's newest notification, newest first inside.
    function groupOf(entry): string {
        return entry.appName || "Other";
    }

    readonly property var historyGroups: {
        const groups = [];
        const byApp = {};
        for (const entry of history) {
            const app = groupOf(entry);
            if (!(app in byApp)) {
                byApp[app] = { app: app, items: [] };
                groups.push(byApp[app]);
            }
            byApp[app].items.push(entry);
        }
        return groups;
    }

    function removeGroup(app: string): void {
        history = history.filter(h => groupOf(h) !== app);
    }

    // Do not disturb on a daily schedule (notifications.schedule): switched on
    // and off at the edges only, so DND set by hand in between is left alone.
    property bool inSchedule: false

    function scheduled(): bool {
        const sch = Config.notifications.schedule;
        if (!sch.enabled)
            return false;
        const now = new Date();
        const minutes = now.getHours() * 60 + now.getMinutes();
        const parse = t => {
            const m = /^(\d{1,2}):(\d{2})$/.exec(t);
            return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1;
        };
        const from = parse(sch.from), to = parse(sch.to);
        if (from < 0 || to < 0 || from === to)
            return false;
        return from < to ? minutes >= from && minutes < to : minutes >= from || minutes < to;
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = root.scheduled();
            if (now !== root.inSchedule) {
                root.inSchedule = now;
                root.dnd = now;
            }
        }
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
                notification: n,
                appName: n.appName,
                summary: root.plain(n.summary),
                body: root.plain(n.body),
                icon: root.iconOf(n),
                urgency: critical ? 2 : n.urgency === NotificationUrgency.Low ? 0 : 1,
                time: Qt.formatTime(new Date(), "hh:mm"),
                // -1 means "the server decides": 5 s; critical waits for you
                timeout: critical ? 0 : n.expireTimeout > 0 ? n.expireTimeout : Config.notifications.timeout * 1000,
                actions: n.actions.map(a => ({ id: a.identifier, text: a.text, action: a })),
                closeOnDismiss: true
            };
            if (!n.transient)
                root.history = [entry].concat(root.history).slice(0, root.maxHistory);
            if (!root.dnd || critical)
                root.popups = [entry].concat(root.popups.filter(p => !(p.notification && p.notification.id === n.id))).slice(0, 6);
            // silent under DND, even for a critical one that still pops up
            if (!root.dnd)
                Sounds.notification(critical, n.hints);
            // a notification closed by its app takes its card with it
            n.closed.connect(() => {
                root.popups = root.popups.filter(p => p.notification !== n);
            });
        }
    }
}
