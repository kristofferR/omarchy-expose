.pragma library

// The Glide animation, after Mission Control: every window on screen travels
// from where it really is to its place in the grid, all on one curve, and
// travels back on closing. Windows that are not on screen (another workspace,
// minimized) grow into place instead of flying in from nowhere.

// Where the window is drawn on its display, in display-local coordinates, or
// null when it is not on screen there. `ipc` is the window's Hyprland client
// object and `monitorIpc` the display's monitor object.
function startRect(ipc, monitorIpc) {
    if (!ipc || !monitorIpc || ipc.hidden === true || ipc.mapped === false)
        return null;
    var at = ipc.at;
    var size = ipc.size;
    if (!at || !size || at.length < 2 || size.length < 2)
        return null;
    var width = Number(size[0]);
    var height = Number(size[1]);
    if (!(width > 0) || !(height > 0))
        return null;
    var workspace = ipc.workspace ? Number(ipc.workspace.id) : NaN;
    var active = monitorIpc.activeWorkspace ? Number(monitorIpc.activeWorkspace.id) : NaN;
    var special = monitorIpc.specialWorkspace ? Number(monitorIpc.specialWorkspace.id) : 0;
    // A pinned window shows on every workspace of its display.
    var shown = ipc.pinned === true || workspace === active || (special !== 0 && workspace === special);
    if (!isFinite(workspace) || !shown)
        return null;
    if (ipc.monitor !== undefined && monitorIpc.id !== undefined && Number(ipc.monitor) !== Number(monitorIpc.id))
        return null;
    return {
        x: Number(at[0]) - Number(monitorIpc.x || 0),
        y: Number(at[1]) - Number(monitorIpc.y || 0),
        width: width,
        height: height
    };
}

// Scale a window grows from when it has no place on screen.
var growFrom = 0.9;

// The rectangle a preview is drawn in at `progress` (0 on the desktop, 1 in
// the grid), between `start` (or growing in place without one) and `final`.
function rectAt(start, final, progress) {
    var p = Math.max(0, Math.min(1, Number(progress)));
    if (!start) {
        var k = growFrom + (1 - growFrom) * p;
        var width = final.width * k;
        var height = final.height * k;
        return {
            x: final.x + (final.width - width) / 2,
            y: final.y + (final.height - height) / 2,
            width: width,
            height: height
        };
    }
    return {
        x: start.x + (final.x - start.x) * p,
        y: start.y + (final.y - start.y) * p,
        width: start.width + (final.width - start.width) * p,
        height: start.height + (final.height - start.height) * p
    };
}

function smoothstep(edge0, edge1, value) {
    var t = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
    return t * t * (3 - 2 * t);
}

// The backdrop that covers the desktop behind the previews. The previews are
// opaque from the first frame and lie exactly on their windows, so the real
// windows only show where a preview has moved off them; the backdrop covers
// them quickly on opening, and stays until the previews have landed on
// closing, so a window is never seen twice in flight.
function coverOpacity(progress, opening) {
    return smoothstep(0, opening ? 0.15 : 0.04, progress);
}

// In Desktop mode the overview rests on the live, blurred desktop. The cover
// (the wallpaper) hides the real windows only while previews are in flight,
// and gives way to the blurred desktop as they land.
function desktopCoverOpacity(progress, opening) {
    return coverOpacity(progress, opening) * (1 - smoothstep(0.75, 1, progress));
}

// Titles, borders, and buttons appear only as the previews land.
function chromeOpacity(progress) {
    return smoothstep(0.65, 1, progress);
}

// Opacity of a preview without a place on screen.
function growOpacity(progress) {
    return smoothstep(0, 0.6, progress);
}

// Stacking while the previews overlap their windows: floating and fullscreen
// windows above tiled ones, and within each, the most recently focused on top.
// The chosen window lands on top of its own kind only: focus does not lift a
// tiled window over the floating and fullscreen ones.
function stackZ(ipc, chosen) {
    var raised = ipc && (ipc.floating === true || Number(ipc.fullscreen || 0) > 0) ? 1 : 0;
    var history = ipc && isFinite(Number(ipc.focusHistoryID)) ? Number(ipc.focusHistoryID) : 899;
    return raised + (chosen ? 0.95 : 0.9 - Math.max(0, Math.min(899, history)) / 1000);
}
