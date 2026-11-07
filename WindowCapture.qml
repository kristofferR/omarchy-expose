import QtQuick
import Quickshell.Wayland

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
    property bool restarting: false
    property int failures: 0

    captureSource: capture.restarting ? null : capture.source
    paintCursor: false

    function scheduleRestart() {
        if (capture.failures >= 6 || !capture.source)
            return;
        restartTimer.interval = 250 * Math.pow(2, capture.failures);
        capture.failures++;
        capture.restarting = true;
        contentCheck.stop();
        restartTimer.restart();
    }

    onHasContentChanged: {
        if (capture.hasContent) {
            capture.failures = 0;
            contentCheck.stop();
        } else if (!capture.restarting) {
            capture.scheduleRestart();
        }
    }
    onStopped: capture.scheduleRestart()
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
