.pragma library

// One entry per simple setting stored in the plugin's shell.json entry. Reading,
// setting, IPC validation, and the settings pages all derive from this table.
// A spec with `options` is an enum, one with `min`/`max` an integer, and one
// with only `fallback` a boolean. Composite settings (animation timing, slide
// direction) keep their own handling in the overview.
var specs = {
    previewPlacement: {
        fallback: "in-place",
        options: [
            { label: "In place", value: "in-place" },
            { label: "Centered", value: "centered" }
        ]
    },
    windowFooterStyle: {
        fallback: "floating",
        options: [
            { label: "Floating", value: "floating" },
            { label: "Rail", value: "integrated" },
            { label: "Overlay", value: "overlay" },
            { label: "Centered", value: "centered" }
        ]
    },
    selectionStyle: {
        fallback: "outline",
        options: [
            { label: "Outline", value: "outline" },
            { label: "Lift", value: "lift" }
        ]
    },
    animationStyle: {
        fallback: "original",
        options: [
            { label: "Original", value: "original" },
            { label: "Fade", value: "fade" },
            { label: "Zoom", value: "zoom" },
            { label: "Slide", value: "slide" }
        ]
    },
    hotCornerPosition: {
        fallback: "top-left",
        options: [
            { label: "Top left", value: "top-left" },
            { label: "Top right", value: "top-right" },
            { label: "Bottom left", value: "bottom-left" },
            { label: "Bottom right", value: "bottom-right" }
        ]
    },
    initialWorkspaceScope: {
        fallback: "all",
        options: [
            { label: "All workspaces", value: "all" },
            { label: "Current", value: "current" }
        ]
    },
    workspaceLabelStyle: {
        fallback: "full",
        options: [
            { label: "Full", value: "full" },
            { label: "Slot only", value: "slot" }
        ]
    },
    multiMonitorMode: {
        fallback: "mirrored",
        options: [
            { label: "All displays", description: "Windows from every display", value: "mirrored" },
            { label: "This display", description: "Only windows on this display", value: "per-monitor" }
        ]
    },
    backgroundBlur: { fallback: 4, min: 0, max: 20 },
    backgroundDim: { fallback: 6, min: 0, max: 90 },
    hotCornerDelay: { fallback: 0, min: 0, max: 1000 },
    hotCornerEnabled: { fallback: true },
    hotCornerAllDisplays: { fallback: false },
    moveCursorToWindow: { fallback: true },
    showFooter: { fallback: true }
};

function spec(name) {
    var found = specs[name];
    if (!found)
        throw new Error("unknown setting " + name);
    return found;
}

function isEnum(name) { return Array.isArray(spec(name).options); }
function isInteger(name) { return spec(name).min !== undefined; }

function options(name) { return spec(name).options; }

function values(name) {
    return options(name).map(function (option) { return option.value; });
}

function clamp(name, numeric) {
    var s = spec(name);
    return Math.max(s.min, Math.min(s.max, Math.round(numeric)));
}

// The stored value as the overview uses it: anything missing or invalid reads
// as the fallback. A boolean whose fallback is true is only off when stored as
// false; one whose fallback is false is only on when stored as true.
function read(entry, name) {
    var s = spec(name);
    var raw = entry ? entry[name] : undefined;
    if (isEnum(name)) {
        var text = String(raw);
        return values(name).indexOf(text) !== -1 ? text : s.fallback;
    }
    if (isInteger(name)) {
        var numeric = raw === null || raw === undefined ? NaN : Number(raw);
        return isFinite(numeric) ? clamp(name, numeric) : s.fallback;
    }
    return s.fallback ? raw !== false : raw === true;
}

// The value a setter stores. An unusable number keeps the current value
// rather than resetting to the fallback.
function normalize(name, value, current) {
    if (isEnum(name)) {
        var text = String(value);
        return values(name).indexOf(text) !== -1 ? text : spec(name).fallback;
    }
    if (isInteger(name)) {
        var numeric = Number(value);
        return isFinite(numeric) ? clamp(name, numeric) : current;
    }
    return value === true;
}

// IPC rejection text derived from the option list it validates against.
function expectedOneOf(list) {
    if (list.length === 1)
        return "expected " + list[0];
    var head = list.slice(0, -1).join(", ");
    return "expected " + head + (list.length > 2 ? ", or " : " or ") + list[list.length - 1];
}

// IPC arguments: enums must name an option and booleans are "on"/"off".
// Integers pass through; normalize() clamps them or keeps the current value.
// Returns { value } or { error }.
function parseIpc(name, text) {
    if (isEnum(name))
        return values(name).indexOf(text) !== -1 ? { value: text } : { error: expectedOneOf(values(name)) };
    if (isInteger(name))
        return { value: text };
    if (text === "on" || text === "off")
        return { value: text === "on" };
    return { error: "expected on or off" };
}
