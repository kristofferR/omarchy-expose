import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    readonly property string testDir: Quickshell.env("EXPOSE_WALLPAPER_TEST_DIR")
    readonly property string first: testDir + "/first image #?.svg"
    readonly property string second: testDir + "/second.svg"
    property int phase: 0
    property int ticks: 0

    WallpaperSource {
        id: wallpaper
        backgroundLink: test.testDir + "/background"
    }

    Image { id: image; source: wallpaper.source; asynchronous: true }

    Process { id: changeLink }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.quit();
            throw Error(message);
        }
    }

    function link(path) {
        require(!changeLink.running, "previous link operation completed");
        changeLink.command = ["ln", "-sfn", "--", path, wallpaper.backgroundLink];
        changeLink.running = true;
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            test.ticks++;
            test.require(test.ticks < 120, "wallpaper refresh completed before timeout");
            if (test.phase === 0) {
                test.require(wallpaper.resolvedPath === "", "inactive source stays empty");
                wallpaper.active = true;
                test.phase = 1;
            } else if (test.phase === 1 && wallpaper.resolvedPath === test.first && image.status === Image.Ready) {
                test.require(decodeURIComponent(String(wallpaper.source)) === "file://" + test.first,
                    "URL round-trips spaces, hash and question mark: " + wallpaper.source);
                test.link(test.second);
                test.phase = 2;
            } else if (test.phase === 2 && wallpaper.resolvedPath === test.second && image.status === Image.Ready) {
                // No manual refresh: the active poll must follow replacement.
                wallpaper.active = false;
                test.phase = 3;
                test.ticks = 0;
            } else if (test.phase === 3 && test.ticks >= 12) {
                test.require(wallpaper.resolvedPath === "" && String(wallpaper.source) === "", "inactive source releases its path and stops polling");
                wallpaper.active = true;
                test.phase = 4;
            } else if (test.phase === 4 && wallpaper.resolvedPath === test.second) {
                test.link(test.testDir + "/missing.svg");
                test.phase = 5;
            } else if (test.phase === 5 && wallpaper.resolvedPath === "") {
                test.require(String(wallpaper.source) === "", "broken link clears the previous wallpaper");
                test.link(test.first);
                test.phase = 6;
            } else if (test.phase === 6 && wallpaper.resolvedPath === test.first && image.status === Image.Ready) {
                wallpaper.active = false;
                console.log("PASS: wallpaper link resolution, encoded paths, live replacement, inactive cleanup, broken link and recovery");
                Qt.quit();
            }
        }
    }
}
