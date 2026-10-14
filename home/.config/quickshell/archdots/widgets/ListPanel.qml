import QtQuick
import qs.widgets

// A SearchPanel whose body is a keyboard-driven list. `items` is a plain JS
// array; the delegate gets each one as modelData.
//
// Nothing is highlighted until an arrow key is pressed (fabric's behaviour),
// but Enter still opens `defaultIndex`, the obvious pick for the query.
SearchPanel {
    id: root

    property var items: []
    property alias delegate: list.delegate
    property alias list: list
    property int listHeight: 460
    property int defaultIndex: 0

    signal activated(var item, int modifiers)

    function step(delta: int): void {
        if (items.length === 0)
            return;
        list.showSelection = true;
        list.currentIndex = Math.max(0, Math.min(items.length - 1, list.currentIndex + delta));
    }

    onItemsChanged: {
        list.showSelection = false;
        list.currentIndex = Math.min(defaultIndex, items.length - 1);
        list.positionViewAtBeginning();
    }
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
