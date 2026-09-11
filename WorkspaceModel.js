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
