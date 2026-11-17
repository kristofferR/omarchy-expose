// Keep capture lifecycle decisions independent from Wayland so they can be
// covered by the QML unit tests without a running compositor.
function active(opened, surfaceMounted, visible) {
    return Boolean((opened || surfaceMounted) && visible);
}

function live(opened, visible, lowLoadPreviews) {
    return Boolean(opened && visible && !lowLoadPreviews);
}

function captureSource(enabled, restarting, source) {
    return enabled && !restarting ? source : null;
}

function shouldCaptureStill(enabled, liveUpdates, source) {
    return Boolean(enabled && !liveUpdates && source);
}
