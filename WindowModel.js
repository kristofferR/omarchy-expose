.pragma library

function ipcFor(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject;
    return ipc && typeof ipc === "object" ? ipc : {};
}

function waylandFor(toplevel) {
    return toplevel && toplevel.wayland ? toplevel.wayland : null;
}

function appIdFor(toplevel) {
    var wayland = waylandFor(toplevel);
    if (wayland && wayland.appId)
        return String(wayland.appId);
    var ipc = ipcFor(toplevel);
    return String(ipc.class || ipc.initialClass || "");
}

function addressFor(toplevel) {
    var address = String((toplevel && toplevel.address) || "");
    return /^[0-9a-fA-F]+$/.test(address) ? "0x" + address : "";
}

function isEligible(toplevel) {
    return Boolean(waylandFor(toplevel)) && ipcFor(toplevel).mapped !== false;
}

function workspaceName(toplevel) {
    var workspace = toplevel && toplevel.workspace ? toplevel.workspace : null;
    return workspace ? String(workspace.name || workspace.id || "—") : "—";
}

// Workspace names are free-form in Hyprland. Plugins that give every monitor its
// own set name them "<monitor description>:<slot>", which is far too wide for a
// card footer, so "slot" keeps the trailing slot number. Anything else, including
// "special:scratchpad", is returned unchanged.
function formatWorkspaceLabel(name, style) {
    var text = String(name === null || name === undefined ? "" : name);
    if (style !== "slot" || text.indexOf("special:") === 0)
        return text;
    var match = text.match(/^.+:(\d+)$/);
    return match ? match[1] : text;
}

function isOnScreen(toplevel, screenName, perMonitor) {
    if (!perMonitor)
        return true;
    var monitor = toplevel && toplevel.monitor ? toplevel.monitor : null;
    return Boolean(monitor) && String(monitor.name || "") === String(screenName || "");
}

function isOnWorkspace(toplevel, workspace) {
    var toplevelWorkspace = toplevel && toplevel.workspace ? toplevel.workspace : null;
    if (!toplevelWorkspace || !workspace)
        return false;
    if (ipcFor(toplevel).pinned === true || toplevelWorkspace === workspace)
        return true;

    var toplevelId = Number(toplevelWorkspace.id);
    var workspaceId = Number(workspace.id);
    if (isFinite(toplevelId) && isFinite(workspaceId) && toplevelId !== 0 && workspaceId !== 0)
        return toplevelId === workspaceId;

    var workspaceName = String(workspace.name || "");
    return Boolean(workspaceName) && String(toplevelWorkspace.name || "") === workspaceName;
}

function aspectRatioFor(toplevel) {
    var size = ipcFor(toplevel).size || [];
    var width = Number(size[0]);
    var height = Number(size[1]);
    if (size.length < 2 || !isFinite(width) || !isFinite(height) || width <= 0 || height <= 0)
        return 1.6;
    return Math.max(0.45, Math.min(4, width / height));
}

function searchTextFor(toplevel) {
    var ipc = ipcFor(toplevel);
    return (appIdFor(toplevel) + " " + String(ipc.class || "") + " "
        + String(ipc.initialClass || "") + " " + String((toplevel && toplevel.title) || "")).toLowerCase();
}

// The window Hyprland focused last, by focus history; null when none is known.
function mostRecent(toplevels) {
    for (var index = 0; index < toplevels.length; index++)
        if (ipcFor(toplevels[index]).focusHistoryID === 0)
            return toplevels[index];
    return null;
}

// What Enter opens: the chosen window while it is listed, else the window the
// overview was opened from, else the first listed window.
function selectionFor(listed, selected, origin) {
    if (selected && listed.indexOf(selected) !== -1)
        return selected;
    if (origin && listed.indexOf(origin) !== -1)
        return origin;
    return listed.length ? listed[0] : null;
}

// The window to select after windows close: the selection while it is still
// listed, else the window that took its place, so Shift+Q can close several
// windows in a row.
function successorFor(previous, listed, selected) {
    if (!selected || listed.indexOf(selected) !== -1)
        return selected;
    var index = previous.indexOf(selected);
    if (index < 0 || !listed.length)
        return null;
    return listed[Math.min(index, listed.length - 1)];
}
