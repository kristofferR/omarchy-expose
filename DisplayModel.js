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
