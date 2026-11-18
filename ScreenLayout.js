.pragma library

function named(list, name) {
    for (var index = 0; index < list.length; index++)
        if (list[index] && list[index].name === name)
            return list[index];
    return null;
}

// Every display's place on the desktop as { name, x, y, width, height } in
// logical pixels, left to right and then top to bottom. Hyprland supplies the
// positions and the screens their logical sizes; a display Hyprland does not
// list yet sits at the origin.
function displays(screens, monitors) {
    var result = [];
    for (var index = 0; index < screens.length; index++) {
        var screen = screens[index];
        if (!screen)
            continue;
        var monitor = named(monitors, screen.name);
        result.push({
            name: String(screen.name || ""),
            x: monitor ? Number(monitor.x) : 0,
            y: monitor ? Number(monitor.y) : 0,
            width: Number(screen.width),
            height: Number(screen.height)
        });
    }
    return result.sort(function (left, right) {
        return left.x - right.x || left.y - right.y || (left.name < right.name ? -1 : 1);
    });
}

// Hyprland supplies desktop positions; screen sizes are in logical pixels.
function hotCornerScreens(screens, monitors, position, allDisplays) {
    var onLeft = position.indexOf("-left") !== -1;
    var onTop = position.indexOf("top-") === 0;
    var result = [];
    var selected = null;
    var selectedEdge = 0;
    var selectedVertical = 0;
    for (var i = 0; i < screens.length; i++) {
        var screen = screens[i];
        if (!screen)
            continue;
        if (allDisplays) {
            result.push(screen);
            continue;
        }
        var monitor = named(monitors, screen.name);
        if (!monitor)
            continue;
        var edge = onLeft ? monitor.x : monitor.x + screen.width;
        var vertical = onTop ? monitor.y : monitor.y + screen.height;
        if (!selected
                || (onLeft ? edge < selectedEdge : edge > selectedEdge)
                || (edge === selectedEdge && (onTop ? vertical < selectedVertical : vertical > selectedVertical))
                || (edge === selectedEdge && vertical === selectedVertical && screen.name < selected.name)) {
            selected = screen;
            selectedEdge = edge;
            selectedVertical = vertical;
        }
    }
    if (selected)
        result.push(selected);
    return result;
}
