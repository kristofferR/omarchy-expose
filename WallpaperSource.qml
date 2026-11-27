pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool active: false
    // Keeps the last resolved path while inactive, resolving it once even then,
    // so the backdrop's decoded image can stay cached between uses.
    property bool retained: false
    // Use the same link as Omarchy's background plugin.
    property string backgroundLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    // A video wallpaper shows the still that Omarchy's lock screen uses.
    property string posterScript: Quickshell.env("OMARCHY_PATH") + "/shell/plugins/lock/poster.sh"
    // The file the link points at, and the image to draw for it.
    property string linkTarget: ""
    property string resolvedPath: ""
    readonly property url source: root.resolvedPath
        ? "file://" + root.resolvedPath.split("/").map(encodeURIComponent).join("/")
        : ""

    readonly property bool resolving: root.active || root.retained

    function refresh() {
        if (root.resolving && !readlinkProcess.running)
            readlinkProcess.running = true;
    }

    // As Omarchy's Util.isVideoPath.
    function isVideoPath(path) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(path || ""));
    }

    function requestPoster() {
        if (!root.resolving || !root.isVideoPath(root.linkTarget) || posterProcess.running)
            return;
        posterProcess.sourcePath = root.linkTarget;
        posterProcess.running = true;
    }

    onLinkTargetChanged: {
        if (root.isVideoPath(root.linkTarget)) {
            root.resolvedPath = "";
            root.requestPoster();
        } else {
            root.resolvedPath = root.linkTarget;
        }
    }

    onResolvingChanged: {
        if (root.resolving) {
            root.refresh();
        } else {
            root.linkTarget = "";
            root.resolvedPath = "";
        }
    }
    onActiveChanged: root.refresh()
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

    // Omarchy replaces the link in place. A watch on the folder holding it
    // sees that, where a watch on the link follows it to the old image.
    // While retained, this keeps the path current between openings, so the
    // next opening shows the new wallpaper already decoded. Created only
    // while resolving: a folder model without a folder watches the working
    // directory instead.
    Instantiator {
        active: root.resolving
        model: 1
        delegate: FolderListModel {
            readonly property string linkFolder: root.backgroundLink.replace(/\/[^\/]*$/, "")
            folder: "file://" + linkFolder.split("/").map(encodeURIComponent).join("/")
            nameFilters: [root.backgroundLink.replace(/^.*\//, "")]
            showDirs: false
            showHidden: true
            onStatusChanged: {
                if (status === FolderListModel.Ready)
                    root.refresh();
            }
        }
    }

    Process {
        id: readlinkProcess
        command: ["readlink", "-e", "--", root.backgroundLink]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.resolving)
                    root.linkTarget = String(text || "").replace(/\n$/, "");
            }
        }
    }

    Process {
        id: posterProcess
        property string sourcePath: ""
        command: ["bash", root.posterScript, posterProcess.sourcePath]
        stdout: StdioCollector { id: posterOutput }
        onExited: function (exitCode) {
            // The link moved on while this still was being made.
            if (posterProcess.sourcePath !== root.linkTarget) {
                root.requestPoster();
                return;
            }
            if (root.resolving)
                root.resolvedPath = exitCode === 0 ? String(posterOutput.text || "").replace(/\n$/, "") : "";
        }
    }
}
