import QtQuick
import Quickshell.Wayland

// A window capture that starts again when Hyprland ends it. That happens when
// the window moves to another workspace, or is resized while hidden, and a
// stopped capture never resumes on its own. A hidden window can take seconds
// to draw at its new size, so the waits grow: 0.25, 0.5, 1, 2, then 4 s.
ScreencopyView {
    id: capture

    required property var source
    property bool restarting: false
    property int failures: 0

    captureSource: capture.restarting ? null : capture.source
    paintCursor: false

    onHasContentChanged: {
        if (capture.hasContent)
            capture.failures = 0;
    }
    onStopped: {
        if (capture.failures >= 5 || !capture.source)
            return;
        restartTimer.interval = 250 * Math.pow(2, capture.failures);
        capture.failures++;
        capture.restarting = true;
        restartTimer.restart();
    }

    Timer {
        id: restartTimer
        onTriggered: capture.restarting = false
    }
}
