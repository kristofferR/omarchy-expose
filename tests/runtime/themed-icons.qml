import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    readonly property string testDir: Quickshell.env("EXPOSE_ICONS_TEST_DIR")
    readonly property string drawn: "file://" + testDir + "/drawn/probe.svg?theme="
    property string firstSource: ""
    property int phase: 0
    property int ticks: 0

    ThemedIcons {
        id: icons
        drawnDir: test.testDir + "/drawn"
        linksDir: test.testDir + "/links"
        revisionFile: test.testDir + "/icons.revision"
    }

    // An Omarchy without drawn icons has none of these paths.
    ThemedIcons {
        id: absent
        drawnDir: test.testDir + "/absent/drawn"
        linksDir: test.testDir + "/absent/links"
        revisionFile: test.testDir + "/absent/icons.revision"
    }

    Window {
        visible: true
        width: 32
        height: 32

        Image {
            id: image
            anchors.fill: parent
            sourceSize.width: 32
            sourceSize.height: 32
            source: icons.source("probe")
        }
    }

    // As omarchy-theme-set-icons: the new drawing replaces the old with a
    // rename, then the revision file is rewritten.
    Process {
        id: redraw
        command: ["bash", "-c", "mv -f \"$1/next.svg\" \"$1/drawn/probe.svg\" && printf '2\\t1\\n' > \"$1/icons.revision\"", "bash", test.testDir]
    }

    function require(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.quit();
            throw Error(message);
        }
    }

    function capture(name, next) {
        test.phase = -1;
        image.grabToImage(function (result) {
            test.require(result.saveToFile(test.testDir + "/" + name + ".png"), "saved " + name);
            test.phase = next;
        });
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            test.ticks++;
            test.require(test.ticks < 120, "themed icon refresh completed before timeout, phase " + test.phase);
            if (test.phase === 0 && icons.revision !== "" && absent.revision !== "" && image.status === Image.Ready) {
                test.firstSource = icons.source("probe");
                test.require(test.firstSource.indexOf(test.drawn) === 0, "a linked drawn icon resolves to its file: " + test.firstSource);
                test.require(icons.source("own") === "", "a link to the user's own icon is left to the icon theme");
                test.require(icons.source("unknown") === "" && icons.source("constructor") === "", "other names are left to the icon theme");
                test.require(absent.source("probe") === "", "no drawn icons without Omarchy's icon directories");
                test.capture("first", 1);
            } else if (test.phase === 1) {
                redraw.running = true;
                test.phase = 2;
            } else if (test.phase === 2 && icons.source("probe") !== test.firstSource && image.status === Image.Ready) {
                test.require(icons.source("probe").indexOf(test.drawn) === 0, "the redrawn icon resolves to the same file: " + icons.source("probe"));
                test.capture("second", 3);
            } else if (test.phase === 3) {
                console.log("PASS: drawn icon lookup, own and unknown icons, absent directories, and redraw on a new revision");
                Qt.quit();
            }
        }
    }
}
