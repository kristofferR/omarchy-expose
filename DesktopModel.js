.pragma library
.import "WindowModel.js" as WindowModel

// Pure helpers for Show Desktop (ShowDesktop.qml). Windows are minimized to
// the dock with Omarchy's own command and come back to the workspace they
// left, so a window is never closed, resized, or moved on screen.

function visibleWorkspaceIds(monitors) {
    var ids = [];
    for (var index = 0; index < (monitors || []).length; index++) {
        var monitor = monitors[index];
        var id = monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : 0;
        if (id >= 1 && ids.indexOf(id) === -1)
            ids.push(id);
    }
    return ids.sort(function (a, b) { return a - b; });
}

function sameWorkspaces(left, right) {
    if (left.length !== right.length)
        return false;
    for (var index = 0; index < left.length; index++)
        if (left[index] !== right[index])
            return false;
    return true;
}

// The windows Show Desktop moves aside: ordinary windows on a workspace that
// is on screen. Pinned windows belong to every workspace, fullscreen windows
// have no desktop behind them, and grouped windows would leave their group,
// so those stay. Minimized and special-workspace windows are already away.
// Lists from Hyprland arrive as QML sequences, not JS arrays, so `grouped` is
// checked by length rather than Array.isArray().
// A display name safe to put in a Lua string, or null.
function monitorName(name) {
    var text = String(name || "");
    return /^[A-Za-z0-9_.-]{1,64}$/.test(text) ? text : null;
}

function candidates(toplevels, visibleIds) {
    var result = [];
    for (var index = 0; index < (toplevels || []).length; index++) {
        var top = toplevels[index];
        var ipc = WindowModel.ipcFor(top);
        var address = WindowModel.addressFor(top);
        var workspaceId = top && top.workspace ? Number(top.workspace.id) : 0;
        if (!address || !WindowModel.isEligible(top) || !(workspaceId >= 1)
                || visibleIds.indexOf(workspaceId) === -1 || ipc.hidden === true
                || WindowModel.isPinned(top) || Number(ipc.fullscreen || 0) > 0
                || (ipc.grouped && Number(ipc.grouped.length) > 0)
                || WindowModel.isMinimized(top))
            continue;
        result.push({ address: address, stableId: ipc.stableId === undefined ? null : String(ipc.stableId),
            workspaceId: workspaceId, monitor: monitorName(top.monitor ? top.monitor.name : "") });
    }
    return result;
}

// An address can be reused after a window closes; the stable id, when Hyprland
// reports one, tells the windows apart.
function matches(entry, top) {
    if (!entry || WindowModel.addressFor(top) !== entry.address)
        return false;
    var stableId = WindowModel.ipcFor(top).stableId;
    return entry.stableId === null || stableId === undefined || String(stableId) === entry.stableId;
}

function toplevelFor(entry, toplevels) {
    for (var index = 0; index < (toplevels || []).length; index++)
        if (matches(entry, toplevels[index]))
            return toplevels[index];
    return null;
}

// The recorded windows that are still minimized. Any other recorded window was
// closed, or brought back by the dock or Exposé, and is no longer ours.
function stillMinimized(entries, toplevels) {
    return (entries || []).filter(function (entry) {
        var top = toplevelFor(entry, toplevels);
        return top !== null && WindowModel.isMinimized(top);
    });
}

function addresses(entries) {
    return (entries || []).map(function (entry) { return entry.address; });
}

// Lua that brings windows back to their own workspaces without following them
// and without animating in, as the dock restores a window. A workspace that
// emptied and closed during the peek is recreated on the display the minimized
// windows sit on, so it is moved back to the display its windows came from.
function restoreLua(entries, existingWorkspaceIds) {
    var lua = (entries || []).map(function (entry) {
        var target = "window = 'address:" + entry.address + "'";
        return "hl.dispatch(hl.dsp.window.set_prop({ prop = 'no_anim', value = '1', " + target + " })); "
            + "hl.dispatch(hl.dsp.window.move({ workspace = '" + Number(entry.workspaceId)
            + "', follow = false, " + target + " }))";
    });
    var placed = {};
    (entries || []).forEach(function (entry) {
        var id = Number(entry.workspaceId);
        var monitor = monitorName(entry.monitor);
        if (!monitor || placed[id] || (existingWorkspaceIds || []).indexOf(id) !== -1)
            return;
        placed[id] = true;
        lua.push("hl.dispatch(hl.dsp.workspace.move({ workspace = '" + id + "', monitor = '" + monitor + "' }))");
    });
    return lua.join("; ");
}

function animationLua(entries) {
    return (entries || []).map(function (entry) {
        return "hl.dispatch(hl.dsp.window.set_prop({ prop = 'no_anim', value = 'unset', window = 'address:"
            + entry.address + "' }))";
    }).join("; ");
}

// What a saved record may contain; anything else is dropped rather than
// trusted, since the file outlives the process that wrote it.
function parseRecord(text) {
    var entries = [];
    try {
        var data = JSON.parse(String(text || ""));
        var list = data && Array.isArray(data.entries) ? data.entries : [];
        for (var index = 0; index < list.length && entries.length < 256; index++) {
            var entry = list[index];
            if (!entry || !/^0x[0-9a-fA-F]+$/.test(String(entry.address)) || !(Number(entry.workspaceId) >= 1))
                continue;
            entries.push({ address: String(entry.address),
                stableId: entry.stableId === null || entry.stableId === undefined ? null : String(entry.stableId),
                workspaceId: Number(entry.workspaceId), monitor: monitorName(entry.monitor) });
        }
    } catch (error) {
        return [];
    }
    return entries;
}
