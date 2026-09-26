.pragma library

function usesOwnWindows(mode) {
    return mode === "per-monitor" || mode === "all-monitors";
}

function mountedScreens(screens, selectedScreen, mode, mounted) {
    if (!mounted)
        return [];
    if (mode !== "all-monitors")
        return selectedScreen ? [selectedScreen] : [];

    var result = [];
    for (var index = 0; index < screens.length; index++)
        if (screens[index])
            result.push(screens[index]);
    return result;
}

function backdropScreens(screens, selectedScreen, mode, mounted) {
    if (!mounted || mode === "all-monitors")
        return [];

    var result = [];
    for (var index = 0; index < screens.length; index++)
        if (screens[index] && screens[index] !== selectedScreen)
            result.push(screens[index]);
    return result;
}

function keyboardTargets(instances) {
    for (var index = 0; index < instances.length; index++)
        if (instances[index] && instances[index].acceptsKeyboard)
            return instances[index].keyboardTargets;
    return [];
}

function directionalTarget(targets, screenName, selectedIndex, dx, dy, fallback) {
    var current = null;
    for (var currentIndex = 0; currentIndex < targets.length; currentIndex++) {
        var entry = targets[currentIndex];
        if (entry.screenName === screenName && entry.index === selectedIndex) {
            current = entry;
            break;
        }
    }
    if (!current)
        current = fallback;
    if (!current)
        return null;

    var currentX = current.x + current.width / 2;
    var currentY = current.y + current.height / 2;
    var best = null;
    var bestScore = Number.MAX_VALUE;
    for (var index = 0; index < targets.length; index++) {
        var candidate = targets[index];
        if (candidate === current)
            continue;
        var deltaX = candidate.x + candidate.width / 2 - currentX;
        var deltaY = candidate.y + candidate.height / 2 - currentY;
        var primary = dx !== 0 ? deltaX * dx : deltaY * dy;
        if (primary <= 0)
            continue;
        var cross = dx !== 0 ? Math.abs(deltaY) : Math.abs(deltaX);
        var score = primary + cross * cross / Math.max(1, primary) * 2;
        if (score < bestScore) {
            bestScore = score;
            best = candidate;
        }
    }
    return best;
}
