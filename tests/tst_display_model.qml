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
}
