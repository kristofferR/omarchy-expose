import QtQuick
import Quickshell.Wayland
import "CapturePolicy.js" as CapturePolicy

// A window capture that starts again when Hyprland ends it. That happens when
// the window moves to another workspace, or is resized while hidden. Quickshell
// then drops the frame without emitting `stopped`, and never captures again on
// its own. A hidden window can take seconds to draw at its new size, and a
// restart before then can sit without a frame, so a new capture or restart that
// shows nothing within a second is retried too. The waits grow: 0.25, 0.5, 1,
// 2, 4, then 8 s.
ScreencopyView {
    id: capture

    required property var source
    // Capture only while Exposé is open. In still mode, this also makes each
    // opening take a fresh frame without keeping hidden captures alive.
    property bool active: true
    property bool restarting: false
    property int failures: 0

    captureSource: CapturePolicy.captureSource(capture.active, capture.restarting, capture.source)
    paintCursor: false

    function captureStillIfNeeded(source) {
        if (CapturePolicy.shouldCaptureStill(capture.active, capture.live, source))
            capture.captureFrame();
    }

    function scheduleRestart() {
        if (!capture.active || capture.failures >= 6 || !capture.source)
            return;
        restartTimer.interval = 250 * Math.pow(2, capture.failures);
        capture.failures++;
        capture.restarting = true;
        contentCheck.stop();
        restartTimer.restart();
    }

    onHasContentChanged: {
        if (!capture.active)
            return;
        if (capture.hasContent) {
            capture.failures = 0;
            contentCheck.stop();
        } else if (!capture.restarting) {
            capture.scheduleRestart();
        }
    }
    onStopped: {
        if (capture.active)
            capture.scheduleRestart();
    }
    onActiveChanged: {
        if (capture.active) {
            capture.failures = 0;
            contentCheck.restart();
            if (!capture.live)
                Qt.callLater(function () { capture.captureStillIfNeeded(capture.captureSource); });
        } else {
            restartTimer.stop();
            contentCheck.stop();
            capture.restarting = false;
        }
    }
    onLiveChanged: {
        if (capture.active && !capture.live)
            Qt.callLater(function () { capture.captureStillIfNeeded(capture.captureSource); });
    }
    onCaptureSourceChanged: {
        if (capture.active && capture.captureSource && !capture.live)
            Qt.callLater(function () { capture.captureStillIfNeeded(capture.captureSource); });
    }
    // A capture can start mid-resize, such as when closing a window rebuilds
    // the cards while its neighbour grows, and never get a first frame.
    Component.onCompleted: contentCheck.restart()

    Timer {
        id: restartTimer
        onTriggered: {
            capture.restarting = false;
            contentCheck.restart();
        }
    }

    Timer {
        id: contentCheck
        interval: 1000
        onTriggered: {
            if (!capture.hasContent)
                capture.scheduleRestart();
        }
    }
}
