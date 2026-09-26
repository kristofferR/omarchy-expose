import QtQuick
import QtTest
import "../DisplayModel.js" as DisplayModel
import "../WindowModel.js" as WindowModel

TestCase {
    name: "DisplayModel"

    function test_mountsOnlySelectedDisplayInExistingModes() {
        var screens = [{name: "DP-1"}, {name: "HDMI-A-1"}];
        compare(DisplayModel.mountedScreens(screens, screens[1], "mirrored", true).length, 1);
        compare(DisplayModel.mountedScreens(screens, screens[1], "mirrored", true)[0], screens[1]);
        compare(DisplayModel.mountedScreens(screens, screens[1], "per-monitor", true)[0], screens[1]);
        compare(DisplayModel.mountedScreens(screens, screens[1], "per-monitor", false).length, 0);
        compare(DisplayModel.backdropScreens(screens, screens[1], "mirrored", true)[0], screens[0]);
        compare(DisplayModel.backdropScreens(screens, screens[1], "per-monitor", true)[0], screens[0]);
    }

    function test_mountsEveryDisplayWithItsOwnWindows() {
        var screens = [{name: "DP-1"}, {name: "HDMI-A-1"}, {name: "DP-2"}, {name: "DP-3"}];
        var mounted = DisplayModel.mountedScreens(screens, screens[2], "all-monitors", true);
        compare(mounted.length, 4);
        for (var index = 0; index < screens.length; index++)
            compare(mounted[index], screens[index]);
        compare(DisplayModel.backdropScreens(screens, screens[2], "all-monitors", true).length, 0);

        verify(DisplayModel.usesOwnWindows("all-monitors"));
        verify(DisplayModel.usesOwnWindows("per-monitor"));
        verify(!DisplayModel.usesOwnWindows("mirrored"));
        var top = {monitor: {name: "DP-2"}};
        for (var screenIndex = 0; screenIndex < screens.length; screenIndex++)
            compare(WindowModel.isOnScreen(top, screens[screenIndex].name,
                DisplayModel.usesOwnWindows("all-monitors")), screenIndex === 2);
    }

    function test_unmountedAndMissingScreens() {
        var screens = [{name: "DP-1"}, null, {name: "DP-2"}];
        compare(DisplayModel.mountedScreens(screens, screens[0], "all-monitors", false).length, 0);
        compare(DisplayModel.mountedScreens(screens, screens[0], "all-monitors", true).length, 2);
        compare(DisplayModel.mountedScreens([], null, "all-monitors", true).length, 0);
        compare(DisplayModel.mountedScreens(screens, null, "per-monitor", true).length, 0);
        compare(DisplayModel.backdropScreens(screens, screens[0], "mirrored", false).length, 0);
    }

    function test_routesKeysToOpeningDisplay() {
        var openingTargets = ["opening grid"];
        var instances = [
            {acceptsKeyboard: false, keyboardTargets: ["other grid"]},
            {acceptsKeyboard: true, keyboardTargets: openingTargets},
            {acceptsKeyboard: false, keyboardTargets: ["another grid"]}
        ];
        compare(DisplayModel.keyboardTargets(instances), openingTargets);
        compare(DisplayModel.keyboardTargets([instances[0]]).length, 0);
    }

    function test_arrowNavigationCrossesDisplayBoundaries() {
        var targets = [
            {screenName: "left", index: 0, x: -1500, y: 200, width: 300, height: 200},
            {screenName: "left", index: 1, x: -500, y: 200, width: 300, height: 200},
            {screenName: "right", index: 0, x: 100, y: 220, width: 300, height: 200},
            {screenName: "right", index: 1, x: 900, y: 220, width: 300, height: 200}
        ];
        compare(DisplayModel.directionalTarget(targets, "left", 0, 1, 0, null), targets[1]);
        compare(DisplayModel.directionalTarget(targets, "left", 1, 1, 0, null), targets[2]);
        compare(DisplayModel.directionalTarget(targets, "right", 0, -1, 0, null), targets[1]);
        compare(DisplayModel.directionalTarget(targets, "right", 1, 1, 0, null), null);
    }

    function test_arrowNavigationUsesScreenCenterWhenItHasNoWindows() {
        var upper = {screenName: "upper", index: 0, x: 300, y: -800, width: 300, height: 200};
        var lower = {screenName: "lower", index: 0, x: 300, y: 400, width: 300, height: 200};
        var targets = [upper, lower];
        var emptyScreen = {x: 0, y: 0, width: 900, height: 600};
        compare(DisplayModel.directionalTarget(targets, "empty", 0, 0, -1, emptyScreen), upper);
        compare(DisplayModel.directionalTarget(targets, "empty", 0, 0, 1, emptyScreen), lower);
        compare(DisplayModel.directionalTarget(targets, "empty", 0, 1, 0, emptyScreen), null);
    }
}
