import QtQuick
import QtTest
import "../WindowModel.js" as WindowModel

TestCase {
    id: testCase
    name: "NativeWindowModel"

    Component {
        id: toplevelComponent

        QtObject {
            property string address: "abc123"
            property string title: "Window title"
            property var lastIpcObject: ({
                mapped: true,
                class: "native.class",
                initialClass: "native.initial",
                size: [1600, 1000],
                pinned: false
            })
            property var workspace: ({id: 2, name: "2"})
            property var monitor: ({id: 0, name: "DP-1"})
            property var wayland: ({appId: "wayland.app"})
        }
    }

    function createToplevel(properties) {
        var toplevel = toplevelComponent.createObject(testCase, properties || {});
        verify(toplevel !== null);
        return toplevel;
    }

    function test_usesStableNativeAddress() {
        var toplevel = createToplevel();
        compare(WindowModel.addressFor(toplevel), "0xabc123");
        toplevel.address = "not-an-address";
        compare(WindowModel.addressFor(toplevel), "");
        toplevel.destroy();
    }

    function test_prefersWaylandAppIdWithNativeFallback() {
        var toplevel = createToplevel();
        compare(WindowModel.appIdFor(toplevel), "wayland.app");
        toplevel.wayland.appId = "";
        compare(WindowModel.appIdFor(toplevel), "native.class");
        toplevel.lastIpcObject = ({initialClass: "native.initial"});
        compare(WindowModel.appIdFor(toplevel), "native.initial");
        toplevel.destroy();
    }

    function test_excludesUnmappedOrUncapturableWindows() {
        var toplevel = createToplevel();
        verify(WindowModel.isEligible(toplevel));
        toplevel.lastIpcObject = ({mapped: false});
        verify(!WindowModel.isEligible(toplevel));
        toplevel.lastIpcObject = ({mapped: true});
        toplevel.wayland = null;
        verify(!WindowModel.isEligible(toplevel));
        toplevel.destroy();
    }

    function test_matchesWorkspaceIdentityAndPinnedWindows() {
        var toplevel = createToplevel();
        verify(WindowModel.isOnWorkspace(toplevel, {id: 2, name: "2"}));
        verify(!WindowModel.isOnWorkspace(toplevel, {id: 3, name: "3"}));
        toplevel.lastIpcObject = ({pinned: true});
        verify(WindowModel.isOnWorkspace(toplevel, {id: 3, name: "3"}));
        toplevel.destroy();
    }

    function test_matchesScreenOnlyInPerMonitorMode() {
        var toplevel = createToplevel();
        verify(WindowModel.isOnScreen(toplevel, "DP-1", true));
        verify(!WindowModel.isOnScreen(toplevel, "HDMI-A-1", true));
        verify(WindowModel.isOnScreen(toplevel, "HDMI-A-1", false));
        toplevel.destroy();
    }

    function test_readsAndClampsNativeAspectRatio() {
        var toplevel = createToplevel();
        compare(WindowModel.aspectRatioFor(toplevel), 1.6);
        toplevel.lastIpcObject = ({size: [10000, 100]});
        compare(WindowModel.aspectRatioFor(toplevel), 4);
        toplevel.lastIpcObject = ({size: [100, 10000]});
        compare(WindowModel.aspectRatioFor(toplevel), 0.45);
        toplevel.lastIpcObject = ({size: [0, 0]});
        compare(WindowModel.aspectRatioFor(toplevel), 1.6);
        toplevel.destroy();
    }

    function test_searchesAllNativeIdentityFields() {
        var toplevel = createToplevel();
        verify(WindowModel.searchTextFor(toplevel).includes("wayland.app"));
        verify(WindowModel.searchTextFor(toplevel).includes("native.class"));
        verify(WindowModel.searchTextFor(toplevel).includes("native.initial"));
        verify(WindowModel.searchTextFor(toplevel).includes("window title"));
        toplevel.destroy();
    }
}
