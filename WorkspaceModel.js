.pragma library

function idFor(workspace) {
    var id = Number(workspace && workspace.id);
    return isFinite(id) ? id : 0;
}

function nameFor(workspace) {
    return workspace ? String(workspace.name || "") : "";
}

function keyFor(workspace) {
    var id = idFor(workspace);
    if (id !== 0)
        return "id:" + id;

    var name = nameFor(workspace);
    return name ? "name:" + name : "";
}

function labelFor(workspace) {
    var name = nameFor(workspace);
    if (name)
        return name;

    var id = idFor(workspace);
    return id !== 0 ? String(id) : "—";
}

function isNumbered(workspace) {
    return idFor(workspace) > 0;
}

function isSpecial(workspace) {
    var name = nameFor(workspace);

    return name === "special"
        || name.indexOf("special:") === 0;
}

function workspaceSelector(workspace) {
    if (!workspace || isSpecial(workspace))
        return "";

    var id = idFor(workspace);

    if (id > 0)
        return String(id);

    var name = nameFor(workspace);

    if (!name)
        return "";

    // Reject control characters. Besides being invalid UI labels,
    // they should never reach a compositor dispatcher request.
    for (var index = 0; index < name.length; index++) {
        var code = name.charCodeAt(index);

        if (code < 32 || code === 127)
            return "";
    }

    if (name.indexOf("name:") === 0)
        return name;

    return "name:" + name;
}

function valuesFor(source) {
    if (!source)
        return [];

    var values = source;

    // Quickshell ObjectModel exposes its items through a `values`
    // property. Plain JavaScript arrays also have a `values()` method,
    // so only unwrap non-function `values` properties.
    if (!Array.isArray(source)
            && source.values !== undefined
            && typeof source.values !== "function") {
        values = source.values;
    }

    var length = Number(values && values.length);

    if (!isFinite(length) || length < 0)
        return [];

    var result = [];
    for (var index = 0; index < length; index++)
        result.push(values[index]);

    return result;
}

function overviewWorkspaces(workspaces) {
    var source = valuesFor(workspaces);
    var result = [];

    for (var index = 0; index < source.length; index++) {
        var workspace = source[index];

        if (workspace
                && keyFor(workspace)
                && !isSpecial(workspace)) {
            result.push(workspace);
        }
    }

    result.sort(compareWorkspaces);
    return result;
}

function gridColumns(count) {
    var total = Number(count);

    if (!isFinite(total) || total <= 0)
        return 1;

    total = Math.floor(total);

    return Math.max(
        1,
        Math.ceil(Math.sqrt(total))
    );
}

function moveGridIndex(current, count, columns, horizontal, vertical) {
    var total = Number(count);

    if (!isFinite(total) || total <= 0)
        return 0;

    total = Math.floor(total);

    var columnCount = Number(columns);

    if (!isFinite(columnCount) || columnCount < 1)
        columnCount = gridColumns(total);
    else
        columnCount = Math.floor(columnCount);

    var selected = Number(current);

    if (!isFinite(selected))
        selected = 0;

    selected = Math.max(
        0,
        Math.min(
            total - 1,
            Math.floor(selected)
        )
    );

    var row = Math.floor(selected / columnCount);
    var column = selected % columnCount;

    var horizontalStep = Number(horizontal);
    var verticalStep = Number(vertical);

    horizontalStep = isFinite(horizontalStep)
        ? (horizontalStep < 0 ? -1 : (horizontalStep > 0 ? 1 : 0))
        : 0;

    verticalStep = isFinite(verticalStep)
        ? (verticalStep < 0 ? -1 : (verticalStep > 0 ? 1 : 0))
        : 0;

    if (horizontalStep !== 0) {
        var nextColumn = column + horizontalStep;

        if (nextColumn < 0 || nextColumn >= columnCount)
            return selected;

        var horizontalTarget =
            row * columnCount + nextColumn;

        return horizontalTarget < total
            ? horizontalTarget
            : selected;
    }

    if (verticalStep !== 0) {
        var rows = Math.ceil(total / columnCount);
        var nextRow = row + verticalStep;

        if (nextRow < 0 || nextRow >= rows)
            return selected;

        var verticalTarget =
            nextRow * columnCount + column;

        // When the last row is incomplete, move to the nearest
        // existing card in that row instead of falling outside
        // the workspace model.
        if (verticalTarget >= total)
            verticalTarget = total - 1;

        return verticalTarget;
    }

    return selected;
}

function compareWorkspaces(left, right) {
    var leftId = idFor(left);
    var rightId = idFor(right);
    var leftNumbered = leftId > 0;
    var rightNumbered = rightId > 0;

    if (leftNumbered && rightNumbered)
        return leftId - rightId;

    if (leftNumbered !== rightNumbered)
        return leftNumbered ? -1 : 1;

    var leftLabel = labelFor(left);
    var rightLabel = labelFor(right);

    if (leftLabel < rightLabel)
        return -1;
    if (leftLabel > rightLabel)
        return 1;

    return leftId - rightId;
}

function sorted(workspaces) {
    var result = valuesFor(workspaces);
    result.sort(compareWorkspaces);
    return result;
}
