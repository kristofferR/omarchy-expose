import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import qs.Ui as Ui // qmllint disable import
import "DisplayModel.js" as DisplayModel
import "GridLayout.js" as GridLayout
import "IconResolver.js" as IconResolver
import "WindowModel.js" as WindowModel
import "WorkspaceModel.js" as WorkspaceModel
import "ScreenLayout.js" as ScreenLayout
import "SettingsSchema.js" as SettingsSchema
import "HotCorners.js" as HotCorners

Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property alias windowBorders: compositorBorders
    WindowBorders { id: compositorBorders }
    ShowDesktop { id: showDesktop }
    readonly property string pluginId: String((root.manifest && root.manifest.id) || "expose.window-overview")
    readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir)
        || (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId))
    readonly property var pluginEntry: pluginSettings.entry

    PluginSettings {
        id: pluginSettings
        pluginId: root.pluginId
        shell: root.shell
        onReloadRequested: Qt.callLater(pluginSettingsFile.reload)
    }

    UpdateNotice {
        pluginDir: root.pluginDir
        entry: pluginSettings.diskEntry
        settingsReady: pluginSettings.ready
    }

    FileView {
        id: pluginSettingsFile
        // Match the host's userConfigPath, which does not use XDG_CONFIG_HOME.
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onLoaded: pluginSettings.load(text())
        onLoadFailed: function(error) {
            pluginSettings.loadFailed();
            console.warn(root.pluginId + ": could not load shell.json: " + error);
        }
        onFileChanged: Qt.callLater(pluginSettingsFile.reload)
    }
    readonly property string previewPlacement: SettingsSchema.read(root.pluginEntry, "previewPlacement")
    readonly property string windowFooterStyle: SettingsSchema.read(root.pluginEntry, "windowFooterStyle")
    readonly property string selectionStyle: SettingsSchema.read(root.pluginEntry, "selectionStyle")
    readonly property var animationStyles: SettingsSchema.values("animationStyle")
    readonly property string animationStyle: SettingsSchema.read(root.pluginEntry, "animationStyle")
    readonly property var defaultAnimationDurations: ({ original: 190, fade: 400, zoom: 320, slide: 320 })
    readonly property var animationTimings: {
        var configuredTimings = root.pluginEntry && root.pluginEntry.animationTimings
            && typeof root.pluginEntry.animationTimings === "object"
            ? root.pluginEntry.animationTimings
            : null;
        var configuredDurations = root.pluginEntry && root.pluginEntry.animationDurations
            && typeof root.pluginEntry.animationDurations === "object"
            ? root.pluginEntry.animationDurations
            : null;
        var configured = configuredTimings || configuredDurations || {};
        var legacyRaw = root.pluginEntry ? root.pluginEntry.animationDuration : undefined;
        var legacy = legacyRaw === null || legacyRaw === undefined ? NaN : Number(legacyRaw);
        function timingFor(style) {
            var raw = configured[style];
            var isObject = raw !== null && raw !== undefined && typeof raw === "object";
            var scalar = raw === null || raw === undefined ? NaN : Number(raw);
            var separate = isObject && raw.separate === true;
            var inValue = isObject ? Number(raw["in"]) : scalar;
            var outValue = isObject ? Number(raw["out"]) : scalar;
            if (!isFinite(inValue) && isFinite(legacy))
                inValue = legacy;
            if (!isFinite(outValue) && isFinite(legacy))
                outValue = legacy;
            if (!isFinite(inValue))
                inValue = root.defaultAnimationDurations[style];
            if (!isFinite(outValue))
                outValue = inValue;
            return {
                "in": root.clampAnimationDuration(inValue),
                "out": root.clampAnimationDuration(outValue),
                separate: separate
            };
        }
        return {
            original: timingFor("original"),
            fade: timingFor("fade"),
            zoom: timingFor("zoom"),
            slide: timingFor("slide")
        };
    }
    readonly property var slideVectors: ({
        left: {x: -1, y: 0},
        right: {x: 1, y: 0},
        up: {x: 0, y: -1},
        down: {x: 0, y: 1}
    })
    readonly property var slideDirections: Object.keys(root.slideVectors)
    // {"in", "out"}. A bare string in config is shorthand for both. The slide
    // timing's `separate` flag decides whether "out" is honored or mirrors "in".
    readonly property var slideDirection: {
        var raw = root.pluginEntry ? root.pluginEntry.slideDirection : undefined;
        var isObject = raw !== null && raw !== undefined && typeof raw === "object";
        var inValue = root.normalizeSlideDirection(isObject ? raw["in"] : raw);
        var outValue = root.animationTimingFor("slide").separate
            ? root.normalizeSlideDirection(isObject ? raw["out"] : raw)
            : inValue;
        return {"in": inValue, "out": outValue};
    }
    // Latched by animateMotionTo when a transition starts from rest, so reversing
    // mid-flight slides back out the side it came from instead of popping across.
    property string slideMotionDirection: ""
    readonly property var slideVector: root.slideVectors[root.slideMotionDirection] || root.slideVectors[root.slideDirection["in"]]
    readonly property real slideOffsetFraction: root.animationStyle === "slide"
        ? 0.11 * (1 - root.motionProgress)
        : 0
    readonly property real windowFooterHeight: root.windowFooterStyle === "overlay" ? 0 : Style.space(40)
    readonly property string backgroundMode: SettingsSchema.read(root.pluginEntry, "backgroundMode")
    readonly property int backgroundBlur: SettingsSchema.read(root.pluginEntry, "backgroundBlur")
    readonly property int backgroundDim: SettingsSchema.read(root.pluginEntry, "backgroundDim")
    // Off until settings load, so a saved "off" never flashes the corner on.
    readonly property bool hotCornerEnabled: pluginSettings.ready && SettingsSchema.read(root.pluginEntry, "hotCornerEnabled")
    // What each corner does: { "top-left": "all-windows", ... }. See HotCorners.js.
    readonly property var hotCornerActions: HotCorners.read(root.pluginEntry)
    readonly property bool hotCornerAllDisplays: SettingsSchema.read(root.pluginEntry, "hotCornerAllDisplays")
    readonly property bool hotCornerIgnoreFullscreen: SettingsSchema.read(root.pluginEntry, "hotCornerIgnoreFullscreen")
    // One { position, action, screen } per corner that does something, on each
    // display that answers it: the outermost one on that side, or every display.
    readonly property var hotCornerSurfaces: {
        if (!root.hotCornerEnabled)
            return [];
        var screens = Quickshell.screens;
        var monitors = Hyprland.monitors ? Hyprland.monitors.values : [];
        var result = [];
        HotCorners.active(root.hotCornerActions).forEach(function (corner) {
            ScreenLayout.hotCornerScreens(screens, monitors, corner.position, root.hotCornerAllDisplays)
                .forEach(function (screen) {
                    result.push({ position: corner.position, action: corner.action, screen: screen });
                });
        });
        return result;
    }
    onHotCornerSurfacesChanged: root.scheduleHotCornerRearm()
    // How long the pointer has to rest in the corner before it fires. Zero
    // keeps the original instant trip; longer dwells stop stray flings.
    readonly property int hotCornerDelay: SettingsSchema.read(root.pluginEntry, "hotCornerDelay")
    // Which windows the overview starts with. "all" keeps every workspace, as
    // before; "current" opens on the active workspace and leaves Tab to widen.
    readonly property string initialWorkspaceScope: SettingsSchema.read(root.pluginEntry, "initialWorkspaceScope")
    // How a workspace is named on the cards and in the scope indicator. Plugins
    // such as per-monitor-workspaces name a workspace "<monitor description>:<slot>",
    // which is far wider than a card footer; "slot" prints the trailing slot only.
    readonly property string workspaceLabelStyle: SettingsSchema.read(root.pluginEntry, "workspaceLabelStyle")
    // Reach farther along both screen edges than into the desktop. Fast flings
    // are easier to catch without stealing a large square from the bar below.
    readonly property int hotCornerReach: Style.space(48)
    readonly property int hotCornerDepth: Style.space(6)
    readonly property bool moveCursorToWindow: SettingsSchema.read(root.pluginEntry, "moveCursorToWindow")
    readonly property string multiMonitorMode: SettingsSchema.read(root.pluginEntry, "multiMonitorMode")
    readonly property bool showFooter: SettingsSchema.read(root.pluginEntry, "showFooter")
    readonly property bool closeButton: SettingsSchema.read(root.pluginEntry, "closeButton")
    readonly property string closeButtonSide: SettingsSchema.read(root.pluginEntry, "closeButtonSide")
    readonly property bool workspaceStrip: SettingsSchema.read(root.pluginEntry, "workspaceStrip")
    readonly property bool workspaceDrag: SettingsSchema.read(root.pluginEntry, "workspaceDrag")
    readonly property bool dragToWorkspaces: root.workspaceStrip && root.workspaceDrag
    property bool opened: false
    property bool surfaceMounted: false
    property bool hotCornerArmed: true
    property string filterText: ""
    // "all-windows", or "app-windows" for the windows of one app, named by
    // appKey (its app id in lower case), as macOS Application Windows does.
    // Set by every open() and by switchOverviewMode() only, always together
    // through applyOverviewMode(), so a mode is never paired with another
    // mode's key. They keep their last values once closed and mean nothing
    // then; anything reporting them checks `opened` first.
    property string overviewMode: "all-windows"
    property string appKey: ""
    // A deferred intent, set when Desktop fires with Exposé open: the desktop
    // is shown once the overview has gone, so the two never fight over focus.
    // Consumed by finishDismiss(); cleared by open(), so reopening before the
    // overview is gone cancels it and it can never fire on a later close.
    property bool desktopAfterDismiss: false
    property string workspaceScope: "all"
    // Selection state holds windows, not positions in filteredToplevels, so it
    // survives the list being rebuilt by filtering, scope, or windows closing.
    property var selectedToplevel: null
    property var hoveredToplevel: null
    property var previewToplevel: null
    property var previewExitToplevel: null
    // The window the overview was opened from. Hyprland's active window stops
    // matching any card once the overlay holds keyboard focus.
    property var originToplevel: null
    // Window to focus, or workspace to show ({ id, screen }), once the overlay
    // releases the keyboard.
    property var pendingActivation: null
    property var pendingWorkspace: null
    // The window whose card is being dragged toward the workspace strip.
    property var draggedToplevel: null
    readonly property var allWorkspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []
    // Workspaces added with + that have no window yet; see WorkspaceModel.placeholder.
    property var addedWorkspaces: []
    // Omarchy's record of which block of ten workspace ids each monitor owns.
    property string workspaceBlocks: ""
    property bool previewSlowMotion: false
    property bool previewNavigationSlowMotion: false
    property bool openingPending: false
    property bool settingsOpen: false
    property int settingsCategoryIndex: 0
    property bool footerHideConfirmationOpen: false
    property bool footerHideAcknowledged: false
    property string animationDurationPreviewStyle: ""
    property real animationInDurationPreview: -1
    property real animationOutDurationPreview: -1
    property real backgroundBlurPreview: -1
    property real backgroundDimPreview: -1
    property real hotCornerDelayPreview: -1
    readonly property real effectiveBackgroundBlur: root.backgroundBlurPreview >= 0 ? root.backgroundBlurPreview : root.backgroundBlur
    readonly property real desktopBackgroundBlur: root.backgroundMode === "desktop" ? root.effectiveBackgroundBlur : 0
    readonly property real effectiveBackgroundDim: root.backgroundDimPreview >= 0 ? root.backgroundDimPreview : root.backgroundDim
    readonly property int effectiveHotCornerDelay: root.hotCornerDelayPreview >= 0 ? Math.round(root.hotCornerDelayPreview) : root.hotCornerDelay
    readonly property int previewAnimationDuration: Style.duration(root.previewSlowMotion || root.previewNavigationSlowMotion ? 4000 : 190)
    readonly property int previewFadeDuration: Style.duration(root.previewSlowMotion || root.previewNavigationSlowMotion ? 4000 : 130)
    readonly property int previewAnimationEasing: root.previewNavigationSlowMotion ? Easing.InOutCubic : Easing.OutQuart
    property bool backgroundBlurPrimed: false
    property bool backgroundBlurFailed: false
    property bool dismissNotifyShell: false
    // 0 idle, 1 restoring the desktop blur while the surface is transparent.
    property int backgroundBlurReleasePhase: 0
    property real motionProgress: 0
    property real motionTarget: 0
    // Cards bind to this instead of motionProgress so the animation only
    // notifies them twice, not once per frame.
    readonly property bool motionSettled: root.motionProgress >= 0.999
    property int lastRequestedBlur: -1
    property var iconCache: ({})
    property int modelRevision: 0
    property var sessionToplevels: []
    property var sessionAspectRatios: []
    readonly property var allToplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
    readonly property string focusedMonitorName: Hyprland.focusedMonitor
        ? String(Hyprland.focusedMonitor.name || "")
        : ""
    property string overviewScreenName: ""
    property bool overviewScreenPinned: false
    readonly property var effectiveOverviewScreen: {
        var screens = Quickshell.screens;
        var wanted = String(root.overviewScreenName || "");
        var fallback = null;
        for (var index = 0; index < screens.length; index++) {
            var screen = screens[index];
            if (!screen)
                continue;
            if (!fallback)
                fallback = screen;
            if (wanted && String(screen.name || "") === wanted)
                return screen;
        }
        return fallback;
    }
    readonly property string effectiveOverviewScreenName: root.effectiveOverviewScreen
        ? String(root.effectiveOverviewScreen.name || "")
        : ""
    readonly property string keyboardScreenName: {
        if (root.effectiveOverviewScreenName && (root.surfaceMounted || root.overviewScreenName))
            return root.effectiveOverviewScreenName;
        if (root.overviewScreenName)
            return root.overviewScreenName;
        if (root.focusedMonitorName)
            return root.focusedMonitorName;
        var active = Hyprland.activeToplevel;
        if (active && active.monitor)
            return String(active.monitor.name || "");
        return Quickshell.screens.length ? String(Quickshell.screens[0].name || "") : "";
    }
    // Each display gets a grid in all-monitors mode. Per-display filtering
    // keeps each screencopy capture on exactly one surface.
    readonly property var mountedScreens: {
        return DisplayModel.mountedScreens(Quickshell.screens, root.effectiveOverviewScreen,
            root.multiMonitorMode, root.surfaceMounted);
    }
    readonly property var backdropScreens: {
        return DisplayModel.backdropScreens(Quickshell.screens, root.effectiveOverviewScreen,
            root.multiMonitorMode, root.surfaceMounted);
    }
    readonly property var overviewKeyboardTargets: {
        return DisplayModel.keyboardTargets(surfaceInstances.instances);
    }
    // Every listed window, which the selection is one of. Each display's grid
    // in all-monitors mode lists only its own windows, so a window is never
    // listed twice.
    readonly property var filteredToplevels: {
        var revision = root.modelRevision;
        if (root.multiMonitorMode !== "all-monitors")
            return root.toplevelsForScreen(root.keyboardScreenName);
        var result = [];
        for (var index = 0; index < root.mountedScreens.length; index++)
            result = result.concat(root.toplevelsForScreen(String(root.mountedScreens[index].name || "")));
        return result;
    }
    // What Enter opens.
    readonly property var selection: WindowModel.selectionFor(root.filteredToplevels, root.selectedToplevel, root.originToplevel)

    onMultiMonitorModeChanged: {
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
        root.selectedToplevel = root.originToplevel;
    }

    onDesktopBackgroundBlurChanged: {
        if (!root.surfaceMounted)
            return;
        if (!backgroundBlurSession.running && root.desktopBackgroundBlur > 0 && !root.backgroundBlurFailed) {
            root.backgroundBlurPrimed = false;
            backgroundBlurSession.running = true;
        } else {
            root.scheduleBackgroundBlurUpdate();
        }
    }

    function open(payload) {
        // Taken before the overlay takes keyboard focus. Right after a shell
        // restart the active window is not known yet; focus history may be.
        root.originToplevel = Hyprland.activeToplevel || WindowModel.mostRecent(root.allToplevels);
        // Reopening before the overlay is gone cancels the activation.
        root.pendingActivation = null;
        root.pendingWorkspace = null;
        root.draggedToplevel = null;
        root.addedWorkspaces = [];
        compositorBorders.refresh();
        var blurRestoreInFlight = root.backgroundBlurReleasePhase === 1 && backgroundBlurSession.running;
        if (!blurRestoreInFlight)
            root.backgroundBlurReleasePhase = 0;
        root.closeSettings();
        root.filterText = "";
        root.desktopAfterDismiss = false;
        root.applyOverviewMode(root.payloadMode(payload));
        root.workspaceScope = root.initialWorkspaceScope;
        root.dismissNotifyShell = false;
        if (root.surfaceMounted) {
            if (blurRestoreInFlight) {
                root.openingPending = true;
                return;
            }
            root.opened = true;
            root.animateMotionTo(1);
            root.refreshHyprlandState();
            Qt.callLater(root.focusKeyboardSurface);
            return;
        }
        if (root.openingPending)
            return;
        if (!root.overviewScreenPinned)
            root.overviewScreenName = root.keyboardScreenName;
        overviewMotionAnimation.stop();
        root.motionTarget = 0;
        root.motionProgress = 0;
        root.openingPending = true;
        root.refreshHyprlandState();
        root.resetSessionToplevels();
        root.selectedToplevel = root.originToplevel;
        root.hoveredToplevel = null;
        root.clearPreview();
        root.backgroundBlurPrimed = false;
        root.backgroundBlurFailed = false;
        if (root.desktopBackgroundBlur > 0) {
            if (!blurRestoreInFlight)
                backgroundBlurSession.running = true;
        } else {
            root.prepareOpenSurface();
        }
    }

    function close() {
        root.startDismiss(false);
    }

    // Openings without desktop blur (Wallpaper mode, or blur 0) skip the blur
    // session, so its layer rule is installed up front as well.
    function installLayerRule() {
        Quickshell.execDetached([root.pluginDir + "/background-blur-session", "--layer-rule"]);
    }
    Component.onCompleted: root.installLayerRule()

    function startDismiss(notifyShell) {
        root.openingPending = false;
        root.closeSettings();
        root.hoveredToplevel = null;
        root.clearPreview();
        root.opened = false;
        root.dismissNotifyShell = root.dismissNotifyShell || notifyShell;
        if (root.backgroundBlurReleasePhase > 0)
            return;
        if (root.surfaceMounted) {
            root.animateMotionTo(0);
            return;
        }
        overviewMotionAnimation.stop();
        root.motionTarget = 0;
        root.motionProgress = 0;
        root.backgroundBlurPrimed = false;
        root.backgroundBlurReleasePhase = 0;
        backgroundBlurSession.running = false;
        root.clearOverviewScreen();
        root.finishDismiss();
    }

    function dismiss() {
        root.startDismiss(true);
    }

    function toggle() {
        root.showOverview("all-windows", "");
    }

    // { "mode": "app-windows" } opens on the focused app's windows; anything
    // else, including no payload, opens on every window.
    function payloadMode(payload) {
        try {
            var options = typeof payload === "string" ? JSON.parse(payload || "{}") : (payload || {});
            return options && options.mode === "app-windows" ? "app-windows" : "all-windows";
        } catch (error) {
            return "all-windows";
        }
    }

    // App windows needs an app: with no window to take it from, it shows all.
    function applyOverviewMode(mode) {
        var key = mode === "app-windows" ? WindowModel.appKeyFor(root.originToplevel) : "";
        root.overviewMode = key ? "app-windows" : "all-windows";
        root.appKey = key;
    }

    // A corner or key for a mode: opens Exposé in that mode, closes it when it
    // is already showing that mode, and otherwise switches in place, as macOS
    // moves between Mission Control and Application Windows.
    function showOverview(mode, screenName) {
        if (root.opened || root.openingPending) {
            var wanted = mode === "app-windows" && WindowModel.appKeyFor(root.originToplevel)
                ? "app-windows" : "all-windows";
            if (wanted === root.overviewMode)
                root.dismiss();
            else
                root.switchOverviewMode(wanted);
            return;
        }
        var name = String(screenName || "");
        if (name) {
            root.overviewScreenPinned = true;
            root.overviewScreenName = name;
        }
        root.open(JSON.stringify({ mode: mode }));
    }

    function switchOverviewMode(mode) {
        root.applyOverviewMode(mode);
        root.filterText = "";
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
        root.selectedToplevel = root.originToplevel;
    }

    // The Desktop corner or key. With Exposé open it closes Exposé and shows
    // the desktop, as the macOS Desktop corner does from Mission Control.
    function toggleDesktop() {
        // A Desktop waiting for Exposé to close counts as shown, so a second
        // toggle cancels it.
        if (root.desktopAfterDismiss) {
            root.desktopAfterDismiss = false;
            return;
        }
        if (root.opened || root.openingPending) {
            root.desktopAfterDismiss = true;
            root.dismiss();
            return;
        }
        showDesktop.toggle();
    }

    function runCornerAction(action, screenName) {
        if (action === "desktop")
            root.toggleDesktop();
        else if (action === "all-windows" || action === "app-windows")
            root.showOverview(action, screenName);
    }

    function requestedBackgroundBlur() {
        return Math.max(0, Math.round(root.desktopBackgroundBlur));
    }

    function writeBackgroundBlur(size) {
        backgroundBlurSession.write(String(size) + "\n");
    }

    function scheduleBackgroundBlurUpdate() {
        if (backgroundBlurSession.running && !backgroundBlurUpdate.running)
            backgroundBlurUpdate.start();
    }

    function prepareOpenSurface() {
        if (!root.openingPending)
            return;
        if (root.desktopBackgroundBlur > 0 && !root.backgroundBlurFailed) {
            if (!backgroundBlurSession.running) {
                root.backgroundBlurPrimed = false;
                backgroundBlurSession.running = true;
                return;
            }
            if (!root.backgroundBlurPrimed)
                return;
        }
        if (!root.overviewScreenPinned)
            root.overviewScreenName = root.focusedMonitorName || root.keyboardScreenName;
        root.surfaceMounted = true;
        Qt.callLater(function () {
            if (!root.surfaceMounted || !root.openingPending)
                return;
            root.openingPending = false;
            root.opened = true;
            root.animateMotionTo(1);
            root.focusKeyboardSurface();
        });
    }

    function animateMotionTo(target) {
        var next = target >= 0.5 ? 1 : 0;
        overviewMotionAnimation.stop();
        root.motionTarget = next;
        var distance = Math.abs(next - root.motionProgress);
        // Omarchy's no-animations mode (`omarchy toggle animations`) skips the
        // transition and lands on the final frame.
        if (distance < 0.001 || Style.reduceMotion) {
            root.motionProgress = next;
            root.completeMotion();
            return;
        }
        if (root.motionProgress <= 0.001 || root.motionProgress >= 0.999)
            root.slideMotionDirection = String(root.slideDirection[next > 0 ? "in" : "out"]);
        overviewMotionAnimation.from = root.motionProgress;
        overviewMotionAnimation.to = next;
        var configuredDuration = next > root.motionProgress
            ? root.animationInDurationFor(root.animationStyle)
            : root.animationOutDurationFor(root.animationStyle);
        overviewMotionAnimation.duration = Math.max(1, Math.round(configuredDuration * distance));
        overviewMotionAnimation.easing.type = root.animationStyle === "original"
            ? Easing.OutQuart
            : (next > root.motionProgress ? Easing.OutCubic : Easing.InCubic);
        overviewMotionAnimation.start();
    }

    function previewAnimation() {
        if (!root.surfaceMounted)
            return;
        overviewMotionAnimation.stop();
        root.motionTarget = 1;
        root.motionProgress = 0;
        root.animateMotionTo(1);
    }

    function completeMotion() {
        root.motionProgress = root.motionTarget;
        if (root.motionTarget > 0) {
            root.scheduleBackgroundBlurUpdate();
            Qt.callLater(root.focusKeyboardSurface);
            return;
        }
        backgroundBlurUpdate.stop();
        if (backgroundBlurSession.running) {
            root.backgroundBlurReleasePhase = 1;
            root.backgroundBlurPrimed = false;
            backgroundBlurSession.write("close\n");
            return;
        }
        root.releaseBlurredSurface();
    }

    function releaseBlurredSurface() {
        root.surfaceMounted = false;
        root.backgroundBlurPrimed = false;
        root.clearOverviewScreen();
        root.backgroundBlurReleasePhase = 0;
        root.finishDismiss();
        root.scheduleHotCornerRearm();
    }

    function finishDismiss() {
        if (root.pendingActivation || root.pendingWorkspace)
            root.dispatchPendingActivation();
        if (root.desktopAfterDismiss) {
            root.desktopAfterDismiss = false;
            showDesktop.show();
        }
        var notifyShell = root.dismissNotifyShell;
        root.dismissNotifyShell = false;
        if (notifyShell && root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId);
    }

    function updatePluginSetting(name, value) {
        return pluginSettings.update(name, value);
    }

    // Stores a simple setting from the schema; returns the value it now has.
    function setSetting(name, value) {
        if (name === "hotCornerEnabled")
            return root.setHotCornerEnabled(value);
        if (name === "hotCornerPosition")
            return root.setHotCornerPosition(value);
        var corner = root.cornerForSetting(name);
        if (corner)
            return root.setHotCornerAction(corner, value);
        var next = SettingsSchema.normalize(name, value, root[name]);
        if (next !== root[name])
            root.updatePluginSetting(name, next);
        return next;
    }

    // IPC form of setSetting: rejects unlisted options and non on/off booleans
    // with a message, and answers with the stored value as text.
    function setSettingFromIpc(name, text) {
        var parsed = SettingsSchema.parseIpc(name, text);
        if (parsed.error)
            return parsed.error;
        var next = root.setSetting(name, parsed.value);
        return typeof next === "boolean" ? (next ? "on" : "off") : String(next);
    }

    function clampAnimationDuration(value) {
        var numeric = Number(value);
        if (!isFinite(numeric))
            return 320;
        var clamped = Math.max(100, Math.min(800, numeric));
        return Math.round(clamped / 10) * 10;
    }

    function animationTimingFor(style) {
        var mode = root.animationStyles.indexOf(style) !== -1 ? style : "original";
        return root.animationTimings[mode];
    }

    function animationInDurationFor(style) {
        if (root.animationInDurationPreview >= 0 && root.animationDurationPreviewStyle === style)
            return root.animationInDurationPreview;
        return Number(root.animationTimingFor(style)["in"]);
    }

    function animationOutDurationFor(style) {
        if (root.animationOutDurationPreview >= 0 && root.animationDurationPreviewStyle === style)
            return root.animationOutDurationPreview;
        return Number(root.animationTimingFor(style)["out"]);
    }

    function setAnimationTiming(style, inValue, outValue, separate) {
        var mode = root.animationStyles.indexOf(style) !== -1 ? style : "original";
        var nextIn = root.clampAnimationDuration(inValue);
        var nextOut = root.clampAnimationDuration(outValue);
        var nextSeparate = separate === true;
        if (mode === "slide" && !nextSeparate)
            root.setSlideDirection(root.slideDirection["in"]);
        var current = root.animationTimingFor(mode);
        if (nextIn !== Number(current["in"])
                || nextOut !== Number(current["out"])
                || nextSeparate !== (current.separate === true)) {
            var timings = {};
            for (var index = 0; index < root.animationStyles.length; index++) {
                var animationMode = root.animationStyles[index];
                var timing = root.animationTimingFor(animationMode);
                timings[animationMode] = animationMode === mode
                    ? {"in": nextIn, "out": nextOut, separate: nextSeparate}
                    : {"in": Number(timing["in"]), "out": Number(timing["out"]), separate: timing.separate === true};
            }
            root.updatePluginSetting("animationTimings", timings);
        }
        return {"in": nextIn, "out": nextOut, separate: nextSeparate};
    }

    function setAnimationDuration(style, value) {
        var next = root.clampAnimationDuration(value);
        root.setAnimationTiming(style, next, next, false);
        return next;
    }

    function setAnimationDurationIn(style, value) {
        var timing = root.animationTimingFor(style);
        var next = root.clampAnimationDuration(value);
        root.setAnimationTiming(style, next, timing["out"], true);
        return next;
    }

    function setAnimationDurationOut(style, value) {
        var timing = root.animationTimingFor(style);
        var next = root.clampAnimationDuration(value);
        root.setAnimationTiming(style, timing["in"], next, true);
        return next;
    }

    function setAnimationTimingSeparate(style, separate) {
        var timing = root.animationTimingFor(style);
        return separate
            ? root.setAnimationTiming(style, timing["in"], timing["out"], true)
            : root.setAnimationTiming(style, timing["in"], timing["in"], false);
    }

    function isSlideDirection(value) {
        var direction = String(value === null || value === undefined ? "" : value);
        return root.slideDirections.indexOf(direction) !== -1;
    }

    function normalizeSlideDirection(value) {
        var direction = String(value === null || value === undefined ? "" : value);
        return root.isSlideDirection(direction) ? direction : "left";
    }

    function setSlideDirections(inValue, outValue) {
        var nextIn = root.normalizeSlideDirection(inValue);
        var nextOut = root.normalizeSlideDirection(outValue);
        var current = root.slideDirection;
        if (nextIn !== String(current["in"]) || nextOut !== String(current["out"]))
            root.updatePluginSetting("slideDirection", {"in": nextIn, "out": nextOut});
    }

    function setSlideDirection(value) {
        var next = root.normalizeSlideDirection(value);
        root.setSlideDirections(next, next);
        return next;
    }

    // Splitting a side also splits slide timing: one toggle governs both.
    function setSlideDirectionIn(value) {
        var next = root.normalizeSlideDirection(value);
        root.setAnimationTimingSeparate("slide", true);
        root.setSlideDirections(next, root.slideDirection["out"]);
        return next;
    }

    function setSlideDirectionOut(value) {
        var next = root.normalizeSlideDirection(value);
        root.setAnimationTimingSeparate("slide", true);
        root.setSlideDirections(root.slideDirection["in"], next);
        return next;
    }

    function clearAnimationTimingPreview() {
        root.animationDurationPreviewStyle = "";
        root.animationInDurationPreview = -1;
        root.animationOutDurationPreview = -1;
    }

    function openSettings() {
        if (!root.surfaceMounted)
            root.open("{}");
        root.closeFooterHideConfirmation();
        root.clearAnimationTimingPreview();
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        root.hotCornerDelayPreview = -1;
        root.settingsCategoryIndex = 0;
        root.settingsOpen = true;
        Qt.callLater(root.focusKeyboardSurface);
    }

    function closeSettings() {
        var restoreKeyboardFocus = root.settingsOpen && root.opened;
        root.closeFooterHideConfirmation();
        root.settingsOpen = false;
        root.clearAnimationTimingPreview();
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        root.hotCornerDelayPreview = -1;
        if (restoreKeyboardFocus)
            Qt.callLater(function () {
                if (root.opened)
                    root.focusKeyboardSurface();
            });
    }

    function clearPreview() {
        previewExitTimer.stop();
        root.previewSlowMotion = false;
        root.previewNavigationSlowMotion = false;
        root.previewToplevel = null;
        root.previewExitToplevel = null;
    }

    function cornerForSetting(name) {
        for (var index = 0; index < HotCorners.positions.length; index++)
            if (HotCorners.keyFor(HotCorners.positions[index]) === name)
                return HotCorners.positions[index];
        return "";
    }

    function storeCornerSettings(settings) {
        for (var key in settings)
            root.updatePluginSetting(key, settings[key]);
    }

    // One corner's action; the other corners keep theirs.
    function setHotCornerAction(position, action) {
        if (!HotCorners.isPosition(position))
            return "";
        var next = HotCorners.isAction(action) ? action : "off";
        root.storeCornerSettings(HotCorners.withAction(root.pluginEntry, position, next));
        return next;
    }

    // The single-corner setting: that corner opens all windows, alone.
    function setHotCornerPosition(position) {
        var next = HotCorners.isPosition(position) ? position : "top-left";
        root.storeCornerSettings(HotCorners.withAllWindowsAt(root.pluginEntry, next));
        return next;
    }

    function setHotCornerEnabled(enabled) {
        var next = enabled === true;
        // The corner is also disabled while settings load; an early "off"
        // command must still be queued even though the surface is inactive.
        root.updatePluginSetting("hotCornerEnabled", next);
        return next;
    }

    function requestFooterHide() {
        if (!root.showFooter)
            return;
        root.footerHideAcknowledged = false;
        root.footerHideConfirmationOpen = true;
    }

    function closeFooterHideConfirmation() {
        root.footerHideConfirmationOpen = false;
        root.footerHideAcknowledged = false;
    }

    function confirmFooterHide() {
        if (!root.footerHideConfirmationOpen || !root.footerHideAcknowledged || !root.showFooter)
            return;
        root.updatePluginSetting("showFooter", false);
        root.closeFooterHideConfirmation();
    }

    function hotCornerHovered() {
        var groups = [hotCornerInstances, surfaceInstances, backdropInstances];
        for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
            var instances = groups[groupIndex].instances;
            for (var index = 0; index < instances.length; index++)
                if (instances[index] && instances[index].cornerHovered())
                    return true;
        }
        return false;
    }

    // A freshly mapped overview gets no pointer enter until the pointer moves,
    // so until one of its surfaces has seen the pointer it may still be resting
    // in the corner underneath.
    function overviewPointerSeen() {
        var groups = [surfaceInstances, backdropInstances];
        for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
            var instances = groups[groupIndex].instances;
            for (var index = 0; index < instances.length; index++)
                if (instances[index] && instances[index].pointerInside)
                    return true;
        }
        return false;
    }

    // Every corner shares one latch: after any corner fires, none fires again
    // until the pointer has left the corners (see hotCornerRearm).
    function triggerHotCorner(screenName, action) {
        if (!root.hotCornerEnabled || !root.hotCornerArmed)
            return;
        // Corners still close whatever they opened.
        var idle = !root.opened && !root.openingPending && showDesktop.phase === "idle";
        if (idle && root.hotCornerIgnoreFullscreen && HotCorners.showsFullscreen(Hyprland.monitors ? Hyprland.monitors.values : [], screenName))
            return;
        root.hotCornerArmed = false;
        root.runCornerAction(action, screenName);
    }

    function clearOverviewScreen() {
        root.overviewScreenPinned = false;
        root.overviewScreenName = "";
    }

    function scheduleHotCornerRearm() {
        hotCornerRearm.restart();
    }

    onHotCornerEnabledChanged: {
        if (!root.hotCornerEnabled) {
            hotCornerRearm.stop();
            root.hotCornerArmed = true;
        }
    }

    // Keyboard focus goes wherever it belongs now: the settings when they are
    // open, the window grid otherwise. Every request asks the same question, so
    // a late one from the open sequence cannot pull focus out of settings.
    function focusKeyboardSurface() {
        var surface = root.keyboardSurface();
        if (!surface)
            return;
        if (root.settingsOpen)
            surface.focusSettings();
        else
            surface.keyboardItem.forceActiveFocus();
    }

    // The mounted surface that takes the keyboard, or null while unmounted.
    function keyboardSurface() {
        var surfaces = surfaceInstances.instances;
        for (var index = 0; index < surfaces.length; index++)
            if (surfaces[index] && surfaces[index].acceptsKeyboard)
                return surfaces[index];
        return null;
    }

    // How IPC names a window: its title, or its application when untitled.
    function windowLabel(top) {
        return String(top.title || WindowModel.appIdFor(top));
    }

    // An arrow key's move, for IPC.
    function moveFromIpc(dx, dy) {
        root.moveDirectional(dx, dy, false);
    }

    function focusSettingsItem(item) {
        if (!item || !item.visible || !item.enabled)
            return false;
        item.forceActiveFocus();
        return true;
    }

    // Tab/Shift+Tab wrap through every focusable item. Up/Down (and Left/Right
    // inside the confirmation dialog) step without wrapping, so arrow keys never
    // jump from the last control back to the sidebar.
    function handleSettingsNavigation(event) {
        if (!root.settingsOpen)
            return false;
        var isTab = event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab;
        var isStep = event.key === Qt.Key_Up || event.key === Qt.Key_Down
            || (root.footerHideConfirmationOpen && (event.key === Qt.Key_Left || event.key === Qt.Key_Right));
        if (!isTab && !isStep)
            return false;
        var forward = isTab
            ? event.key !== Qt.Key_Backtab && !(event.modifiers & Qt.ShiftModifier)
            : event.key === Qt.Key_Down || event.key === Qt.Key_Right;
        var surface = root.keyboardSurface();
        if (!surface)
            return false;
        if (root.footerHideConfirmationOpen)
            surface.moveFooterConfirmationFocus(forward, isTab);
        else
            surface.moveSettingsFocus(forward, isTab);
        event.accepted = true;
        return true;
    }

    function handleSettingsTab(event) {
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return false;
        return root.handleSettingsNavigation(event);
    }

    function setFilter(value) {
        root.filterText = value;
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
        root.selectedToplevel = root.filteredToplevels[0] || null;
    }

    function setWorkspaceScope(value) {
        var next = value === "current" ? "current" : "all";
        if (next === "current" && !root.workspaceForScreen(root.keyboardScreenName))
            return;
        if (next === root.workspaceScope)
            return;
        root.workspaceScope = next;
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
        root.selectedToplevel = root.originToplevel;
    }

    function toggleWorkspaceScope() {
        root.setWorkspaceScope(root.workspaceScope === "all" ? "current" : "all");
    }

    function refreshHyprlandState() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    function handleDisplayStateChanged() {
        if (!root.surfaceMounted && !root.openingPending)
            return;
        if (!root.overviewScreenPinned && (!root.surfaceMounted || root.openingPending))
            root.overviewScreenName = root.focusedMonitorName || root.keyboardScreenName;
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
    }

    function handleToplevelMetadataChanged(top) {
        if (!root.surfaceMounted && !root.openingPending)
            return;
        // Focus history arrives with the first refresh after a shell restart.
        if (!root.originToplevel)
            root.originToplevel = WindowModel.mostRecent(root.allToplevels);
        var membershipChanged = root.syncSessionToplevels();
        // A card takes the window's new shape, such as when closing a window
        // lets its neighbour grow. A refresh without a size keeps the old one.
        var sessionIndex = root.sessionToplevels.indexOf(top);
        var size = WindowModel.ipcFor(top).size || [];
        if (sessionIndex >= 0 && Number(size[0]) > 0 && Number(size[1]) > 0) {
            var live = root.liveAspectRatioFor(top);
            if (Math.abs(live - (root.sessionAspectRatios[sessionIndex] || 0)) > 0.01) {
                var ratios = root.sessionAspectRatios.slice();
                ratios[sessionIndex] = live;
                root.sessionAspectRatios = ratios;
            }
        }
        if (!membershipChanged)
            root.modelRevision++;
        root.clearUnlistedPreview();
    }

    function clearUnlistedPreview() {
        var listed = root.filteredToplevels;
        if ((root.previewToplevel && listed.indexOf(root.previewToplevel) === -1)
                || (root.previewExitToplevel && listed.indexOf(root.previewExitToplevel) === -1))
            root.clearPreview();
    }

    function handleToplevelCollectionChanged() {
        if (!root.surfaceMounted && !root.openingPending)
            return;
        var previous = root.filteredToplevels;
        var selected = root.selection;
        var membershipChanged = root.syncSessionToplevels();
        if (!membershipChanged && root.filterText.length > 0)
            root.modelRevision++;
        root.selectedToplevel = WindowModel.successorFor(previous, root.filteredToplevels, selected);
        root.clearUnlistedPreview();
    }

    function activate(top) {
        if (!top)
            return;
        root.pendingWorkspace = null;
        root.pendingActivation = top;
        root.dismiss();
    }

    // A connector name that is safe to put in a Lua string.
    function luaMonitorName(screenName) {
        var name = String(screenName || "");
        return /^[A-Za-z0-9_.-]+$/.test(name) ? name : "";
    }

    function stripWorkspacesForScreen(screenName) {
        return WorkspaceModel.withPlaceholders(WorkspaceModel.stripWorkspaces(root.allWorkspaces, screenName),
            root.addedWorkspaces, screenName);
    }

    // + adds an empty workspace to the strip and keeps the overview open.
    function addWorkspace(screenName) {
        var id = root.newWorkspaceIdForScreen(screenName);
        if (id > 0)
            root.addedWorkspaces = root.addedWorkspaces.concat([WorkspaceModel.placeholder(id, screenName)]);
    }

    function activeWorkspaceIdForScreen(screenName) {
        var monitor = root.monitorForScreen(screenName);
        return monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : 0;
    }

    function blockForScreen(screenName) {
        return WorkspaceModel.blockFor(root.workspaceBlocks, screenName, root.activeWorkspaceIdForScreen(screenName));
    }

    function newWorkspaceIdForScreen(screenName) {
        var ids = root.allWorkspaces.concat(root.addedWorkspaces).map(function (workspace) { return Number(workspace.id); });
        return WorkspaceModel.newWorkspaceId(ids, root.blockForScreen(screenName));
    }

    // Closes the overview onto a workspace of a display.
    function switchToWorkspace(id, screenName) {
        if (!(id >= 1))
            return;
        root.pendingActivation = null;
        root.pendingWorkspace = { id: id, screen: String(screenName || "") };
        root.dismiss();
    }

    // Number keys pick a slot of the display taking the keyboard, as Super+N does.
    function switchToSlot(slot) {
        var screenName = root.keyboardScreenName;
        root.switchToWorkspace(WorkspaceModel.slotId(root.blockForScreen(screenName), slot), screenName);
    }

    // Moves a window to a workspace of a display, or to a new one ("new"),
    // without following it. The overview stays open.
    function moveToWorkspace(top, target, screenName) {
        var id = target === "new" ? root.newWorkspaceIdForScreen(screenName) : Number(target);
        var address = WindowModel.addressFor(top);
        var workspace = top && top.workspace ? top.workspace : null;
        if (!address || !(id >= 1) || WindowModel.isPinned(top) || (workspace && Number(workspace.id) === id))
            return;
        var lua = "hl.dispatch(hl.dsp.window.move({ workspace = '" + id + "', follow = false, window = 'address:" + address + "' }))";
        // A workspace that does not exist yet opens on the window's display;
        // bring it to this one.
        var exists = root.allWorkspaces.some(function (existing) { return Number(existing.id) === id; });
        var monitor = root.luaMonitorName(screenName);
        var windowMonitor = top.monitor ? String(top.monitor.name || "") : "";
        if (!exists && monitor && windowMonitor !== monitor)
            lua += "; hl.dispatch(hl.dsp.workspace.move({ workspace = '" + id + "', monitor = '" + monitor + "' }))";
        Hyprland.dispatch("(function() " + lua + " end)");
        // Hyprland reports where the window now sits on the next refresh.
        movedWindowRefresh.restart();
    }

    // Also restarted when the session's windows change.
    Timer {
        id: movedWindowRefresh
        interval: 100
        onTriggered: root.refreshHyprlandState()
    }

    FileView {
        id: workspaceBlocksFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/monitors/workspaces"
        watchChanges: true
        printErrors: false
        onLoaded: root.workspaceBlocks = text()
        onLoadFailed: root.workspaceBlocks = ""
        onFileChanged: Qt.callLater(workspaceBlocksFile.reload)
    }

    // Runs once a surface has lost the keyboard, or once the surfaces are gone
    // if none held it. When an exclusive-keyboard layer lets go, Hyprland
    // returns focus to the previous window, overriding any earlier request.
    function dispatchPendingActivation() {
        var workspace = root.pendingWorkspace;
        root.pendingWorkspace = null;
        if (workspace) {
            root.pendingActivation = null;
            var monitor = root.luaMonitorName(workspace.screen);
            var show = "hl.dispatch(hl.dsp.focus({ workspace = '" + workspace.id + "' }))";
            // A workspace that does not exist yet opens on the focused display.
            if (monitor)
                show = "local m = hl.get_monitor('" + monitor + "'); if m and not m.focused then "
                    + "hl.dispatch(hl.dsp.focus({ monitor = '" + monitor + "' })) end; " + show;
            Hyprland.dispatch("(function() " + show + " end)");
            return;
        }
        var top = root.pendingActivation;
        var address = WindowModel.addressFor(top);
        root.pendingActivation = null;
        if (!address)
            return;
        var target = "window = 'address:" + address + "'";
        // Focus alone does not raise a floating window in Hyprland, so on a
        // floating workspace the chosen window would stay behind the ones
        // covering it. Raise it as well, as Omarchy's Alt+Tab and the dock do.
        var raise = "hl.dispatch(hl.dsp.window.alter_zorder({ mode = 'top', " + target + " }))";
        // Hyprland keeps a hidden stacking state on a workspace with a
        // maximized or fullscreen window W:
        //   W on top      the usual state once W is maximized or fullscreen
        //   W covered     a floating window was focused meanwhile and is now
        //                 drawn above W; raising W does not undo this
        //   W on top      again whenever W's state is set afresh
        // Picking another window should leave W covered, so that window shows.
        // Picking W must put W back on top, so its state is unset and set
        // again, in one call so it keeps its size. That runs only when a
        // floating, non-fullscreen window shares W's workspace, the only kind
        // that can cover it, so a lone or tiled-only W is never resized.
        raise += "; local w = hl.get_window('address:" + address + "')"
            + "; if w and (w.fullscreen == 1 or w.fullscreen == 2) and w.workspace then"
            + " local covered = false"
            + " for _, other in ipairs(hl.get_workspace_windows(tostring(w.workspace.id))) do"
            + " if other.address ~= w.address and other.floating and (other.fullscreen or 0) == 0 then covered = true end"
            + " end"
            + " if covered then"
            + " local mode = w.fullscreen == 1 and 'maximized' or 'fullscreen'"
            + "; hl.dispatch(hl.dsp.window.fullscreen({ mode = mode, action = 'unset', window = w }))"
            + "; hl.dispatch(hl.dsp.window.fullscreen({ mode = mode, action = 'set', window = w }))"
            + " end end";
        var focus = "hl.dispatch(hl.dsp.focus({ " + target + " })); " + raise;
        // A window minimized to the dock comes back to the workspace in front
        // of the user, on top and without animating in, as the dock restores it.
        var monitor = Hyprland.focusedMonitor;
        var workspaceId = monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : -1;
        if (WindowModel.isMinimized(top) && workspaceId >= 1) {
            focus = "hl.dispatch(hl.dsp.window.set_prop({ prop = 'no_anim', value = '1', " + target + " })); "
                + "hl.dispatch(hl.dsp.window.move({ workspace = '" + workspaceId + "', follow = false, " + target + " })); "
                + focus;
            restoredAnimationTimer.targets.push(target);
            restoredAnimationTimer.restart();
        }
        Hyprland.dispatch(root.moveCursorToWindow
            ? "(function() " + focus + " end)"
            : "(function() local p = hl.get_cursor_pos(); " + focus
                + "; hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end)");
    }

    // Keep every restore target when rapid activations restart the delay.
    Timer {
        id: restoredAnimationTimer
        property var targets: []
        interval: 400
        onTriggered: {
            for (var index = 0; index < targets.length; index++)
                Hyprland.dispatch("hl.dsp.window.set_prop({ prop = 'no_anim', value = 'unset', " + targets[index] + " })");
            targets = [];
        }
    }

    // Windows the overview asked to close. Their captures stop first:
    // Hyprland drops the shell's whole Wayland connection when it is asked to
    // capture a window that has just been destroyed.
    property var closingToplevels: []

    function captureSourceFor(top) {
        return root.closingToplevels.indexOf(top) === -1 ? WindowModel.waylandFor(top) : null;
    }

    function requestClose(top) {
        var wayland = WindowModel.waylandFor(top);
        if (!wayland || typeof wayland.close !== "function")
            return;
        root.closingToplevels = root.closingToplevels.concat([top]);
        closingRelease.restart();
        // Sent after the captures have let go of the window.
        Qt.callLater(function () { wayland.close(); });
    }

    // A window that is still open, such as one asking to save first, gets its
    // capture back.
    Timer {
        id: closingRelease
        interval: 2000
        onTriggered: root.closingToplevels = []
    }

    function resetSessionToplevels() {
        var next = [];
        for (var index = 0; index < root.allToplevels.length; index++)
            if (WindowModel.isEligible(root.allToplevels[index]))
                next.push(root.allToplevels[index]);
        root.sessionToplevels = next;
        root.captureSessionAspectRatios();
        root.modelRevision++;
    }

    function syncSessionToplevels() {
        if (!root.surfaceMounted && !root.openingPending)
            return false;
        var current = [];
        for (var currentIndex = 0; currentIndex < root.allToplevels.length; currentIndex++)
            if (WindowModel.isEligible(root.allToplevels[currentIndex]))
                current.push(root.allToplevels[currentIndex]);

        var next = [];
        var nextRatios = [];
        for (var oldIndex = 0; oldIndex < root.sessionToplevels.length; oldIndex++) {
            var existing = root.sessionToplevels[oldIndex];
            if (current.indexOf(existing) === -1)
                continue;
            next.push(existing);
            nextRatios.push(root.sessionAspectRatios[oldIndex] || root.liveAspectRatioFor(existing));
        }
        for (var newIndex = 0; newIndex < current.length; newIndex++) {
            var candidate = current[newIndex];
            if (next.indexOf(candidate) !== -1)
                continue;
            next.push(candidate);
            nextRatios.push(root.liveAspectRatioFor(candidate));
        }

        var changed = next.length !== root.sessionToplevels.length;
        for (var compareIndex = 0; !changed && compareIndex < next.length; compareIndex++)
            changed = next[compareIndex] !== root.sessionToplevels[compareIndex];
        if (!changed)
            return false;
        root.sessionToplevels = next;
        root.sessionAspectRatios = nextRatios;
        root.modelRevision++;
        // A window opening or closing retiles its neighbours, and Hyprland
        // reports their new sizes on the next refresh.
        movedWindowRefresh.restart();
        return true;
    }

    function captureSessionAspectRatios() {
        var ratios = [];
        for (var index = 0; index < root.sessionToplevels.length; index++)
            ratios.push(root.liveAspectRatioFor(root.sessionToplevels[index]));
        root.sessionAspectRatios = ratios;
    }

    function formatWorkspaceLabel(name) {
        return WindowModel.formatWorkspaceLabel(name, root.workspaceLabelStyle);
    }

    function workspaceName(top) {
        return root.formatWorkspaceLabel(WindowModel.workspaceName(top));
    }

    function workspaceLabel(top) {
        return "Workspace " + root.workspaceName(top);
    }

    function monitorForScreen(screenName) {
        var wanted = String(screenName || "");
        var monitors = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (var index = 0; index < monitors.length; index++) {
            var monitor = monitors[index];
            if (monitor && monitor.name === wanted)
                return monitor;
        }
        return null;
    }

    function workspaceForScreen(screenName) {
        if (DisplayModel.usesOwnWindows(root.multiMonitorMode)) {
            var monitor = root.monitorForScreen(screenName);
            if (monitor && monitor.activeWorkspace)
                return monitor.activeWorkspace;
        }
        return Hyprland.focusedWorkspace || null;
    }

    function activeWorkspaceLabelForScreen(screenName) {
        var workspace = root.workspaceForScreen(screenName);
        if (!workspace)
            return "—";
        return root.formatWorkspaceLabel(String(workspace.name || workspace.id || "—"));
    }

    function workspaceScopeLabelForScreen(screenName) {
        return root.workspaceScope === "current"
            ? "Workspace " + root.activeWorkspaceLabelForScreen(screenName)
            : "All workspaces";
    }

    function isOnScreen(top, screenName) {
        return WindowModel.isOnScreen(top, screenName, DisplayModel.usesOwnWindows(root.multiMonitorMode));
    }

    function isOnWorkspace(top, workspace) {
        return WindowModel.isOnWorkspace(top, workspace);
    }

    function toplevelsOnScreen(screenName) {
        var result = [];
        var source = root.surfaceMounted || root.openingPending ? root.sessionToplevels : root.allToplevels;
        for (var index = 0; index < source.length; index++) {
            var top = source[index];
            if (top && root.isOnScreen(top, screenName))
                result.push(top);
        }
        return result;
    }

    function toplevelsForScreen(screenName) {
        var needle = root.filterText.toLowerCase();
        var currentWorkspace = root.workspaceForScreen(screenName);
        var candidates = root.toplevelsOnScreen(screenName);
        var result = [];
        for (var index = 0; index < candidates.length; index++) {
            var top = candidates[index];
            if (root.workspaceScope === "current" && !root.isOnWorkspace(top, currentWorkspace))
                continue;
            if (root.overviewMode === "app-windows" && !WindowModel.matchesApp(top, root.appKey))
                continue;
            var haystack = WindowModel.searchTextFor(top);
            if (!needle || haystack.indexOf(needle) !== -1)
                result.push(top);
        }
        return result;
    }

    function toplevelListsEqual(left, right) {
        if (left.length !== right.length)
            return false;
        for (var index = 0; index < left.length; index++)
            if (left[index] !== right[index])
                return false;
        return true;
    }

    function liveAspectRatioFor(top) {
        return WindowModel.aspectRatioFor(top);
    }

    function aspectRatioFor(top) {
        if (root.surfaceMounted) {
            var index = root.sessionToplevels.indexOf(top);
            if (index >= 0 && root.sessionAspectRatios[index] > 0)
                return root.sessionAspectRatios[index];
        }
        return root.liveAspectRatioFor(top);
    }

    function previewRectFor(top, sourceRect, width, height, padding, footerHeight) {
        return GridLayout.previewRect(root.aspectRatioFor(top), root.previewPlacement === "centered",
            sourceRect, width, height, padding, footerHeight);
    }

    // Steps to the nearest card in a direction, across every mounted grid.
    function moveDirectional(dx, dy, slowMotion) {
        var rects = [];
        var tops = [];
        var surfaces = surfaceInstances.instances;
        for (var index = 0; index < surfaces.length; index++) {
            if (!surfaces[index])
                continue;
            rects = rects.concat(surfaces[index].navigationRects());
            tops = tops.concat(surfaces[index].screenToplevels);
        }
        var bestIndex = GridLayout.neighbourIndex(rects, tops.indexOf(root.selection), dx, dy);
        if (bestIndex < 0)
            return;

        var previousPreview = root.previewToplevel;
        var next = tops[bestIndex];
        root.selectedToplevel = next;
        if (previousPreview) {
            root.previewSlowMotion = false;
            root.previewNavigationSlowMotion = slowMotion === true;
            previewExitTimer.stop();
            root.previewExitToplevel = previousPreview;
            root.previewToplevel = next;
            previewExitTimer.restart();
        }
    }

    function togglePreview(slowMotion) {
        root.previewNavigationSlowMotion = false;
        root.previewSlowMotion = slowMotion === true;
        if (root.previewToplevel) {
            root.previewExitToplevel = root.previewToplevel;
            root.previewToplevel = null;
            previewExitTimer.restart();
            return;
        }
        previewExitTimer.stop();
        root.previewExitToplevel = null;
        var target = root.hoveredToplevel || root.selection;
        if (target && root.filteredToplevels.indexOf(target) !== -1) {
            root.selectedToplevel = target;
            root.previewToplevel = target;
        }
    }

    // The app's name from its desktop entry, else its app id.
    function appNameFor(top) {
        var identity = IconResolver.identityFor(top);
        var entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        var entry = IconResolver.findEntry(entries, identity.candidates);
        return String((entry && entry.name) || WindowModel.appIdFor(top) || "App");
    }

    function iconFor(top) {
        var identity = IconResolver.identityFor(top);
        if (Object.prototype.hasOwnProperty.call(root.iconCache, identity.key))
            return root.iconCache[identity.key];
        var entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        var entry = IconResolver.findEntry(entries, identity.candidates);
        var iconName = entry
            ? String(entry.icon || "application-x-executable")
            : String(identity.candidates[0] || "application-x-executable");
        var appLibrary = root.shell && root.shell.appLibrary ? root.shell.appLibrary : null;
        var result = appLibrary && typeof appLibrary.iconSource === "function"
            ? String(appLibrary.iconSource(iconName) || "")
            : "";
        if (!result)
            result = Quickshell.iconPath(iconName, true);
        root.iconCache[identity.key] = result;
        return result;
    }

    function handleKey(event) {
        if (root.settingsOpen) {
            if (event.key === Qt.Key_Escape) {
                if (root.footerHideConfirmationOpen)
                    root.closeFooterHideConfirmation();
                else
                    root.closeSettings();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
            return;
        }
        if (event.key === Qt.Key_Escape) {
            if (root.draggedToplevel)
                root.draggedToplevel = null;
            else if (root.previewToplevel || root.previewExitToplevel)
                root.clearPreview();
            else
                root.dismiss();
        } else if (event.key === Qt.Key_Space || event.text === " ") {
            if (!event.isAutoRepeat)
                root.togglePreview(Boolean(event.modifiers & Qt.ShiftModifier));
        }
        else if (event.key === Qt.Key_Tab
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (!event.isAutoRepeat)
                root.toggleWorkspaceScope();
        }
        else if (event.key === Qt.Key_Left)
            root.moveDirectional(-1, 0, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Right)
            root.moveDirectional(1, 0, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Up)
            root.moveDirectional(0, -1, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Down)
            root.moveDirectional(0, 1, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.activate(root.selection);
        else if (event.key === Qt.Key_Q
                && Boolean(event.modifiers & Qt.ShiftModifier)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (!event.isAutoRepeat)
                root.requestClose(root.selection);
        }
        // With the workspace strip, the number row switches workspace until a
        // filter is typed, so digits can still narrow a filter.
        else if (root.workspaceStrip && !root.filterText
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                && WorkspaceModel.slotForKey(event.key, event.nativeScanCode) > 0) {
            if (!event.isAutoRepeat)
                root.switchToSlot(WorkspaceModel.slotForKey(event.key, event.nativeScanCode));
        }
        else if (Util.editsFilter(event, root.filterText))
            root.setFilter(Util.editedFilter(event, root.filterText));
        else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier)))
            root.setFilter(root.filterText + event.text);
        else
            return;
        event.accepted = true;
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.handleToplevelCollectionChanged(); }
    }

    Instantiator {
        model: Hyprland.toplevels

        delegate: Connections {
            required property var modelData
            target: modelData
            function onWorkspaceChanged() { root.handleDisplayStateChanged(); }
            function onMonitorChanged() { root.handleDisplayStateChanged(); }
            function onLastIpcObjectChanged() { root.handleToplevelMetadataChanged(modelData); }
            function onWaylandHandleChanged() { root.handleToplevelCollectionChanged(); }
        }
    }

    Instantiator {
        model: Hyprland.monitors

        delegate: Connections {
            required property var modelData
            target: modelData
            function onActiveWorkspaceChanged() { root.handleDisplayStateChanged(); }
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.iconCache = {};
        }
    }

    Connections {
        target: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
        function onIconIndexChanged() { root.iconCache = {}; }
    }

    Timer {
        id: previewExitTimer
        interval: root.previewAnimationDuration
        onTriggered: {
            root.previewExitToplevel = null;
            root.previewNavigationSlowMotion = false;
            if (!root.previewToplevel)
                root.previewSlowMotion = false;
        }
    }

    NumberAnimation {
        id: overviewMotionAnimation
        target: root
        property: "motionProgress"
        onFinished: root.completeMotion()
    }

    WallpaperSource {
        id: wallpaperSource
        active: (root.backgroundMode === "wallpaper" || root.workspaceStrip) && (root.openingPending || root.surfaceMounted)
        retained: root.backgroundMode === "wallpaper"
    }

    // A hidden copy of each display's wallpaper backdrop keeps its decoded
    // image referenced while the overview is closed. Qt drops an unreferenced
    // image this large from its cache at once, so every opening would decode
    // it again and show the base colour until it was ready.
    Variants {
        model: root.backgroundMode === "wallpaper" ? Quickshell.screens : []

        WallpaperBackdrop {
            required property var modelData
            visible: false
            width: modelData.width
            height: modelData.height
            pixelRatio: modelData.devicePixelRatio
            source: wallpaperSource.source
            blur: root.effectiveBackgroundBlur
        }
    }

    Timer {
        id: backgroundBlurUpdate
        interval: 16
        onTriggered: {
            if (!backgroundBlurSession.running)
                return;
            var requested = root.requestedBackgroundBlur();
            if (requested === root.lastRequestedBlur)
                return;
            root.lastRequestedBlur = requested;
            root.writeBackgroundBlur(requested);
        }
    }

    Timer {
        id: hotCornerRearm
        interval: 100
        onTriggered: {
            // Hiding the closed corner under the overview reports an exit
            // even though the pointer never moved. Arming then would let the
            // first motion out of the corner dismiss the overview again.
            if (root.surfaceMounted && !root.overviewPointerSeen())
                return;
            if (!root.hotCornerHovered())
                root.hotCornerArmed = true;
        }
    }

    Process {
        id: backgroundBlurSession
        command: [root.pluginDir + "/background-blur-session"]
        stdinEnabled: true
        onStarted: {
            var initialBlur = root.requestedBackgroundBlur();
            root.lastRequestedBlur = initialBlur;
            root.writeBackgroundBlur(initialBlur);
        }
        stdout: SplitParser {
            onRead: function (line) {
                var applied = Number(line);
                if (!isFinite(applied))
                    return;
                if (applied < 0) {
                    if (root.backgroundBlurReleasePhase > 0) {
                        root.backgroundBlurReleasePhase = 0;
                        backgroundBlurSession.running = false;
                        if (root.surfaceMounted) {
                            root.surfaceMounted = false;
                            root.backgroundBlurPrimed = false;
                            root.clearOverviewScreen();
                        }
                        if (root.openingPending) {
                            root.backgroundBlurFailed = true;
                            root.prepareOpenSurface();
                        } else {
                            root.finishDismiss();
                        }
                        return;
                    }
                    root.backgroundBlurFailed = true;
                    root.prepareOpenSurface();
                    return;
                }
                if (applied === 0 && root.backgroundBlurReleasePhase === 1) {
                    root.backgroundBlurReleasePhase = 0;
                    if (root.openingPending) {
                        root.lastRequestedBlur = root.requestedBackgroundBlur();
                        root.writeBackgroundBlur(root.lastRequestedBlur);
                    } else {
                        backgroundBlurSession.running = false;
                        root.releaseBlurredSurface();
                    }
                    return;
                }
                if (root.openingPending) {
                    root.backgroundBlurReleasePhase = 0;
                    root.backgroundBlurPrimed = true;
                    root.prepareOpenSurface();
                }
            }
        }
        onExited: function (exitCode, exitStatus) { // qmllint disable signal-handler-parameters
            root.backgroundBlurPrimed = false;
            root.lastRequestedBlur = -1;
            if (root.backgroundBlurReleasePhase > 0) {
                root.backgroundBlurReleasePhase = 0;
                if (root.surfaceMounted) {
                    root.surfaceMounted = false;
                    root.clearOverviewScreen();
                }
                if (!root.surfaceMounted && !root.openingPending)
                    root.finishDismiss();
            }
            if (root.openingPending) {
                root.backgroundBlurFailed = true;
                root.prepareOpenSurface();
            }
        }
    }

    // Let compositor keybinds reach the resident shell without spawning a CLI.
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { root.handleDisplayStateChanged(); }
        function onFocusedWorkspaceChanged() { root.handleDisplayStateChanged(); }
        function onActiveToplevelChanged() {
            if (root.opened && root.filteredToplevels.indexOf(Hyprland.activeToplevel) !== -1)
                root.selectedToplevel = Hyprland.activeToplevel;
        }
        function onRawEvent(event) {
            if (event && event.name === "configreloaded") {
                compositorBorders.refresh();
                root.installLayerRule();
            }
            if (event && event.name === "custom" && event.data === "expose.window-overview:toggle")
                root.toggle();
            if (event && event.name === "fullscreen" && root.hotCornerIgnoreFullscreen)
                Hyprland.refreshToplevels();
        }
    }

    IpcHandler {
        target: "expose"
        function open(): string {
            // Must not be root.toggle(): that makes "open" a duplicate of
            // "toggle", so calling open on an already-open overview closes it.
            // Mirrors close(), which correctly calls dismiss(). An overview
            // showing one app's windows widens to all of them.
            if (!root.opened && !root.openingPending)
                root.open("{}");
            else if (root.overviewMode !== "all-windows")
                root.switchOverviewMode("all-windows");
            return "ok";
        }
        // App windows (macOS Application Windows): the focused app's windows,
        // minimized ones included. Same toggle rules as toggle().
        function toggleApplication(): string {
            root.showOverview("app-windows", "");
            return "ok";
        }
        function openApplication(): string {
            if (!root.opened && !root.openingPending)
                root.open(JSON.stringify({ mode: "app-windows" }));
            else if (root.overviewMode !== "app-windows")
                root.switchOverviewMode("app-windows");
            return root.overviewMode;
        }
        // Desktop (macOS Show Desktop): a temporary peek at the desktop that
        // ends when a window is focused or the workspace changes.
        function toggleDesktop(): string {
            root.toggleDesktop();
            return "ok";
        }
        function desktop(mode: string): string {
            if (mode === "show") {
                // A Desktop already waiting for Exposé to close stays queued.
                if (root.desktopAfterDismiss)
                    return showDesktop.phase;
                if (root.opened || root.openingPending)
                    root.toggleDesktop();
                else
                    showDesktop.show();
            } else if (mode === "hide") {
                // A show waiting for Exposé to close is cancelled too.
                root.desktopAfterDismiss = false;
                showDesktop.restore(true);
            } else if (mode === "toggle") {
                root.toggleDesktop();
            } else if (mode !== "state") {
                return "expected show, hide, toggle, or state";
            }
            return showDesktop.phase;
        }
        function close(): string {
            root.dismiss();
            return "ok";
        }
        function toggle(): string {
            root.toggle();
            return "ok";
        }
        function animationDuration(style: string, value: real): string {
            return SettingsSchema.parseIpc("animationStyle", style).error || String(root.setAnimationDuration(style, value));
        }
        function animationDurationIn(style: string, value: real): string {
            return SettingsSchema.parseIpc("animationStyle", style).error || String(root.setAnimationDurationIn(style, value));
        }
        function animationDurationOut(style: string, value: real): string {
            return SettingsSchema.parseIpc("animationStyle", style).error || String(root.setAnimationDurationOut(style, value));
        }
        function slideDirection(direction: string): string {
            if (!root.isSlideDirection(direction))
                return SettingsSchema.expectedOneOf(root.slideDirections);
            return root.setSlideDirection(direction);
        }
        function slideDirectionIn(direction: string): string {
            if (!root.isSlideDirection(direction))
                return SettingsSchema.expectedOneOf(root.slideDirections);
            return root.setSlideDirectionIn(direction);
        }
        function slideDirectionOut(direction: string): string {
            if (!root.isSlideDirection(direction))
                return SettingsSchema.expectedOneOf(root.slideDirections);
            return root.setSlideDirectionOut(direction);
        }
        function previewPlacement(mode: string): string { return root.setSettingFromIpc("previewPlacement", mode); }
        function windowFooterStyle(style: string): string { return root.setSettingFromIpc("windowFooterStyle", style); }
        function selectionStyle(style: string): string { return root.setSettingFromIpc("selectionStyle", style); }
        function animationStyle(style: string): string { return root.setSettingFromIpc("animationStyle", style); }
        function backgroundMode(mode: string): string { return root.setSettingFromIpc("backgroundMode", mode); }
        function backgroundBlur(value: real): string { return root.setSettingFromIpc("backgroundBlur", value); }
        function backgroundDim(value: real): string { return root.setSettingFromIpc("backgroundDim", value); }
        function showFooter(mode: string): string { return root.setSettingFromIpc("showFooter", mode); }
        function closeButton(mode: string): string { return root.setSettingFromIpc("closeButton", mode); }
        function closeButtonSide(side: string): string { return root.setSettingFromIpc("closeButtonSide", side); }
        function initialWorkspaceScope(scope: string): string { return root.setSettingFromIpc("initialWorkspaceScope", scope); }
        function workspaceLabelStyle(style: string): string { return root.setSettingFromIpc("workspaceLabelStyle", style); }
        function workspaceStrip(mode: string): string { return root.setSettingFromIpc("workspaceStrip", mode); }
        function workspaceDrag(mode: string): string { return root.setSettingFromIpc("workspaceDrag", mode); }
        // What the overview is doing now, as JSON, for scripts and live checks.
        // The filter, windows, and selection describe the open overview only.
        function state(): string {
            var open = root.opened;
            var top = open ? root.selection : null;
            return JSON.stringify({
                opened: open,
                opening: root.openingPending,
                mounted: root.surfaceMounted,
                settingsOpen: root.settingsOpen,
                scope: root.workspaceScope,
                filter: open ? root.filterText : "",
                mode: open ? root.overviewMode : null,
                app: open && root.overviewMode === "app-windows" ? root.appKey : null,
                desktop: showDesktop.phase,
                windows: open ? root.filteredToplevels.length : 0,
                selection: top ? root.windowLabel(top) : null,
                selectionAddress: top ? WindowModel.addressFor(top) : null,
                preview: root.previewToplevel !== null
            });
        }
        function get(name: string): string {
            if (!Object.prototype.hasOwnProperty.call(SettingsSchema.specs, name))
                return SettingsSchema.expectedOneOf(Object.keys(SettingsSchema.specs));
            var corner = root.cornerForSetting(name);
            if (corner)
                return root.hotCornerActions[corner];
            var value = SettingsSchema.read(root.pluginEntry, name);
            return typeof value === "boolean" ? (value ? "on" : "off") : String(value);
        }
        // The overview's own keys. Each answers "closed" unless it is open.
        function move(direction: string): string {
            var step = ({ left: [-1, 0], right: [1, 0], up: [0, -1], down: [0, 1] })[direction];
            if (!step)
                return SettingsSchema.expectedOneOf(["left", "right", "up", "down"]);
            if (!root.opened)
                return "closed";
            root.moveFromIpc(step[0], step[1]);
            return root.selection ? root.windowLabel(root.selection) : "";
        }
        function filter(text: string): string {
            if (!root.opened)
                return "closed";
            root.setFilter(text);
            return String(root.filteredToplevels.length);
        }
        function preview(): string {
            if (!root.opened)
                return "closed";
            root.togglePreview(false);
            return root.previewToplevel ? "on" : "off";
        }
        function activate(): string {
            if (!root.opened)
                return "closed";
            if (!root.selection)
                return "no selection";
            root.activate(root.selection);
            return "ok";
        }
        function settings(mode: string): string {
            if (mode === "open")
                root.openSettings();
            else if (mode === "close")
                root.closeSettings();
            else if (mode === "toggle")
                root.settingsOpen ? root.closeSettings() : root.openSettings();
            else
                return "expected open, close, or toggle";
            return mode;
        }
        function hotCorner(mode: string): string { return root.setSettingFromIpc("hotCornerEnabled", mode); }
        function hotCornerPosition(position: string): string { return root.setSettingFromIpc("hotCornerPosition", position); }
        // What a corner does: off, all-windows, app-windows, or desktop.
        function hotCornerAction(position: string, action: string): string {
            if (!HotCorners.isPosition(position))
                return SettingsSchema.expectedOneOf(HotCorners.positions);
            if (!HotCorners.isAction(action))
                return SettingsSchema.expectedOneOf(HotCorners.actions);
            return root.setHotCornerAction(position, action);
        }
        // Every corner at once, as JSON: { "top-left": "all-windows", ... }.
        function hotCorners(): string { return JSON.stringify(root.hotCornerActions); }
        function hotCornerDelay(value: real): string { return root.setSettingFromIpc("hotCornerDelay", value); }
        function hotCornerAllDisplays(mode: string): string { return root.setSettingFromIpc("hotCornerAllDisplays", mode); }
        function hotCornerIgnoreFullscreen(mode: string): string { return root.setSettingFromIpc("hotCornerIgnoreFullscreen", mode); }
        function moveCursorToWindow(mode: string): string { return root.setSettingFromIpc("moveCursorToWindow", mode); }
        function multiMonitorMode(mode: string): string { return root.setSettingFromIpc("multiMonitorMode", mode); }
    }

    component HotCornerTarget: Item {
        id: cornerTarget
        required property bool onTop
        required property bool onLeft
        readonly property bool hovered: enabled && (horizontalTarget.containsMouse || verticalTarget.containsMouse)
        signal entered()
        signal exited()

        implicitWidth: root.hotCornerReach
        implicitHeight: root.hotCornerReach

        // The two strips overlap in the corner square, so hovering is tracked
        // across both: sliding from one into the other must not restart the
        // dwell or report a spurious exit.
        onHoveredChanged: {
            if (cornerTarget.hovered) {
                if (root.effectiveHotCornerDelay > 0)
                    dwellTimer.restart();
                else
                    cornerTarget.entered();
            } else {
                dwellTimer.stop();
                cornerTarget.exited();
            }
        }

        Timer {
            id: dwellTimer
            interval: root.effectiveHotCornerDelay
            onTriggered: {
                if (cornerTarget.hovered)
                    cornerTarget.entered();
            }
        }

        MouseArea {
            id: horizontalTarget
            x: 0
            y: cornerTarget.onTop ? 0 : parent.height - height
            width: parent.width
            height: root.hotCornerDepth
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        MouseArea {
            id: verticalTarget
            x: cornerTarget.onLeft ? 0 : parent.width - width
            y: 0
            width: root.hotCornerDepth
            height: parent.height
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    // One small surface per corner that does something, on each display that
    // answers it. Full-screen surfaces take over corner handling while Exposé
    // is mounted, so every corner keeps working with the overview open.
    Variants {
        id: hotCornerInstances
        model: root.hotCornerSurfaces

        PanelWindow { // qmllint disable uncreatable-type
            id: cornerSurface
            required property var modelData
            readonly property bool cornerOnTop: HotCorners.onTop(modelData.position)
            readonly property bool cornerOnLeft: HotCorners.onLeft(modelData.position)
            screen: modelData.screen
            visible: !root.surfaceMounted
            anchors {
                top: cornerSurface.cornerOnTop
                right: !cornerSurface.cornerOnLeft
                bottom: !cornerSurface.cornerOnTop
                left: cornerSurface.cornerOnLeft
            }
            implicitWidth: root.hotCornerReach
            implicitHeight: root.hotCornerReach
            color: "#02000000"
            mask: Region {
                Region {
                    x: 0
                    y: cornerSurface.cornerOnTop ? 0 : root.hotCornerReach - root.hotCornerDepth
                    width: root.hotCornerReach
                    height: root.hotCornerDepth
                }
                Region {
                    x: cornerSurface.cornerOnLeft ? 0 : root.hotCornerReach - root.hotCornerDepth
                    y: 0
                    width: root.hotCornerDepth
                    height: root.hotCornerReach
                }
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "expose-hot-corner"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            function cornerHovered() { return closedHotCorner.hovered; }

            HotCornerTarget {
                id: closedHotCorner
                anchors.fill: parent
                enabled: !root.surfaceMounted
                onTop: cornerSurface.cornerOnTop
                onLeft: cornerSurface.cornerOnLeft
                onEntered: root.triggerHotCorner(String(cornerSurface.modelData.screen.name || ""), cornerSurface.modelData.action)
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }

    component OverviewSurface: PanelWindow { // qmllint disable uncreatable-type
        id: surface
        required property var modelData
        screen: modelData
        visible: true
        anchors {
            top: true
            right: true
            bottom: true
            left: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "expose-window-overview"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland restricts pointer hit testing to exclusive surfaces too.
        // Every backdrop must participate so clicks on other displays arrive.
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        HyprlandWindow.opacity: root.motionProgress
        BackgroundEffect.blurRegion: root.desktopBackgroundBlur > 0 // qmllint disable missing-type
                && !root.backgroundBlurFailed
            ? backgroundBlurRegion
            : null
        readonly property bool pointerInside: overviewPointer.hovered
        // The configured corners on this display.
        readonly property var openCorners: root.hotCornerSurfaces.filter(function (corner) {
            return corner.screen === surface.modelData;
        })
        function cornerHovered() {
            for (var index = 0; index < openCornerTargets.count; index++) {
                var target = openCornerTargets.itemAt(index) as HotCornerTarget;
                if (target && target.hovered)
                    return true;
            }
            return false;
        }

        Region {
            id: backgroundBlurRegion
            item: surface.contentItem
        }

        Loader {
            anchors.fill: parent
            active: root.backgroundMode === "wallpaper"
            sourceComponent: WallpaperBackdrop {
                source: wallpaperSource.source
                blur: root.effectiveBackgroundBlur
                // The screen's ratio, as the cached copy above uses: the window's can
                // start at 1 and change once the compositor sends its scale.
                pixelRatio: surface.modelData.devicePixelRatio
                color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 1)
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.effectiveBackgroundDim / 100
        }

        // Losing the keyboard means Hyprland has already handed focus back,
        // so the chosen window's focus can be dispatched without waiting for
        // the closing animation.
        Item {
            Window.onActiveChanged: {
                if (surface.modelData === root.effectiveOverviewScreen
                        && !Window.active && (root.pendingActivation || root.pendingWorkspace))
                    root.dispatchPendingActivation();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                // A click beside Quick Look closes the preview, on the display
                // showing it; anywhere else it dismisses the overview.
                var preview = root.previewToplevel || root.previewExitToplevel;
                var previewHere = root.multiMonitorMode === "all-monitors"
                    ? root.toplevelsForScreen(String(surface.modelData.name || "")).indexOf(preview) !== -1
                    : surface.modelData === root.effectiveOverviewScreen;
                if (preview && previewHere)
                    root.clearPreview();
                else
                    root.dismiss();
            }
            onWheel: function (wheel) { wheel.accepted = true; }
        }

        HoverHandler {
            id: overviewPointer
            onHoveredChanged: {
                if (hovered)
                    root.scheduleHotCornerRearm();
            }
        }

        Repeater {
            id: openCornerTargets
            model: surface.openCorners

            HotCornerTarget {
                required property var modelData
                width: root.hotCornerReach
                height: root.hotCornerReach
                x: onLeft ? 0 : surface.width - width
                y: onTop ? 0 : surface.height - height
                z: 100
                enabled: root.surfaceMounted
                onTop: HotCorners.onTop(modelData.position)
                onLeft: HotCorners.onLeft(modelData.position)
                onEntered: root.triggerHotCorner(String(surface.modelData.name || ""), modelData.action)
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }

    Variants {
        id: backdropInstances
        model: root.backdropScreens
        OverviewSurface {
            Item {
                anchors.fill: parent
                focus: true
                Keys.forwardTo: root.opened ? root.overviewKeyboardTargets : []
            }
        }
    }

    Variants {
        id: surfaceInstances
        model: root.mountedScreens

        OverviewSurface {
            id: overviewWindow
            readonly property string screenName: String(modelData.name || "")
            readonly property var monitor: root.monitorForScreen(overviewWindow.screenName)
            // Window positions are in the desktop's logical coordinates.
            readonly property real monitorX: overviewWindow.monitor ? Number(overviewWindow.monitor.x) : 0
            readonly property real monitorY: overviewWindow.monitor ? Number(overviewWindow.monitor.y) : 0
            readonly property bool acceptsKeyboard: {
                var wanted = root.effectiveOverviewScreenName;
                if (wanted)
                    return String(modelData.name || "") === wanted;
                return true;
            }
            property alias keyboardItem: keyCatcher
            readonly property alias windowLayout: overviewArea.windowLayout
            // Forwarded events don't bubble through the target's parents.
            // Run overview shortcuts first, then the focused settings control.
            readonly property var keyboardTargets: {
                var focused = keyCatcher.Window.window ? keyCatcher.Window.window.activeFocusItem : null;
                return focused && focused !== keyCatcher ? [keyCatcher, focused] : [keyCatcher];
            }
            readonly property var screenToplevels: {
                var revision = root.modelRevision;
                return root.toplevelsForScreen(String(modelData.name || ""));
            }
            // The grid's cards in desktop coordinates, alongside screenToplevels,
            // so arrow keys can cross from one display's grid to the next.
            function navigationRects() {
                var monitor = root.monitorForScreen(overviewWindow.screenName);
                var origin = overviewArea.mapToItem(keyCatcher, 0, 0);
                var offsetX = (monitor ? monitor.x : 0) + origin.x;
                var offsetY = (monitor ? monitor.y : 0) + origin.y;
                // One entry per listed window, so concatenated grids stay paired
                // with their windows even when a crowded grid has no layout.
                var layout = overviewArea.windowLayout;
                return overviewWindow.screenToplevels.map(function (top, index) {
                    var rect = layout[index];
                    return rect ? Qt.rect(offsetX + rect.x, offsetY + rect.y, rect.width, rect.height) : null;
                });
            }
            // A Repeater over a JS array rebuilds every delegate when the array
            // is reassigned, and with it every screencopy capture and layer
            // texture. Cards are therefore created from every window on this
            // screen and only hidden by the filter, and the list is reassigned
            // solely when its membership changes.
            readonly property var cardToplevelsSource: {
                var revision = root.modelRevision;
                return root.toplevelsOnScreen(String(modelData.name || ""));
            }
            property var cardToplevels: []

            function syncCardToplevels() {
                if (!root.toplevelListsEqual(overviewWindow.cardToplevels, overviewWindow.cardToplevelsSource))
                    overviewWindow.cardToplevels = overviewWindow.cardToplevelsSource;
            }

            onCardToplevelsSourceChanged: overviewWindow.syncCardToplevels()
            Component.onCompleted: overviewWindow.syncCardToplevels()
            // A window's card capture, which its workspace thumbnail draws
            // instead of capturing the window a second time.
            property int cardsRevision: 0
            function captureItemFor(top) {
                var revision = overviewWindow.cardsRevision;
                for (var index = 0; index < cardRepeater.count; index++) {
                    var card = cardRepeater.itemAt(index);
                    // A card outside the layout has no size to draw from.
                    if (card && card.modelData === top) // qmllint disable missing-property
                        return card.inLayout ? card.captureItem : null; // qmllint disable missing-property
                }
                return null;
            }
            readonly property string screenWorkspaceLabel: root.activeWorkspaceLabelForScreen(String(modelData.name || ""))
            readonly property string screenScopeLabel: root.workspaceScopeLabelForScreen(String(modelData.name || ""))

            function focusSettingsCategory() {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.focusSettingsCategory(); // qmllint disable missing-property
            }

            // Keeps focus already on a visible settings control; otherwise the category.
            function focusSettings() {
                var settings = settingsLayerLoader.item;
                if (settings && !settings.holdsFocus()) // qmllint disable missing-property
                    settings.focusSettingsCategory(); // qmllint disable missing-property
            }

            function moveSettingsFocus(forward, wrap) {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.moveSettingsFocus(forward, wrap); // qmllint disable missing-property
            }

            function focusFirstSettingsControl() {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.focusFirstSettingsControl(); // qmllint disable missing-property
            }

            function moveFooterConfirmationFocus(forward, wrap) {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.moveFooterConfirmationFocus(forward, wrap); // qmllint disable missing-property
            }

            onAcceptsKeyboardChanged: {
                if (acceptsKeyboard && root.opened)
                    Qt.callLater(root.focusKeyboardSurface);
                if (acceptsKeyboard && root.settingsOpen)
                    Qt.callLater(overviewWindow.focusSettingsCategory);
            }

            Item {
                anchors.fill: parent
                focus: !overviewWindow.acceptsKeyboard
                Keys.forwardTo: root.opened ? root.overviewKeyboardTargets : []
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: overviewWindow.acceptsKeyboard
                enabled: root.opened
                scale: root.animationStyle === "zoom"
                    ? 0.82 + 0.18 * root.motionProgress
                    : (root.animationStyle === "slide"
                        ? 0.97 + 0.03 * root.motionProgress
                        : (root.animationStyle === "original"
                            ? 0.96 + 0.04 * root.motionProgress
                            : 1))
                transformOrigin: Item.Center
                transform: Translate {
                    x: overviewWindow.width * root.slideOffsetFraction * root.slideVector.x
                    y: overviewWindow.height * root.slideOffsetFraction * root.slideVector.y
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    if (root.settingsOpen
                            && !root.footerHideConfirmationOpen
                            && event.key >= Qt.Key_1
                            && event.key <= Qt.Key_6) {
                        root.settingsCategoryIndex = event.key - Qt.Key_1;
                        Qt.callLater(overviewWindow.focusSettingsCategory);
                        event.accepted = true;
                        return;
                    }
                    if (root.handleSettingsNavigation(event))
                        return;
                    root.handleKey(event);
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.sm
                    spacing: Style.spacing.md

                    Ui.BorderSurface {
                        id: searchBar
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(Style.space(760), overviewWindow.width - Style.space(48))
                        Layout.preferredHeight: Style.space(48)
                        radius: Style.cornerRadius
                        color: Commons.Color.menu.background
                        borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.foreground, Style.normalBorderWidth)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.xl
                            anchors.rightMargin: Style.spacing.xl
                            spacing: Style.spacing.md
                            Text {
                                text: "⌕"
                                textFormat: Text.PlainText
                                color: Commons.Color.menu.text
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.heading
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.filterText || (root.overviewMode === "app-windows"
                                    ? root.appNameFor(root.originToplevel) + " windows · type to filter…"
                                    : "Type to filter windows…")
                                textFormat: Text.PlainText
                                color: Commons.Color.menu.text
                                opacity: root.filterText ? 1 : 0.6
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.heading
                                elide: Text.ElideRight
                            }
                            Text {
                                text: overviewWindow.screenToplevels.length + " windows"
                                textFormat: Text.PlainText
                                color: Commons.Color.menu.text
                                opacity: 0.55
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
                            }

                            ThemeDivider {
                                vertical: true
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: Style.space(24)
                            }

                            Text {
                                Layout.maximumWidth: Style.space(176)
                                text: searchBar.width < Style.space(640)
                                    ? (root.workspaceScope === "all" ? "All" : "WS " + overviewWindow.screenWorkspaceLabel)
                                    : overviewWindow.screenScopeLabel
                                textFormat: Text.PlainText
                                color: Commons.Color.accent
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            ThemedControl {
                                Layout.preferredWidth: Style.space(34)
                                Layout.preferredHeight: Style.space(24)
                                radius: Math.max(0, Style.cornerRadius - Style.spacing.sm)
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "Tab"
                                    textFormat: Text.PlainText
                                    color: Commons.Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                    }

                    Loader {
                        id: workspaceStripLoader
                        Layout.fillWidth: true
                        Layout.leftMargin: Style.space(64)
                        Layout.rightMargin: Style.space(64)
                        Layout.preferredHeight: item ? item.implicitHeight : 0 // qmllint disable missing-property
                        active: root.workspaceStrip
                        visible: active

                        sourceComponent: WorkspaceStrip {
                            controller: root
                            screenName: overviewWindow.screenName
                            screenWidth: overviewWindow.width
                            screenHeight: overviewWindow.height
                            screenX: overviewWindow.monitorX
                            screenY: overviewWindow.monitorY
                            wallpaper: wallpaperSource.source
                            captureItemFor: overviewWindow.captureItemFor
                        }
                    }

                    Item {
                        id: overviewArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property var windowLayout: {
                            var revision = root.modelRevision;
                            var ratios = overviewWindow.screenToplevels.map(function (top) { return root.aspectRatioFor(top); });
                            // The gap leaves room for a hovered card's lift and outline;
                            // more only shrinks the cards on a short display.
                            return GridLayout.computeLayout(ratios, width, height, Style.space(32), Style.spacing.sm, root.windowFooterHeight);
                        }

                        Item {
                            id: cardLayer
                            anchors.fill: parent
                            // The original style grows the whole arrangement out of the
                            // top-left corner. A single transform does that without
                            // resizing any card, so no layout, text elision, or layer
                            // texture is redone per frame.
                            scale: root.animationStyle === "original" && root.motionTarget > 0
                                ? root.motionProgress
                                : 1
                            transformOrigin: Item.TopLeft

                            Repeater {
                                id: cardRepeater
                                model: overviewWindow.cardToplevels
                                onItemAdded: overviewWindow.cardsRevision++
                                onItemRemoved: overviewWindow.cardsRevision++

                                delegate: WindowCard {
                                    controller: root
                                    screenToplevels: overviewWindow.screenToplevels
                                    acceptsKeyboard: overviewWindow.acceptsKeyboard || root.multiMonitorMode === "all-monitors"
                                    workspaceStrip: workspaceStripLoader.item
                                    windowLayout: overviewArea.windowLayout
                                    layoutAreaWidth: overviewArea.width
                                    layoutAreaHeight: overviewArea.height
                                }
                                }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: overviewWindow.screenToplevels.length === 0
                            text: root.filterText
                                ? "No matching windows"
                                : (root.workspaceScope === "current"
                                    ? "No windows on Workspace " + overviewWindow.screenWorkspaceLabel
                                    : "No open windows")
                            textFormat: Text.PlainText
                            color: Commons.Color.menu.text
                            opacity: 0.7
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.display
                            layer.enabled: true
                            layer.effect: BackdropShadow {}
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Style.spacing.xl
                        visible: root.showFooter && overviewWindow.acceptsKeyboard
                        // The hints sit on the backdrop, like the floating card footers.
                        layer.enabled: true
                        layer.effect: BackdropShadow {}

                        Text {
                            text: "← ↑ ↓ → navigate   Space preview   Tab scope   "
                                + (root.workspaceStrip ? "1–0 workspace   " : "")
                                + "Shift+Q close   Enter open   Esc close"
                            textFormat: Text.PlainText
                            color: Commons.Color.menu.text
                            opacity: 0.55
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                            id: settingsControl
                            property bool hovered: false
                            text: "Settings"
                            textFormat: Text.PlainText
                            color: settingsControl.hovered ? Style.hoverStateColor(Commons.Color.menu.text, Commons.Color.accent) : Commons.Color.menu.text
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: settingsControl.hovered = true
                                onExited: settingsControl.hovered = false
                                onClicked: root.openSettings()
                            }
                        }
                    }
                }

                Loader {
                    id: settingsLayerLoader
                    anchors.fill: parent
                    active: root.settingsOpen && overviewWindow.acceptsKeyboard
                    z: 200
                    onLoaded: {
                        if (overviewWindow.acceptsKeyboard)
                            Qt.callLater(overviewWindow.focusSettingsCategory);
                    }

                    sourceComponent: Component {
                        SettingsView {
                            controller: root
                            hostWindow: overviewWindow
                        }
                    }
                }
            }
        }
    }
}
