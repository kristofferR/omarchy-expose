import QtQuick
import QtTest
import "../WorkspaceModel.js" as WorkspaceModel

TestCase {
    name: "WorkspaceModel"

    function test_stripListsThisMonitorsNumberedWorkspacesInOrder() {
        var left = {name: "DP-1"};
        var right = {name: "DP-2"};
        var workspaces = [
            {id: 13, monitor: right},
            {id: 2, monitor: left},
            {id: 11, monitor: right},
            {id: -98, name: "special:minimized", monitor: right},
            {id: 12, monitor: null}
        ];
        compare(WorkspaceModel.stripWorkspaces(workspaces, "DP-2").map(function (workspace) { return workspace.id; }), [11, 13]);
        compare(WorkspaceModel.stripWorkspaces(workspaces, "DP-1").length, 1);
    }

    function test_addedWorkspacesJoinTheStripUntilTheyExist() {
        var monitor = {name: "DP-2"};
        var real = [{id: 1, monitor: monitor}, {id: 3, monitor: monitor}];
        var added = [WorkspaceModel.placeholder(4, "DP-2"), WorkspaceModel.placeholder(3, "DP-2"),
            WorkspaceModel.placeholder(14, "HDMI-A-1")];
        var strip = WorkspaceModel.withPlaceholders(real, added, "DP-2");
        compare(strip.map(function (workspace) { return workspace.id; }), [1, 3, 4]);
        compare(strip[1], real[1]);
        compare(strip[2], added[0]);
    }

    function test_blockComesFromOmarchyStateElseActiveWorkspace() {
        var state = "0\tDP-2\tSamsung LC49G95T\n1\tHDMI-A-1\tDell U2720Q\n";
        compare(WorkspaceModel.blockFor(state, "HDMI-A-1", 3), 1);
        compare(WorkspaceModel.blockFor(state, "DP-2", 14), 0);
        // A monitor Omarchy has not recorded, or no state file at all.
        compare(WorkspaceModel.blockFor(state, "DP-3", 24), 2);
        compare(WorkspaceModel.blockFor("", "DP-3", 0), 0);
        compare(WorkspaceModel.slotId(1, 10), 20);
    }

    function test_newWorkspaceFollowsTheHighestElseFillsAGap() {
        compare(WorkspaceModel.newWorkspaceId([1, 2, 4, 15], 0), 5);
        compare(WorkspaceModel.newWorkspaceId([12], 1), 13);
        compare(WorkspaceModel.newWorkspaceId([], 1), 11);
        compare(WorkspaceModel.newWorkspaceId([1, 2, 3, 4, 6, 7, 8, 9, 10], 0), 5);
        compare(WorkspaceModel.newWorkspaceId([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0), -1);
    }

    function test_numberRowPicksSlotsOnAnyLayout() {
        compare(WorkspaceModel.slotForKey(Qt.Key_1, 10), 1);
        compare(WorkspaceModel.slotForKey(Qt.Key_0, 19), 10);
        // AZERTY's unshifted number row types symbols at the same positions.
        compare(WorkspaceModel.slotForKey(Qt.Key_Ampersand, 10), 1);
        compare(WorkspaceModel.slotForKey(Qt.Key_7, 0), 7);
        compare(WorkspaceModel.slotForKey(Qt.Key_A, 38), 0);
    }

    function test_thumbnailStacksLikeTheScreen() {
        var tiledRecent = WorkspaceModel.stackLevel({focusHistoryID: 0});
        var tiledOld = WorkspaceModel.stackLevel({focusHistoryID: 4});
        var floatingOld = WorkspaceModel.stackLevel({floating: true, focusHistoryID: 9});
        var fullscreen = WorkspaceModel.stackLevel({fullscreen: 1, focusHistoryID: 20});
        verify(tiledRecent > tiledOld);
        verify(floatingOld > tiledRecent);
        verify(fullscreen > floatingOld);
    }

    function test_thumbnailSkipsHiddenGroupMembers() {
        var tops = [
            {workspace: {id: 3}, lastIpcObject: {}},
            {workspace: {id: 3}, lastIpcObject: {hidden: true}},
            {workspace: {id: 4}, lastIpcObject: {}}
        ];
        compare(WorkspaceModel.windowsOn(tops, 3).length, 1);
    }
}
