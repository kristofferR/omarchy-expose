.pragma library

// macOS-style hot corners: each of the four corners runs one action, chosen
// independently, as in System Settings > Desktop & Dock > Hot Corners.
//
//   all-windows  Exposé with every window (Mission Control)
//   app-windows  Exposé with the focused app's windows (Application Windows)
//   desktop      move windows aside to show the desktop (Desktop)
//   off          nothing
//
// Entries saved before per-corner actions name a single corner in
// hotCornerPosition, which opened all windows. That corner is the default; a
// corner's own key, when present, overrides it. So upgrading changes nothing,
// and hand-adding one corner's key never silently turns off another. Any
// change made in Settings or over IPC stores all four keys (settingsFor), after
// which the legacy default no longer matters.

var positions = ["top-left", "top-right", "bottom-left", "bottom-right"];

var keys = {
    "top-left": "hotCornerTopLeft",
    "top-right": "hotCornerTopRight",
    "bottom-left": "hotCornerBottomLeft",
    "bottom-right": "hotCornerBottomRight"
};

var actions = ["off", "all-windows", "app-windows", "desktop"];

function isPosition(position) { return positions.indexOf(position) !== -1; }
function isAction(action) { return actions.indexOf(action) !== -1; }
function keyFor(position) { return keys[position]; }
function onTop(position) { return String(position).indexOf("top-") === 0; }
function onLeft(position) { return String(position).indexOf("-left") !== -1; }

function legacyPosition(entry) {
    var position = entry ? String(entry.hotCornerPosition) : "";
    return isPosition(position) ? position : "top-left";
}

// { "top-left": action, ... } for a stored entry: the legacy corner opens all
// windows unless overridden, each stored key decides its own corner, and an
// unknown stored action reads as off rather than guessing.
function read(entry) {
    var map = {};
    var legacy = legacyPosition(entry);
    for (var index = 0; index < positions.length; index++) {
        var position = positions[index];
        var stored = entry ? entry[keys[position]] : undefined;
        if (stored === undefined)
            map[position] = position === legacy ? "all-windows" : "off";
        else
            map[position] = isAction(String(stored)) ? String(stored) : "off";
    }
    return map;
}

// The settings to store for a full corner map: every corner, so the legacy
// fallback is never consulted again, and hotCornerPosition naming the first
// all-windows corner so an older Exposé keeps opening from it.
function settingsFor(map) {
    var settings = {};
    var legacy = "";
    for (var index = 0; index < positions.length; index++) {
        var position = positions[index];
        var action = isAction(map[position]) ? map[position] : "off";
        settings[keys[position]] = action;
        if (!legacy && action === "all-windows")
            legacy = position;
    }
    if (legacy)
        settings.hotCornerPosition = legacy;
    return settings;
}

// One corner changes; the others keep what they had.
function withAction(entry, position, action) {
    var map = read(entry);
    map[position] = action;
    return settingsFor(map);
}

// The older single-corner setting: the chosen corner opens all windows and no
// other corner does, while corners with other actions keep them.
function withAllWindowsAt(entry, position) {
    var map = read(entry);
    for (var index = 0; index < positions.length; index++)
        if (map[positions[index]] === "all-windows")
            map[positions[index]] = "off";
    map[position] = "all-windows";
    return settingsFor(map);
}

// The corners that do something, in a fixed order.
function active(map) {
    var result = [];
    for (var index = 0; index < positions.length; index++) {
        var position = positions[index];
        if (map[position] && map[position] !== "off")
            result.push({ position: position, action: map[position] });
    }
    return result;
}
