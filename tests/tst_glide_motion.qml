import QtQuick
import QtTest
import "../GlideMotion.js" as GlideMotion

TestCase {
    name: "GlideMotion"

    readonly property var monitor: ({
        id: 1, x: 2560, y: 0,
        activeWorkspace: {id: 3}, specialWorkspace: {id: 0}
    })

    function client(extra) {
        var ipc = {at: [2660, 50], size: [800, 600], workspace: {id: 3}, monitor: 1,
            hidden: false, mapped: true, floating: false, fullscreen: 0, focusHistoryID: 2};
        for (var key in extra)
            ipc[key] = extra[key];
        return ipc;
    }

    function test_startRectIsLocalToItsDisplay() {
        compare(GlideMotion.startRect(client({}), monitor), {x: 100, y: 50, width: 800, height: 600});
    }

    function test_windowsOffScreenHaveNoStartRect() {
        compare(GlideMotion.startRect(client({workspace: {id: 4}}), monitor), null);
        compare(GlideMotion.startRect(client({workspace: {id: -98, name: "special:minimized"}}), monitor), null);
        compare(GlideMotion.startRect(client({hidden: true}), monitor), null);
        compare(GlideMotion.startRect(client({mapped: false}), monitor), null);
        compare(GlideMotion.startRect(client({monitor: 0}), monitor), null);
        compare(GlideMotion.startRect(client({size: [0, 0]}), monitor), null);
        compare(GlideMotion.startRect({}, monitor), null);
    }

    function test_closingOntoAnotherWorkspaceLandsOnItsWindows() {
        // The display shows workspace 3 and is about to show 4.
        compare(GlideMotion.startRect(client({workspace: {id: 4}}), monitor, "4"), {x: 100, y: 50, width: 800, height: 600});
        compare(GlideMotion.startRect(client({}), monitor, "4"), null);
        verify(GlideMotion.startRect(client({workspace: {id: 7}, pinned: true}), monitor, "4") !== null);
    }

    function test_workspacesAreToldApartAsHyprlandNamesThem() {
        // Hyprland 0.57: an address for every workspace, an id for numbered ones only.
        function shows(active, special) {
            return {id: 1, x: 2560, y: 0, activeWorkspace: active, specialWorkspace: special || {address: "", type: "", name: ""}};
        }
        var mail = {address: "mail", type: "normal", name: "mail"};
        var chat = {address: "chat", type: "normal", name: "chat"};
        verify(GlideMotion.startRect(client({workspace: mail}), shows(mail)) !== null);
        compare(GlideMotion.startRect(client({workspace: chat}), shows(mail)), null);
        verify(GlideMotion.startRect(client({workspace: chat}), shows(mail), "chat") !== null);
        var three = {address: "3", id: 3, type: "normal", name: "3"};
        var scratchpad = {address: "special:scratchpad", type: "special", name: "special:scratchpad"};
        verify(GlideMotion.startRect(client({workspace: scratchpad}), shows(three, scratchpad)) !== null);
        verify(GlideMotion.startRect(client({workspace: three}), shows(three, scratchpad)) !== null);
        // Workspace 4 renamed "3" is still not workspace 3.
        compare(GlideMotion.startRect(client({workspace: {address: "4", id: 4, type: "normal", name: "3"}}), shows(three)), null);
        // Before 0.57 there is no address, and no special workspace shown has id 0.
        var old = {id: 1, x: 2560, y: 0, activeWorkspace: {id: 3, name: "3"}, specialWorkspace: {id: 0, name: ""}};
        verify(GlideMotion.startRect(client({workspace: {id: 3, name: "3"}}), old) !== null);
        compare(GlideMotion.startRect(client({workspace: {id: -1337, name: "mail"}}), old), null);
    }

    function test_shownSpecialWorkspaceCountsAsOnScreen() {
        var shown = {id: 1, x: 2560, y: 0, activeWorkspace: {id: 3}, specialWorkspace: {id: -99}};
        verify(GlideMotion.startRect(client({workspace: {id: -99}}), shown) !== null);
        verify(GlideMotion.startRect(client({}), shown) !== null);
    }

    function test_rectRunsFromWindowToGridSlot() {
        var start = {x: 0, y: 0, width: 1000, height: 500};
        var final = {x: 100, y: 200, width: 200, height: 100};
        compare(GlideMotion.rectAt(start, final, 0), start);
        compare(GlideMotion.rectAt(start, final, 1), final);
        compare(GlideMotion.rectAt(start, final, 0.5), {x: 50, y: 100, width: 600, height: 300});
    }

    function test_withoutStartRectThePreviewGrowsAroundItsSlot() {
        var final = {x: 100, y: 100, width: 200, height: 100};
        var r = GlideMotion.rectAt(null, final, 0);
        compare(r.width, 180);
        compare(r.x + r.width / 2, 200);
        compare(r.y + r.height / 2, 150);
        compare(GlideMotion.rectAt(null, final, 1), final);
    }

    function test_coverHidesTheDesktopEarlyOnOpeningAndLateOnClosing() {
        compare(GlideMotion.coverOpacity(0, true), 0);
        compare(GlideMotion.coverOpacity(0.15, true), 1);
        // Closing keeps the windows covered until the previews have nearly landed.
        compare(GlideMotion.coverOpacity(0.05, false), 1);
        verify(GlideMotion.coverOpacity(0.02, false) < 1);
        compare(GlideMotion.coverOpacity(0, false), 0);
    }

    // The blur and dim are gone before a closing's cover starts to leave, so
    // they never pop away with it.
    function test_backdropFadesBeforeTheCoverLeaves() {
        compare(GlideMotion.backdropStrength(1), 1);
        verify(GlideMotion.backdropStrength(0.5) > 0.5 && GlideMotion.backdropStrength(0.5) < 1);
        for (var progress = 0; progress <= 1; progress += 0.01)
            if (GlideMotion.coverOpacity(progress, false) < 1)
                compare(GlideMotion.backdropStrength(progress), 0);
    }

    function test_titlesWaitForThePreviewsToLand() {
        compare(GlideMotion.chromeOpacity(0.5), 0);
        compare(GlideMotion.chromeOpacity(1), 1);
    }

    function test_pinnedWindowIsOnScreenOnAnyWorkspace() {
        verify(GlideMotion.startRect(client({workspace: {id: 7}, pinned: true}), monitor) !== null);
        compare(GlideMotion.startRect(client({workspace: {id: 7}, pinned: true, monitor: 0}), monitor), null);
    }

    function test_floatingAndRecentWindowsStackOnTop() {
        verify(GlideMotion.stackZ({floating: true, focusHistoryID: 5}) > GlideMotion.stackZ({floating: false, focusHistoryID: 0}));
        verify(GlideMotion.stackZ({fullscreen: 1, focusHistoryID: 0}) > GlideMotion.stackZ({floating: true, focusHistoryID: 1}));
        verify(GlideMotion.stackZ({focusHistoryID: 0}) > GlideMotion.stackZ({focusHistoryID: 1}));
    }

    function test_chosenWindowLandsOnTopOfItsOwnKind() {
        var tiled = GlideMotion.stackZ({focusHistoryID: 4}, true);
        verify(tiled > GlideMotion.stackZ({focusHistoryID: 0}));
        verify(tiled < GlideMotion.stackZ({floating: true, focusHistoryID: 899}));
        verify(GlideMotion.stackZ({floating: true, focusHistoryID: 4}, true)
            > GlideMotion.stackZ({fullscreen: 2, focusHistoryID: 0}));
    }
}
