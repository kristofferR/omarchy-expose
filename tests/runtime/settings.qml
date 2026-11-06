import QtQuick
import Quickshell
import Quickshell.Io
import "Commons"
ShellRoot {
    id: test
    property int phase: 0
    property string configPath: Quickshell.shellDir + "/config.json"
    QtObject {
        id: shell
        property var builtinShellConfig: ({version: 1, plugins: []})
        property var defaultsConfig: builtinShellConfig
        property var shellConfig: builtinShellConfig
        property bool userConfigUnreadable: false
// HOST FUNCTIONS
    }
    PluginShellApi {
        id: api
        pluginId: "expose.window-overview"
        _updateSettings: function(id, settings) { return shell.updateEntryInline(id, settings); }
    }
    FileView {
        id: userConfigFile
        path: test.configPath
        watchChanges: true
        atomicWrites: true
        onLoaded: shell.applyShellConfig()
        onFileChanged: reload()
    }
    PluginSettings {
        id: settings
        pluginId: "expose.window-overview"
        shell: api
        onReloadRequested: Qt.callLater(reader.reload)
    }
    FileView {
        id: reader
        path: test.configPath
        watchChanges: true
        onLoaded: settings.load(text())
        onLoadFailed: settings.loadFailed()
        onFileChanged: Qt.callLater(reader.reload)
    }
    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.quit();
            throw new Error(message);
        }
    }
    Timer {
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            if (!settings.ready || shell.shellConfig.plugins.length !== 2) return;
            if (test.phase === 0) {
                require(settings.entry.hotCornerEnabled === false, "saved disabled hot corner");
                test.phase = 1;
                settings.update("backgroundBlur", 0);
                settings.flush();
                for (var i = 0; i < 100; i++) {
                    settings.update("backgroundDim", i % 90);
                    settings.update("animationTimings", {slide: {"in": 200, "out": 300 + i, separate: true}});
                }
                settings.update("backgroundDim", 70);
                settings.update("hotCornerPosition", "bottom-right");
                require(settings.entry.backgroundDim === 70, "immediate UI updates");
            } else if (test.phase === 1 && !settings.inFlight && Object.keys(settings.pending).length === 0) {
                require(settings.entry.backgroundBlur === 0, "blur persists");
                require(settings.entry.backgroundDim === 70, "last dim persists");
                require(settings.entry.animationTimings.slide.out === 399, "nested timing persists");
                require(settings.entry.unknownSetting.preserve === true, "unknown field survives");
                require(settings.entry.hotCornerEnabled === false, "disabled hot corner survives");
                require(shell.shellConfig.plugins[0].keep === true, "other plugin survives");
                require(shell.shellConfig.bar.layout.left[0].keep === true, "bar survives");
                test.phase = 2;
                var config = JSON.parse(reader.text());
                config.plugins[1].backgroundDim = 25;
                delete config.plugins[1].hotCornerPosition;
                userConfigFile.setText(JSON.stringify(config));
            } else if (test.phase === 2 && settings.entry.backgroundDim === 25) {
                require(settings.entry.hotCornerPosition === undefined, "external deletion applies");
                console.log("PASS: real PluginShellApi, host persistence, 203 rapid edits, atomic file watching, external edits");
                Qt.quit();
            }
        }
    }
}
