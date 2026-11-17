import QtQuick
import QtTest
import "../MonitorTargets.js" as Targets

TestCase {
    name: "MonitorTargets"
    function test_workspaceUsesSelectedDestination() {
        compare(Targets.destination(21, "DP-1", 3), {monitor: "DP-1", workspace: 21});
        compare(Targets.destination("new", "DP-2", 0), {monitor: "DP-2", workspace: "new"});
    }
    function test_monitorUsesLiveActiveWorkspace() {
        compare(Targets.destination({monitor: "DP-2"}, "eDP-1", 31), {monitor: "DP-2", workspace: 31});
        compare(Targets.destination({monitor: "DP-2"}, "eDP-1", 32).workspace, 32);
    }
    function test_cancelAndMissingMonitorDoNothing() {
        compare(Targets.destination(null, "DP-1", 1), null);
        compare(Targets.destination({monitor: "DP-2"}, "DP-1", 0), null);
        compare(Targets.destination({monitor: "DP-2"}, "DP-1", "not-a-workspace"), null);
        compare(Targets.destination({monitor: ""}, "DP-1", 3), null);
        compare(Targets.destination(-98, "DP-1", 3), null);
    }
}
