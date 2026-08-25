.pragma library

function normalize(value) {
    var result = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    return result.slice(-8) === ".desktop" ? result.slice(0, -8) : result;
}

function identityFor(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {};
    var wayland = toplevel && toplevel.wayland ? toplevel.wayland : null;
    var appId = normalize(wayland && wayland.appId);
    var windowClass = normalize(ipc.class);
    var initialClass = normalize(ipc.initialClass);
    var candidates = [];

    function add(candidate) {
        if (candidate && candidates.indexOf(candidate) === -1)
            candidates.push(candidate);
    }

    add(appId);
    add(windowClass);
    add(initialClass);
    return {
        key: [appId, windowClass, initialClass].join("|"),
        candidates: candidates
    };
}

function visibleEntries(entries) {
    var result = [];
    for (var index = 0; index < entries.length; index++)
        if (entries[index] && !entries[index].noDisplay)
            result.push(entries[index]);
    return result;
}

function uniqueIconEntry(matches) {
    if (matches.length === 0)
        return null;
    var icon = String(matches[0].icon || "");
    for (var index = 1; index < matches.length; index++)
        if (String(matches[index].icon || "") !== icon)
            return null;
    return matches[0];
}

function findEntry(entries, candidates) {
    var visible = visibleEntries(entries || []);

    for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
        var candidate = normalize(candidates[candidateIndex]);
        for (var entryIndex = 0; entryIndex < visible.length; entryIndex++)
            if (normalize(visible[entryIndex].id) === candidate)
                return visible[entryIndex];
    }

    for (var startupIndex = 0; startupIndex < candidates.length; startupIndex++) {
        var startupCandidate = normalize(candidates[startupIndex]);
        for (var startupEntryIndex = 0; startupEntryIndex < visible.length; startupEntryIndex++)
            if (normalize(visible[startupEntryIndex].startupClass) === startupCandidate)
                return visible[startupEntryIndex];
    }

    for (var nameIndex = 0; nameIndex < candidates.length; nameIndex++) {
        var nameCandidate = normalize(candidates[nameIndex]);
        var matches = [];
        for (var nameEntryIndex = 0; nameEntryIndex < visible.length; nameEntryIndex++)
            if (normalize(visible[nameEntryIndex].name) === nameCandidate)
                matches.push(visible[nameEntryIndex]);
        var unique = uniqueIconEntry(matches);
        if (unique)
            return unique;
    }

    return null;
}
