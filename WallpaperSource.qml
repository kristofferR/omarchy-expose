import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool active: false
    // Use the same link as Omarchy's background plugin.
    property string backgroundLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    property string resolvedPath: ""
    readonly property url source: root.resolvedPath
        ? "file://" + root.resolvedPath.split("/").map(encodeURIComponent).join("/")
        : ""

    function refresh() {
        if (root.active && !readlinkProcess.running)
            readlinkProcess.running = true;
    }

    onActiveChanged: {
        if (root.active)
            root.refresh();
        else
            root.resolvedPath = "";
    }
    onBackgroundLinkChanged: root.refresh()
    Component.onCompleted: root.refresh()

    // Symlink replacement does not reliably trigger an image file watcher.
    // Poll only while the wallpaper backdrop is in use, resolving the target
    // so Qt's image cache does not retain the previous symlink destination.
    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: readlinkProcess
        command: ["readlink", "-e", "--", root.backgroundLink]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.active)
                    root.resolvedPath = String(text || "").trim();
            }
        }
    }
}
