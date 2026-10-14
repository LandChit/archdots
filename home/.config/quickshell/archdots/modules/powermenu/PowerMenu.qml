import QtQuick
import qs.services
import qs.widgets

// A card per session action (services/Power.qml).
CardMenu {
    name: "powermenu"
    cards: Power.actions.map(a => ({ label: a.label, glyph: a.glyph, run: () => Power.run(a.id) }))
}
