import QtQuick
import QtTest
import "../WorkspaceModel.js" as WorkspaceModel

TestCase {
    name: "WorkspaceModel"

    readonly property var dp: ({name: "DP-1"})
    readonly property var hdmi: ({name: "HDMI-A-1"})

    function test_listsAndSortsWorkspacesWithNewDestination() {
        var workspaces = [
            {id: 3, name: "3", monitor: hdmi, active: true},
            {id: -4, name: "writing", monitor: dp, active: false},
            {id: 1, name: "1", monitor: dp, active: true}
        ];
        var windows = [
            {workspace: {id: 1, name: "1"}},
            {workspace: {id: 3, name: "3"}}
        ];
        var entries = WorkspaceModel.entries(workspaces, windows, "DP-1", false);
        compare(entries.length, 4);
        compare(entries[0].name, "writing");
        compare(entries[1].name, "1");
        compare(entries[1].windows.length, 1);
        compare(entries[2].monitorName, "HDMI-A-1");
        compare(entries[3].id, 2);
        verify(entries[3].isNew);
    }

    function test_perMonitorOnlyListsThatDisplay() {
        var workspaces = [
            {id: 1, name: "1", monitor: dp},
            {id: 2, name: "2", monitor: hdmi}
        ];
        var entries = WorkspaceModel.entries(workspaces, [], "DP-1", true);
        compare(entries.length, 2);
        compare(entries[0].name, "1");
        verify(entries[1].isNew);
        compare(entries[1].id, 3);
        compare(entries[1].monitorName, "DP-1");
    }

    function test_newWorkspaceTileCanBeOmitted() {
        var workspaces = [{id: 1, name: "1", monitor: dp}];
        var entries = WorkspaceModel.entries(workspaces, [], "DP-1", false, false);
        compare(entries.length, 1);
        verify(!entries[0].isNew);
    }

    function test_rejectsCurrentWorkspacePinnedAndUnknownTargets() {
        var top = {workspace: {id: 1, name: "1"}, lastIpcObject: {pinned: false}};
        verify(!WorkspaceModel.canMove(top, {id: 1, name: "1", monitorName: "DP-1"}));
        verify(WorkspaceModel.canMove(top, {id: 2, name: "2", monitorName: "DP-1"}));
        verify(!WorkspaceModel.canMove(top, {id: 2, name: "2", monitorName: ""}));
        top.lastIpcObject.pinned = true;
        verify(!WorkspaceModel.canMove(top, {id: 2, name: "2", monitorName: "DP-1"}));
    }
}
