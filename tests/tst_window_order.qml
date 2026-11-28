import QtQuick
import QtTest
import "../WindowOrder.js" as WindowOrder

TestCase {
    name: "WindowOrder"

    readonly property var leftDisplay: ({ x: 0, y: 0 })
    readonly property var rightDisplay: ({ x: 2560, y: 0 })

    function window(name, monitor, workspaceId, x, y, workspaceName) {
        return {
            name: name,
            monitor: monitor,
            workspace: { id: workspaceId, name: workspaceName || String(workspaceId) },
            lastIpcObject: { at: [x, y] }
        };
    }

    function names(list) {
        return list.map(function (top) { return top.name; }).join(" ");
    }

    function test_desktopOrderFollowsDisplaysWorkspacesAndPositions() {
        var list = [
            window("right-display", rightDisplay, 11, 0, 0),
            window("ws2", leftDisplay, 2, 0, 0),
            window("ws1-right", leftDisplay, 1, 1300, 0),
            window("ws1-lower", leftDisplay, 1, 0, 700),
            window("ws1-upper", leftDisplay, 1, 0, 0)
        ];
        compare(names(WindowOrder.desktopOrder(list)), "ws1-upper ws1-lower ws1-right ws2 right-display");
    }

    function test_specialAndMinimizedWindowsComeLast() {
        var list = [
            window("minimized", leftDisplay, -99, 0, 0, "special:minimized"),
            window("scratchpad", leftDisplay, -98, 0, 0, "special:scratchpad"),
            window("normal", rightDisplay, 11, 500, 0)
        ];
        compare(names(WindowOrder.desktopOrder(list)), "normal scratchpad minimized");
    }

    function test_tiesKeepTheirGivenOrder() {
        var list = [window("first", leftDisplay, 1, 0, 0), window("second", leftDisplay, 1, 0, 0)];
        compare(names(WindowOrder.desktopOrder(list)), "first second");
    }

    function test_arrangeKeepsTheDraggedOrderAndAppendsNewWindows() {
        var a = window("a", leftDisplay, 1, 0, 0);
        var b = window("b", leftDisplay, 1, 100, 0);
        var c = window("c", leftDisplay, 1, 200, 0);
        var newer = window("newer", leftDisplay, 1, 50, 0);
        var closed = window("closed", leftDisplay, 1, 300, 0);
        compare(names(WindowOrder.arrange([a, b, c, newer], [c, closed, a, b])), "c a b newer");
        compare(names(WindowOrder.arrange([c, b, a], [])), "a b c");
    }

    function test_movedTakesTheTargetsPlace() {
        var list = ["a", "b", "c", "d"];
        compare(WindowOrder.moved(list, "a", "c").join(""), "bcad");
        compare(WindowOrder.moved(list, "d", "b").join(""), "adbc");
        compare(WindowOrder.moved(list, "b", "b"), list);
        compare(WindowOrder.moved(list, "x", "b"), list);
    }
}
