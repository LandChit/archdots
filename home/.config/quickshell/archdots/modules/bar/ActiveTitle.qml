import QtQuick
import qs.config
import qs.services
import qs.widgets

// The focused window's title, or settings.emptyTitle when nothing has focus.
Island {
    required property var settings
    padding: 13

    BarText {
        readonly property string title: Hypr.activeTitle

        text: title === "" ? settings.emptyTitle
            : title.length > settings.titleChars ? title.slice(0, settings.titleChars) + "…"
            : title
    }
}
