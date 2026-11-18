import QtQuick
import QtTest
import "../ScreenLayout.js" as ScreenLayout

TestCase {
    name: "ScreenLayout"

    function test_outermostDisplay_data() {
        return [
            { tag: "top-left", position: "top-left", expected: "left" },
            { tag: "bottom-left", position: "bottom-left", expected: "left" },
            { tag: "top-right", position: "top-right", expected: "right" },
            { tag: "bottom-right", position: "bottom-right", expected: "right" }
        ];
    }

    function test_outermostDisplay(data) {
        // Screens have logical sizes but no usable desktop positions.
        var screens = [
            { name: "middle", width: 4096, height: 1152 },
            { name: "right", width: 1080, height: 1920 },
            { name: "left", width: 1920, height: 1080 }
        ];
        var monitors = [
            { name: "middle", x: 0, y: 0 },
            { name: "right", x: 4096, y: -200 },
            { name: "left", x: -1920, y: 100 }
        ];
        compare(ScreenLayout.hotCornerScreens(screens, monitors, data.position, false)[0].name, data.expected);
        compare(ScreenLayout.hotCornerScreens(screens.reverse(), monitors, data.position, false)[0].name, data.expected);
    }

    function test_rightmostUsesRightEdge() {
        var wide = { name: "wide", width: 3000, height: 1000 };
        var narrow = { name: "narrow", width: 1000, height: 1000 };
        var monitors = [{ name: "wide", x: 0, y: 0 }, { name: "narrow", x: 1000, y: 1000 }];
        compare(ScreenLayout.hotCornerScreens([narrow, wide], monitors, "top-right", false), [wide]);
    }

    function test_stackedDisplaysUseChosenVerticalCorner() {
        var upper = { name: "upper", width: 1920, height: 1080 };
        var lower = { name: "lower", width: 1920, height: 1080 };
        var monitors = [{ name: "upper", x: 0, y: -1080 }, { name: "lower", x: 0, y: 0 }];
        for (var side of ["left", "right"]) {
            compare(ScreenLayout.hotCornerScreens([lower, upper], monitors, "top-" + side, false), [upper]);
            compare(ScreenLayout.hotCornerScreens([upper, lower], monitors, "bottom-" + side, false), [lower]);
        }
    }

    function test_displaysRunLeftToRightThenTopToBottom() {
        var screens = [
            { name: "right", width: 1080, height: 1920 },
            { name: "lower", width: 1920, height: 1080 },
            { name: "upper", width: 2560, height: 1440 }
        ];
        var monitors = [
            { name: "lower", x: -1920, y: 0 },
            { name: "right", x: 640, y: -200 },
            { name: "upper", x: -1920, y: -1440 }
        ];
        compare(ScreenLayout.displays(screens, monitors), [
            { name: "upper", x: -1920, y: -1440, width: 2560, height: 1440 },
            { name: "lower", x: -1920, y: 0, width: 1920, height: 1080 },
            { name: "right", x: 640, y: -200, width: 1080, height: 1920 }
        ]);
    }

    function test_displayWithoutMonitorSitsAtTheOrigin() {
        compare(ScreenLayout.displays([{ name: "new", width: 1920, height: 1080 }], []),
            [{ name: "new", x: 0, y: 0, width: 1920, height: 1080 }]);
    }

    function test_allDisplaysAndHotplug() {
        var left = { name: "left", width: 1920, height: 1080 };
        var right = { name: "right", width: 1920, height: 1080 };
        var monitors = [{ name: "left", x: -1920, y: 0 }, { name: "right", x: 0, y: 0 }];
        compare(ScreenLayout.hotCornerScreens([left, right], monitors, "top-left", true), [left, right]);
        compare(ScreenLayout.hotCornerScreens([right], monitors, "top-left", false), [right]);
        compare(ScreenLayout.hotCornerScreens([], monitors, "top-left", false), []);
        monitors[1].x = -3840;
        compare(ScreenLayout.hotCornerScreens([left, right], monitors, "top-left", false), [right]);
        compare(ScreenLayout.hotCornerScreens([left], [], "top-left", false), []);
    }
}
