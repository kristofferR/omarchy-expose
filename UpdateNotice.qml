import QtQuick
import Quickshell
import Quickshell.Io

// Tells someone who updated to 6.0 that the workspace strip, now on by
// default, is new and can be turned off. Shown once, and never after a clean
// install: an update fast-forwards the plugin's git checkout, which leaves
// ORIG_HEAD behind, while a fresh clone has none. Stored settings also mark an
// earlier install.
Item {
    id: root

    required property string pluginDir
    // The plugin's settings entry, once read from shell.json.
    property var entry: null
    property bool settingsReady: false

    readonly property string markerPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/omarchy-expose/strip-notice"
    property bool done: false
    // null until each file has been looked for.
    property var marked: null
    property var updated: null

    function hasStoredSettings(entry) {
        for (var key in entry || {})
            if (key !== "id")
                return true;
        return false;
    }

    function decide() {
        if (root.done || !root.settingsReady || root.marked === null || root.updated === null)
            return;
        root.done = true;
        if (root.marked)
            return;
        if (root.updated || root.hasStoredSettings(root.entry))
            Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Exposé",
                "Exposé now shows your workspaces",
                "The new workspace strip sits above your windows. Click to turn it off in Exposé settings.",
                "--exec", "omarchy-shell", "expose", "settings", "open"]);
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && : > \"$1\"", "sh", root.markerPath]);
    }

    onSettingsReadyChanged: root.decide()

    FileView {
        path: root.markerPath
        printErrors: false
        onLoaded: { root.marked = true; root.decide(); }
        onLoadFailed: { root.marked = false; root.decide(); }
    }

    FileView {
        path: root.pluginDir + "/.git/ORIG_HEAD"
        printErrors: false
        onLoaded: { root.updated = true; root.decide(); }
        onLoadFailed: { root.updated = false; root.decide(); }
    }
}
