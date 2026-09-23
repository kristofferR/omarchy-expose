.pragma library

function sameWorkspace(left, right) {
    if (!left || !right)
        return false;
    if (Number(left.id) > 0 && Number(right.id) > 0)
        return Number(left.id) === Number(right.id);
    return String(left.name || "") !== "" && String(left.name) === String(right.name || "");
}

function nextWorkspaceId(workspaces) {
    var occupied = {};
    for (var index = 0; index < workspaces.length; index++) {
        var id = Number(workspaces[index].id);
        if (isFinite(id) && id > 0 && Math.floor(id) === id)
            occupied[id] = true;
    }
    var next = 1;
    while (occupied[next])
        next++;
    return next;
}

function entries(workspaces, toplevels, screenName, perMonitor, includeNewWorkspace) {
    var result = [];
    var wantedMonitor = String(screenName || "");
    for (var index = 0; index < workspaces.length; index++) {
        var workspace = workspaces[index];
        if (!workspace)
            continue;
        var monitorName = workspace.monitor ? String(workspace.monitor.name || "") : "";
        if (perMonitor && monitorName !== wantedMonitor)
            continue;
        var windows = [];
        for (var topIndex = 0; topIndex < toplevels.length; topIndex++) {
            var top = toplevels[topIndex];
            if (top && sameWorkspace(top.workspace, workspace))
                windows.push(top);
        }
        result.push({
            id: Number(workspace.id),
            name: String(workspace.name || workspace.id || "—"),
            monitorName: monitorName,
            active: workspace.active === true,
            workspace: workspace,
            windows: windows,
            isNew: false
        });
    }
    result.sort(function(left, right) {
        if (left.monitorName === wantedMonitor && right.monitorName !== wantedMonitor)
            return -1;
        if (right.monitorName === wantedMonitor && left.monitorName !== wantedMonitor)
            return 1;
        if (left.monitorName !== right.monitorName)
            return left.monitorName < right.monitorName ? -1 : 1;
        if (left.id !== right.id)
            return left.id - right.id;
        return left.name < right.name ? -1 : (left.name > right.name ? 1 : 0);
    });
    if (includeNewWorkspace === false)
        return result;
    var newId = nextWorkspaceId(workspaces);
    result.push({
        id: newId,
        name: String(newId),
        monitorName: wantedMonitor,
        active: false,
        workspace: null,
        windows: [],
        isNew: true
    });
    return result;
}

function canMove(top, target) {
    if (!top || !target || !top.workspace || !target.monitorName)
        return false;
    if (top.lastIpcObject && top.lastIpcObject.pinned === true)
        return false;
    return target.isNew || !sameWorkspace(top.workspace, target);
}
