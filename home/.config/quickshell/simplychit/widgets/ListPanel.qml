import QtQuick
import qs.widgets

// A SearchPanel whose body is a keyboard-driven list. `items` is a plain JS
// array; the delegate gets each one as modelData.
//
// Nothing is highlighted until an arrow key is pressed, but Enter still
// opens `defaultIndex`, the obvious pick for the query. With
// `selectOnSearch`, that pick is highlighted as soon as there is a query.
SearchPanel {
    id: root

    property var items: []
    property alias delegate: list.delegate
    property alias list: list
    property int listHeight: 460
    property int defaultIndex: 0
    property bool selectOnSearch: false

    signal activated(var item, int modifiers)

    function step(delta: int): void {
        if (items.length === 0)
            return;
        // The first arrow press shows the pick Enter would open (row 0 for
        // an empty query) rather than stepping past it.
        if (!list.showSelection) {
            list.showSelection = true;
            return;
        }
        list.currentIndex = Math.max(0, Math.min(items.length - 1, list.currentIndex + delta));
    }

    // Deferred: the ListView takes the new model after this handler and puts
    // currentIndex back to 0, which would drop defaultIndex.
    onItemsChanged: Qt.callLater(() => {
        list.showSelection = selectOnSearch && query !== "" && items.length > 0;
        list.currentIndex = Math.min(defaultIndex, items.length - 1);
        list.positionViewAtBeginning();
    })
    onMoveUp: step(-1)
    onMoveDown: step(1)
    onAccepted: modifiers => {
        if (list.currentIndex >= 0 && list.currentIndex < items.length)
            activated(items[list.currentIndex], modifiers);
    }

    ListView {
        id: list

        property bool showSelection: false

        signal clickedRow(int index)

        width: parent.width
        height: Math.min(root.listHeight, contentHeight)
        model: root.items
        spacing: 3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        onClickedRow: index => root.activated(root.items[index], 0)
    }
}
