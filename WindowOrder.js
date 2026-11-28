.pragma library
.import "WindowModel.js" as WindowModel

// The order windows take in the grid. By default it follows the desktop;
// once cards are dragged into an order of their own, that order is kept.

// Displays from left to right, then workspaces by number, then windows from
// left to right and top to bottom. Special workspaces follow the numbered
// ones, and windows minimized to the dock come last.
function desktopKey(top) {
    var monitor = top && top.monitor ? top.monitor : null;
    var workspace = top && top.workspace ? top.workspace : null;
    var at = WindowModel.ipcFor(top).at || [];
    return [
        WindowModel.isMinimized(top) ? 2 : (WindowModel.isOnSpecialWorkspace(top) ? 1 : 0),
        monitor ? Number(monitor.x) || 0 : 0,
        monitor ? Number(monitor.y) || 0 : 0,
        workspace ? Number(workspace.id) || 0 : 0,
        Number(at[0]) || 0,
        Number(at[1]) || 0
    ];
}

// The windows sorted as they sit on the desktop. Ties keep their given order.
function desktopOrder(toplevels) {
    var keyed = (toplevels || []).map(function (top, index) {
        return { top: top, key: desktopKey(top).concat([index]) };
    });
    keyed.sort(function (a, b) {
        for (var part = 0; part < a.key.length; part++)
            if (a.key[part] !== b.key[part])
                return a.key[part] - b.key[part];
        return 0;
    });
    return keyed.map(function (entry) { return entry.top; });
}

// The windows in the order dragged into, those it does not know yet after
// them in desktop order.
function arrange(toplevels, customOrder) {
    var known = (customOrder || []).filter(function (top) { return top && toplevels.indexOf(top) !== -1; });
    var rest = toplevels.filter(function (top) { return known.indexOf(top) === -1; });
    return known.concat(desktopOrder(rest));
}

// The list with dragged moved to target's place; the windows between shift
// toward the place dragged left. The same list when nothing moves.
function moved(list, dragged, target) {
    var from = list.indexOf(dragged);
    var to = list.indexOf(target);
    if (from < 0 || to < 0 || from === to)
        return list;
    var result = list.slice();
    result.splice(from, 1);
    result.splice(to, 0, dragged);
    return result;
}
