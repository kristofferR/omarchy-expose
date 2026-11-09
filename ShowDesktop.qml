import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "DesktopModel.js" as DesktopModel
import "WindowModel.js" as WindowModel

// Show Desktop, as the macOS Desktop hot corner does it: a temporary peek.
// Windows on the workspaces in view are minimized to the dock, and the peek
// ends by itself the moment the user does anything that needs a window.
//
//   idle       nothing is moved aside.
//   hiding     Omarchy is minimizing the candidates.
//   shown      the desktop is in view; `entries` are the windows moved aside.
//   restoring  the windows are on their way back.
//
//   idle      --show/toggle-->           hiding   (intent saved first)
//   hiding    --minimizer done, or hidingTimeoutMs-->  verify what really left:
//               >=1 window minimized  -> shown  (entries = those windows)
//               none                  -> idle   (tiled workspace: say why once)
//   shown     --toggle-->                restoring, refocusing the window that
//                                        was active, if its workspace is in view
//   shown     --a window is focused-->   restoring  (opened, picked in Exposé
//                                        or the dock, or clicked)
//   shown     --workspaces in view change--> restoring (each to its own)
//   restoring --settled-->               idle
//   any       --shell restart-->         the saved record brings back every
//                                        window that is still minimized
//
// The end conditions are checked twice: on every focus and workspace event,
// and once more, level-triggered, when `shown` settles. A workspace switch
// that happened while windows were still being minimized therefore ends the
// peek too, instead of leaving it shown for a workspace that is out of view.
// Focus changes before then are mostly minimizing handing focus around, which
// only ever lands on windows that were not minimized when the peek began. A
// window that takes focus in that time without being one of them, opened
// fresh or brought back from the dock, is remembered and ends the peek at
// settle.
// One transition runs at a time. While hiding, a hide or toggle is kept and
// brings the windows back as soon as they are minimized; while restoring,
// show/toggle are ignored.
//
// Only recorded windows that are still minimized ever move, so a window the
// user minimized themselves, or one opened during the peek, is never touched.
// Omarchy minimizes on floating workspaces only, as its dock restores there;
// on tiled ones nothing moves, so a tiled layout is never reshuffled.
Item {
    id: root

    property string phase: "idle"
    property var entries: []
    // Workspaces in view when the desktop was shown; leaving them ends it.
    property var scope: []
    property string focusAddress: ""
    // The active window once the desktop settled; only a change counts.
    property var focusBaseline: null
    property bool settled: false
    // Windows minimizing can hand focus to: those shown and not minimized
    // when the peek began, by address. And whether any other window took focus before the
    // peek settled.
    property var knownAddresses: ({})
    property bool openedWhileSettling: false
    // A hide asked for while hiding, and whether it refocuses.
    property bool restoreQueued: false
    property bool restoreQueuedRefocus: false
    property bool tiledNoticeShown: false
    // A minimize that never returns must not wedge Show Desktop.
    readonly property int hidingTimeoutMs: 5000

    readonly property bool shown: root.phase === "shown"
    readonly property var toplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
    readonly property string recordPath: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
        var session = String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "default").replace(/[^A-Za-z0-9_-]/g, "");
        return runtime + "/expose-show-desktop-" + session + ".json";
    }

    function visibleWorkspaces() {
        return DesktopModel.visibleWorkspaceIds(Hyprland.monitors ? Hyprland.monitors.values : []);
    }

    function toggle() {
        if (root.phase === "idle")
            root.show();
        else if (root.phase === "shown" || root.phase === "hiding")
            root.restore(true);
    }

    // Idempotent: showing an already shown desktop keeps it.
    function show() {
        if (root.phase !== "idle")
            return;
        var visible = root.visibleWorkspaces();
        var plan = DesktopModel.candidates(root.toplevels, visible);
        if (!plan.length)
            return;
        root.phase = "hiding";
        root.entries = plan;
        root.scope = visible;
        root.focusAddress = WindowModel.addressFor(Hyprland.activeToplevel);
        var known = {};
        root.toplevels.forEach(function (top) {
            // A window still mapping is not one yet; it may be the user's.
            if (WindowModel.isEligible(top) && !WindowModel.isMinimized(top))
                known[WindowModel.addressFor(top)] = true;
        });
        root.knownAddresses = known;
        root.openedWhileSettling = false;
        root.saveRecord();
        minimizer.command = ["bash", "-c", "for address; do omarchy-hyprland-window-minimize \"$address\"; done",
            "expose-show-desktop"].concat(DesktopModel.addresses(plan));
        minimizer.running = true;
        hidingTimeout.restart();
    }

    function finishHiding() {
        if (root.phase !== "hiding")
            return;
        hidingTimeout.stop();
        var hidden = DesktopModel.stillMinimized(root.entries, root.toplevels);
        if (!hidden.length) {
            if (!root.tiledNoticeShown) {
                root.tiledNoticeShown = true;
                Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Exposé",
                    "Show Desktop needs a floating workspace",
                    "Windows are moved aside by minimizing them to the dock, which Omarchy does on floating workspaces."]);
            }
            root.reset();
            return;
        }
        root.entries = hidden;
        root.phase = "shown";
        root.saveRecord();
        if (root.restoreQueued) {
            root.restore(root.restoreQueuedRefocus);
            return;
        }
        settle.restart();
    }

    function restore(refocus) {
        if (root.phase === "hiding") {
            root.restoreQueued = true;
            root.restoreQueuedRefocus = refocus;
            return;
        }
        if (root.phase !== "shown")
            return;
        var pending = DesktopModel.stillMinimized(root.entries, root.toplevels);
        if (!pending.length) {
            root.reset();
            return;
        }
        root.phase = "restoring";
        root.entries = pending;
        var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        var lua = DesktopModel.restoreLua(pending, workspaces.map(function (workspace) { return Number(workspace.id); }));
        var focus = refocus && root.focusAddress ? root.entryFor(root.focusAddress, pending) : null;
        if (focus && root.visibleWorkspaces().indexOf(focus.workspaceId) !== -1)
            lua += "; hl.dispatch(hl.dsp.focus({ window = 'address:" + focus.address + "' }))";
        Hyprland.dispatch("(function() " + lua + " end)");
        restoreSettle.restart();
    }

    function finishRestoring() {
        Hyprland.dispatch("(function() " + DesktopModel.animationLua(root.entries) + " end)");
        var stuck = DesktopModel.stillMinimized(root.entries, root.toplevels);
        if (stuck.length)
            Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Exposé",
                "Some windows stayed minimized", "Bring them back from the dock or from Exposé."]);
        root.reset();
    }

    function entryFor(address, list) {
        for (var index = 0; index < list.length; index++)
            if (list[index].address === address)
                return list[index];
        return null;
    }

    // The end conditions that can be read off the current state rather than
    // waiting for an event: the workspaces in view are no longer the ones the
    // desktop was shown on.
    function endedWhileSettling() {
        return root.openedWhileSettling || !DesktopModel.sameWorkspaces(root.scope, root.visibleWorkspaces());
    }

    function reset() {
        settle.stop();
        hidingTimeout.stop();
        verifyHidden.stop();
        restoreSettle.stop();
        root.phase = "idle";
        root.entries = [];
        root.scope = [];
        root.focusAddress = "";
        root.focusBaseline = null;
        root.settled = false;
        root.knownAddresses = ({});
        root.openedWhileSettling = false;
        root.restoreQueued = false;
        root.restoreQueuedRefocus = false;
        root.saveRecord();
    }

    function saveRecord() {
        record.setText(root.entries.length ? JSON.stringify({ entries: root.entries }) + "\n" : "");
    }

    Process {
        id: minimizer
        onExited: {
            if (root.phase !== "hiding")
                return;
            Hyprland.refreshToplevels();
            verifyHidden.restart();
        }
    }

    // Stops a hung minimize and keeps whatever did get minimized.
    Timer {
        id: hidingTimeout
        interval: root.hidingTimeoutMs
        onTriggered: {
            if (root.phase !== "hiding")
                return;
            minimizer.running = false;
            Hyprland.refreshToplevels();
            verifyHidden.restart();
        }
    }

    // Hyprland reports the moves as events; give the last one a moment.
    Timer {
        id: verifyHidden
        interval: 250
        onTriggered: root.finishHiding()
    }

    // Minimizing hands focus around; only focus changes after this count.
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            root.focusBaseline = Hyprland.activeToplevel;
            root.settled = true;
            if (root.shown && root.endedWhileSettling())
                root.restore(false);
        }
    }

    Timer {
        id: restoreSettle
        interval: 400
        onTriggered: root.finishRestoring()
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            var top = Hyprland.activeToplevel;
            if (root.shown && root.settled && top && top !== root.focusBaseline)
                root.restore(false);
            else if (top && !root.settled && (root.phase === "hiding" || root.shown)
                    && !root.knownAddresses[WindowModel.addressFor(top)])
                root.openedWhileSettling = true;
        }
        function onFocusedWorkspaceChanged() {
            if (root.shown && root.settled && root.endedWhileSettling())
                root.restore(false);
        }
    }

    // Survives a shell restart. A record found at startup means a peek was
    // cut short: its windows come back once Hyprland has listed them.
    FileView {
        id: record
        path: root.recordPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            var saved = DesktopModel.parseRecord(text());
            if (saved.length && root.phase === "idle") {
                recovery.entries = saved;
                recovery.restart();
            }
        }
    }

    // Recovery runs only from idle. If the user shows the desktop first, the
    // new record replaces the old one and those windows simply stay in the
    // dock as ordinary minimized windows.
    Timer {
        id: recovery
        property var entries: []
        interval: 1500
        onTriggered: {
            if (root.phase !== "idle")
                return;
            root.entries = recovery.entries;
            root.phase = "shown";
            root.restore(false);
        }
    }

    Component.onCompleted: Hyprland.refreshToplevels()
}
