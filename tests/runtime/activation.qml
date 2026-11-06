import QtQuick
import QtTest
import "WindowModel.js" as WindowModel

Item {
    id: root
    property var pendingActivation: null
    property bool moveCursorToWindow: false

    QtObject {
        id: hyprland
        property var focusedMonitor: ({activeWorkspace: {id: 4}})
        property var dispatches: []
        function dispatch(command) {
            dispatches.push(command);
        }
    }

// ACTIVATION COMPONENT

    TestCase {
        name: "MinimizedActivation"

        function restore(address) {
            root.pendingActivation = {address: address, workspace: {name: "special:minimized"}};
            root.dispatchPendingActivation();
        }

        function test_rapidRestoresCleanUpEveryWindow() {
            restore("abc123");
            wait(100);
            restore("def456");
            compare(hyprland.dispatches.length, 2);
            verify(hyprland.dispatches[0].indexOf("value = '1'") >= 0);
            verify(hyprland.dispatches[1].indexOf("value = '1'") >= 0);
            tryVerify(function() { return hyprland.dispatches.length === 4; }, 1000);
            verify(hyprland.dispatches[2].indexOf("value = 'unset', window = 'address:0xabc123'") >= 0);
            verify(hyprland.dispatches[3].indexOf("value = 'unset', window = 'address:0xdef456'") >= 0);

            // A later restore must not replay targets from the previous batch.
            restore("fed789");
            tryVerify(function() { return hyprland.dispatches.length === 6; }, 1000);
            verify(hyprland.dispatches[5].indexOf("value = 'unset', window = 'address:0xfed789'") >= 0);
        }
    }
}
