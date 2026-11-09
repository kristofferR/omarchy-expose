import QtQuick
import QtTest
import "../HotCorners.js" as HotCorners

TestCase {
    name: "HotCorners"

    function test_noEntryOpensAllWindowsFromTopLeftOnly() {
        compare(HotCorners.read(null), {
            "top-left": "all-windows", "top-right": "off", "bottom-left": "off", "bottom-right": "off"
        });
    }

    // Upgrading must not move anyone's corner.
    function test_legacyPositionReadsAsThatCorner() {
        var map = HotCorners.read({ hotCornerPosition: "bottom-right" });
        compare(map["bottom-right"], "all-windows");
        compare(map["top-left"], "off");
        compare(HotCorners.read({ hotCornerPosition: "nonsense" })["top-left"], "all-windows");
    }

    // A hand-added corner key must not silently turn off the legacy corner.
    function test_aCornerKeyOverridesOnlyItsOwnCorner() {
        var map = HotCorners.read({ hotCornerPosition: "top-right", hotCornerBottomLeft: "app-windows" });
        compare(map["top-right"], "all-windows");
        compare(map["bottom-left"], "app-windows");
        compare(map["top-left"], "off");
        compare(HotCorners.read({ hotCornerTopLeft: "off" })["top-left"], "off");
    }

    function test_storedCornersWinOverTheLegacyPosition() {
        var stored = HotCorners.withAction({ hotCornerPosition: "top-left" }, "top-left", "desktop");
        stored.hotCornerPosition = "bottom-right";   // an older version moved its corner
        var map = HotCorners.read(stored);
        compare(map["top-left"], "desktop");
        compare(map["bottom-right"], "off");
    }

    function test_unknownStoredActionReadsAsOff() {
        compare(HotCorners.read({ hotCornerTopRight: "launchpad" })["top-right"], "off");
    }

    function test_changingOneCornerStoresAllFourAndKeepsTheOthers() {
        var settings = HotCorners.withAction({ hotCornerPosition: "top-right" }, "bottom-right", "desktop");
        compare(settings, {
            hotCornerTopLeft: "off", hotCornerTopRight: "all-windows",
            hotCornerBottomLeft: "off", hotCornerBottomRight: "desktop",
            hotCornerPosition: "top-right"
        });
    }

    // Older Exposé versions read hotCornerPosition only.
    function test_legacyPositionFollowsTheFirstAllWindowsCorner() {
        var settings = HotCorners.withAction({ hotCornerTopLeft: "all-windows" }, "top-left", "app-windows");
        verify(!settings.hasOwnProperty("hotCornerPosition"));
        settings = HotCorners.withAction({ hotCornerTopLeft: "off" }, "bottom-left", "all-windows");
        compare(settings.hotCornerPosition, "bottom-left");
    }

    function test_legacyPositionCommandMovesAllWindowsOnly() {
        var entry = { hotCornerTopLeft: "all-windows", hotCornerBottomRight: "desktop", hotCornerBottomLeft: "app-windows" };
        var settings = HotCorners.withAllWindowsAt(entry, "top-right");
        compare(settings.hotCornerTopLeft, "off");
        compare(settings.hotCornerTopRight, "all-windows");
        compare(settings.hotCornerBottomLeft, "app-windows");
        compare(settings.hotCornerBottomRight, "desktop");
    }

    function test_activeCornersSkipOffInFixedOrder() {
        var active = HotCorners.active({
            "top-left": "off", "top-right": "all-windows", "bottom-left": "app-windows", "bottom-right": "desktop"
        });
        compare(active.map(function (corner) { return corner.position + "=" + corner.action; }),
            ["top-right=all-windows", "bottom-left=app-windows", "bottom-right=desktop"]);
    }

    function test_cornerGeometry() {
        verify(HotCorners.onTop("top-right") && !HotCorners.onLeft("top-right"));
        verify(!HotCorners.onTop("bottom-left") && HotCorners.onLeft("bottom-left"));
    }

    function test_fullscreenMeansFullscreenNotMaximized() {
        function monitor(name, modes) {
            return {
                name: name,
                activeWorkspace: {
                    hasFullscreen: modes.some(function (mode) { return mode > 0; }),
                    toplevels: { values: modes.map(function (mode) { return { lastIpcObject: { fullscreen: mode } }; }) }
                }
            };
        }
        var monitors = [monitor("DP-1", [0, 2]), monitor("DP-2", [1]), monitor("DP-3", [0])];
        verify(HotCorners.showsFullscreen(monitors, "DP-1"));
        verify(!HotCorners.showsFullscreen(monitors, "DP-2"));
        verify(!HotCorners.showsFullscreen(monitors, "DP-3"));
        verify(!HotCorners.showsFullscreen(monitors, "HDMI-A-1"));
    }

    function test_validation() {
        verify(HotCorners.isPosition("bottom-left"));
        verify(!HotCorners.isPosition("center"));
        verify(HotCorners.isAction("desktop"));
        verify(!HotCorners.isAction("mission-control"));
        compare(HotCorners.keyFor("bottom-right"), "hotCornerBottomRight");
    }
}
