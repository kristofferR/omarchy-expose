// Resolve a drop without mutating compositor state. Monitor targets use their
// live active workspace at release; workspace targets use the selected monitor.
function destinationAtDragStart(selectedMonitor, sourceMonitor) {
    return selectedMonitor || sourceMonitor;
}

function destination(target, selectedMonitor, activeWorkspace) {
    if (target === null || target === undefined) return null;
    if (typeof target === "object") {
        var monitor = String(target.monitor || "");
        var workspace = Number(activeWorkspace);
        return monitor && workspace > 0 ? {monitor: monitor, workspace: workspace} : null;
    }
    if (!selectedMonitor || (target !== "new" && !(Number(target) > 0))) return null;
    return {monitor: selectedMonitor, workspace: target};
}
