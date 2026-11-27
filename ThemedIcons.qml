import QtQuick
import Quickshell
import Quickshell.Io

// The app icons Omarchy 4.6 draws in the theme's colors. A theme switch redraws
// them in place, and the icon theme lookup keeps serving the previous drawing.
// These are served as file URLs that change with every drawing instead.
Item {
    id: root

    // As Omarchy's omarchy-theme-set-icons: the drawn icons, the links that put
    // them in the icon theme, and the file it rewrites after each drawing.
    property string drawnDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/icons"
    property string linksDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/icons/hicolor/scalable/apps"
    property string revisionFile: Quickshell.env("HOME") + "/.local/state/omarchy/current/icons.revision"
    // Icon name to file, for the links that point at a drawn icon.
    property var paths: ({})
    // New with every scan, so a URL from an earlier drawing is never reused,
    // by this component or a later instance of it in the same process.
    property string revision: ""
    property bool rescanQueued: false

    // The URL of a drawn icon, or "" for an icon Omarchy does not draw.
    function source(name) {
        var key = String(name || "");
        if (!Object.prototype.hasOwnProperty.call(root.paths, key))
            return "";
        return "file://" + root.paths[key].split("/").map(encodeURIComponent).join("/") + "?theme=" + root.revision;
    }

    function rescan() {
        if (scan.running)
            root.rescanQueued = true;
        else
            scan.running = true;
    }

    Component.onCompleted: root.rescan()

    FileView {
        path: root.revisionFile
        watchChanges: true
        printErrors: false
        onFileChanged: root.rescan()
    }

    Process {
        id: scan
        // Each link with its target. A missing directory lists nothing.
        command: ["find", root.linksDir, "-maxdepth", "1", "-type", "l", "-name", "*.svg", "-printf", "%f\\t%l\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                var paths = {};
                var lines = String(text || "").split("\n");
                for (var index = 0; index < lines.length; index++) {
                    var tab = lines[index].indexOf("\t");
                    var target = lines[index].slice(tab + 1);
                    // A link elsewhere is the user's own icon, which stays put.
                    if (tab > 0 && target.indexOf(root.drawnDir + "/") === 0)
                        paths[lines[index].slice(0, tab - ".svg".length)] = target;
                }
                root.paths = paths;
                root.revision = String(Date.now());
            }
        }
        onExited: {
            if (root.rescanQueued) {
                root.rescanQueued = false;
                scan.running = true;
            }
        }
    }
}
