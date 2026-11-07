.pragma library

// Omarchy gives every monitor its own block of ten workspace ids (1-10, 11-20,
// ...), and Super+N goes to slot N of the focused monitor's block.
var SLOTS = 10;

function isNumbered(workspace) {
    return Boolean(workspace) && Number(workspace.id) > 0;
}

// The numbered workspaces on a monitor, in id order. Special workspaces such as
// the scratchpad and the dock's minimized windows are left out.
function stripWorkspaces(workspaces, monitorName) {
    var wanted = String(monitorName || "");
    var result = [];
    for (var index = 0; index < workspaces.length; index++) {
        var workspace = workspaces[index];
        if (isNumbered(workspace) && workspace.monitor && String(workspace.monitor.name || "") === wanted)
            result.push(workspace);
    }
    return result.sort(function (left, right) { return Number(left.id) - Number(right.id); });
}

// A workspace added with + while the overview is open. Hyprland removes an
// empty workspace that is not shown, so until a window is moved there it
// exists only in the strip.
function placeholder(id, monitorName) {
    return { id: id, name: String(id), monitor: { name: String(monitorName || "") }, placeholder: true };
}

// The strip's workspaces with the added ones that do not exist yet, in id
// order. The same objects come back each time, so thumbnails are kept.
function withPlaceholders(workspaces, added, monitorName) {
    var result = workspaces.slice();
    var ids = workspaces.map(function (workspace) { return Number(workspace.id); });
    for (var index = 0; index < added.length; index++) {
        var extra = added[index];
        if (extra.monitor.name === String(monitorName || "") && ids.indexOf(Number(extra.id)) === -1)
            result.push(extra);
    }
    return result.sort(function (left, right) { return Number(left.id) - Number(right.id); });
}

// A monitor's block from Omarchy's state file, whose lines read
// "<block>\t<connector>\t<identity>". Without an entry, the block of the
// monitor's active workspace stands in.
function blockFor(stateText, monitorName, activeId) {
    var lines = String(stateText || "").split("\n");
    for (var index = 0; index < lines.length; index++) {
        var fields = lines[index].split("\t");
        if (fields.length >= 2 && fields[1] === String(monitorName || "") && /^\d+$/.test(fields[0]))
            return Number(fields[0]);
    }
    var id = Number(activeId);
    return id >= 1 ? Math.floor((id - 1) / SLOTS) : 0;
}

// The workspace id of a slot (1-10) in a block.
function slotId(block, slot) {
    return block * SLOTS + slot;
}

// Where a new workspace goes, as Omarchy picks it: after the highest one in the
// block, else in the first gap. -1 when all ten exist.
function newWorkspaceId(existingIds, block) {
    var first = block * SLOTS + 1;
    var last = block * SLOTS + SLOTS;
    var highest = first - 1;
    for (var index = 0; index < existingIds.length; index++) {
        var id = Number(existingIds[index]);
        if (id >= first && id <= last && id > highest)
            highest = id;
    }
    if (highest < last)
        return highest + 1;
    for (var gap = first; gap <= last; gap++)
        if (existingIds.indexOf(gap) === -1)
            return gap;
    return -1;
}

// The slot a number-row key picks, 1-9 and 0 for 10, or 0 for any other key.
// Omarchy binds these by key position, so layouts that need Shift for digits
// still reach them; scan codes 10-19 are that row.
function slotForKey(key, scanCode) {
    var code = Number(scanCode);
    if (code >= 10 && code <= 19)
        return code - 9;
    if (key >= 0x30 && key <= 0x39)
        return key === 0x30 ? 10 : key - 0x30;
    return 0;
}

// The windows a workspace thumbnail draws. Grouped windows other than the
// group's visible one are hidden.
function windowsOn(toplevels, workspaceId) {
    var result = [];
    for (var index = 0; index < toplevels.length; index++) {
        var top = toplevels[index];
        var workspace = top && top.workspace ? top.workspace : null;
        var ipc = top && top.lastIpcObject && typeof top.lastIpcObject === "object" ? top.lastIpcObject : {};
        if (workspace && Number(workspace.id) === Number(workspaceId) && ipc.hidden !== true)
            result.push(top);
    }
    return result;
}

// Stacking within a thumbnail, as on screen: fullscreen over floating over
// tiled, and the most recently focused window on top within each.
function stackLevel(ipc) {
    var history = Number(ipc && ipc.focusHistoryID);
    var recency = 500 - Math.min(499, isFinite(history) && history >= 0 ? history : 499);
    if (ipc && Number(ipc.fullscreen) > 0)
        return 2000 + recency;
    return (ipc && ipc.floating ? 1000 : 0) + recency;
}
