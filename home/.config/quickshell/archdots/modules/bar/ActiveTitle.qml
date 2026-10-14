import QtQuick
import qs.config
import qs.services
import qs.widgets

// The focused window's title, or Config.bar.emptyTitle when nothing has focus.
Island {
    padding: 13

    BarText {
        readonly property string title: Hypr.activeTitle

        text: title === "" ? Config.bar.emptyTitle
            : title.length > Config.bar.titleChars ? title.slice(0, Config.bar.titleChars) + "…"
            : title
    }
}
