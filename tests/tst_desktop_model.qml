import QtQuick
import QtTest
import "../DesktopModel.js" as DesktopModel

TestCase {
    id: testCase
    name: "DesktopModel"

    Component {
        id: toplevelComponent

        QtObject {
            property string address: "a1"
            property var lastIpcObject: ({ mapped: true, stableId: "100", pinned: false, fullscreen: 0, grouped: [] })
            property var workspace: ({ id: 1, name: "1" })
            property var wayland: ({ appId: "app" })
        }
    }

    function window(address, workspace, ipc) {
        var base = { mapped: true, stableId: address + "-id", pinned: false, fullscreen: 0, grouped: [] };
        for (var key in (ipc || {}))
            base[key] = ipc[key];
        var top = toplevelComponent.createObject(testCase, { address: address, workspace: workspace, lastIpcObject: base });
        verify(top !== null);
        return top;
    }

    function test_visibleWorkspacesAreSortedRegularAndUnique() {
        var monitors = [
            { activeWorkspace: { id: 12 } }, { activeWorkspace: { id: 3 } },
            { activeWorkspace: { id: -98 } }, { activeWorkspace: { id: 3 } }, { activeWorkspace: null }
        ];
        compare(DesktopModel.visibleWorkspaceIds(monitors), [3, 12]);
        verify(DesktopModel.sameWorkspaces([3, 12], [3, 12]));
        verify(!DesktopModel.sameWorkspaces([3, 12], [3, 13]));
        verify(!DesktopModel.sameWorkspaces([3], [3, 12]));
    }

    function test_candidatesAreOrdinaryWindowsInView() {
        var ws1 = { id: 1, name: "1" };
        var tops = [
            window("a1", ws1),
            window("a2", { id: 2, name: "2" }),                       // not in view
            window("a3", ws1, { pinned: true }),                        // on every workspace
            window("a4", ws1, { fullscreen: 2 }),                       // nothing behind it
            window("a5", ws1, { grouped: ["0xa5", "0xa6"] }),           // would leave its group
            window("a6", { id: -99, name: "special:minimized" }),       // already away
            window("a7", ws1, { mapped: false }),
            window("a8", ws1, { hidden: true })
        ];
        compare(DesktopModel.candidates(tops, [1]), [{ address: "0xa1", stableId: "a1-id", workspaceId: 1 }]);
    }

    function test_onlyRecordedWindowsStillMinimizedComeBack() {
        var minimized = { id: -99, name: "special:minimized" };
        var tops = [
            window("b1", minimized),
            window("b2", { id: 1, name: "1" }),          // brought back by the dock
            window("b4", minimized, { stableId: "new" }) // address reused by a new window
        ];
        var entries = [
            { address: "0xb1", stableId: "b1-id", workspaceId: 1 },
            { address: "0xb2", stableId: "b2-id", workspaceId: 1 },
            { address: "0xb3", stableId: "b3-id", workspaceId: 1 },   // closed
            { address: "0xb4", stableId: "b4-id", workspaceId: 1 }
        ];
        compare(DesktopModel.stillMinimized(entries, tops).map(function (entry) { return entry.address; }), ["0xb1"]);
    }

    function test_restoreGoesBackToEachOwnWorkspaceWithoutFollowing() {
        var lua = DesktopModel.restoreLua([
            { address: "0xc1", workspaceId: 3 }, { address: "0xc2", workspaceId: 14 }
        ]);
        verify(lua.indexOf("workspace = '3', follow = false, window = 'address:0xc1'") !== -1);
        verify(lua.indexOf("workspace = '14', follow = false, window = 'address:0xc2'") !== -1);
        verify(lua.indexOf("no_anim") !== -1);
        verify(DesktopModel.animationLua([{ address: "0xc1" }]).indexOf("value = 'unset'") !== -1);
    }

    // The record outlives the process that wrote it, so nothing in it is
    // trusted: an address that is not hex never reaches a Lua string.
    function test_savedRecordIsValidated() {
        var text = JSON.stringify({ entries: [
            { address: "0xd1", stableId: "7", workspaceId: 2 },
            { address: "0xd2' }) os.execute('x", workspaceId: 2 },
            { address: "0xd3", workspaceId: 0 },
            { address: "0xd4", stableId: null, workspaceId: "5" }
        ] });
        compare(DesktopModel.parseRecord(text), [
            { address: "0xd1", stableId: "7", workspaceId: 2 },
            { address: "0xd4", stableId: null, workspaceId: 5 }
        ]);
        compare(DesktopModel.parseRecord("not json"), []);
        compare(DesktopModel.parseRecord(""), []);
    }
}
