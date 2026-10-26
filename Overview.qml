import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import qs.Ui as Ui // qmllint disable import
import "GridLayout.js" as GridLayout
import "IconResolver.js" as IconResolver
import "WindowModel.js" as WindowModel
import "ScreenLayout.js" as ScreenLayout
import "SettingsSchema.js" as SettingsSchema

Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property alias windowBorders: compositorBorders
    WindowBorders { id: compositorBorders }
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
    readonly property int backgroundBlur: SettingsSchema.read(root.pluginEntry, "backgroundBlur")
    readonly property int backgroundDim: SettingsSchema.read(root.pluginEntry, "backgroundDim")
    // Off until settings load, so a saved "off" never flashes the corner on.
    readonly property bool hotCornerEnabled: pluginSettings.ready && SettingsSchema.read(root.pluginEntry, "hotCornerEnabled")
    readonly property string hotCornerPosition: SettingsSchema.read(root.pluginEntry, "hotCornerPosition")
    readonly property bool hotCornerOnTop: root.hotCornerPosition.indexOf("top-") === 0
    readonly property bool hotCornerOnLeft: root.hotCornerPosition.indexOf("-left") !== -1
    readonly property bool hotCornerAllDisplays: SettingsSchema.read(root.pluginEntry, "hotCornerAllDisplays")
    readonly property var hotCornerScreens: root.hotCornerEnabled
        ? ScreenLayout.hotCornerScreens(Quickshell.screens,
            Hyprland.monitors ? Hyprland.monitors.values : [],
            root.hotCornerPosition, root.hotCornerAllDisplays)
        : []
    onHotCornerScreensChanged: root.scheduleHotCornerRearm()
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
    property bool opened: false
    property bool surfaceMounted: false
    property bool hotCornerArmed: true
    property string filterText: ""
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
    // Window to focus once the overlay releases the keyboard.
    property var pendingActivation: null
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
    readonly property real effectiveBackgroundDim: root.backgroundDimPreview >= 0 ? root.backgroundDimPreview : root.backgroundDim
    readonly property int effectiveHotCornerDelay: root.hotCornerDelayPreview >= 0 ? Math.round(root.hotCornerDelayPreview) : root.hotCornerDelay
    readonly property int previewAnimationDuration: root.previewSlowMotion || root.previewNavigationSlowMotion ? 4000 : 190
    readonly property int previewFadeDuration: root.previewSlowMotion || root.previewNavigationSlowMotion ? 4000 : 130
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
    // Only the selected display creates cards and screencopy captures.
    readonly property var mountedScreens: {
        if (!root.surfaceMounted || !root.effectiveOverviewScreen)
            return [];
        return [root.effectiveOverviewScreen];
    }
    readonly property var backdropScreens: {
        if (!root.surfaceMounted)
            return [];
        return Quickshell.screens.filter(function (screen) {
            return screen !== root.effectiveOverviewScreen;
        });
    }
    readonly property var overviewKeyboardTargets: surfaceInstances.instances.length
        ? surfaceInstances.instances[0].keyboardTargets
        : []
    readonly property var filteredToplevels: {
        var revision = root.modelRevision;
        return root.toplevelsForScreen(root.keyboardScreenName);
    }
    // What Enter opens.
    readonly property var selection: WindowModel.selectionFor(root.filteredToplevels, root.selectedToplevel, root.originToplevel)

    onMultiMonitorModeChanged: {
        root.hoveredToplevel = null;
        root.clearPreview();
        root.modelRevision++;
        root.selectedToplevel = root.originToplevel;
    }

    onEffectiveBackgroundBlurChanged: {
        if (!root.surfaceMounted)
            return;
        if (!backgroundBlurSession.running && root.effectiveBackgroundBlur > 0 && !root.backgroundBlurFailed) {
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
        compositorBorders.refresh();
        var blurRestoreInFlight = root.backgroundBlurReleasePhase === 1 && backgroundBlurSession.running;
        if (!blurRestoreInFlight)
            root.backgroundBlurReleasePhase = 0;
        root.closeSettings();
        root.filterText = "";
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
        if (root.effectiveBackgroundBlur > 0) {
            if (!blurRestoreInFlight)
                backgroundBlurSession.running = true;
        } else {
            root.prepareOpenSurface();
        }
    }

    function close() {
        root.startDismiss(false);
    }

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
        (root.opened || root.openingPending) ? root.dismiss() : root.open("{}");
    }

    function requestedBackgroundBlur() {
        return Math.max(0, Math.round(root.effectiveBackgroundBlur));
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
        if (root.effectiveBackgroundBlur > 0 && !root.backgroundBlurFailed) {
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
        if (distance < 0.001) {
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
        if (root.pendingActivation)
            root.dispatchPendingActivation();
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
                if (instances[index] && instances[index].hotCornerHovered)
                    return true;
        }
        return false;
    }

    function triggerHotCorner(screenName) {
        if (!root.hotCornerEnabled || !root.hotCornerArmed)
            return;
        root.hotCornerArmed = false;
        if (root.opened || root.openingPending) {
            root.dismiss();
            return;
        }
        var name = String(screenName || "");
        if (name) {
            root.overviewScreenPinned = true;
            root.overviewScreenName = name;
        }
        root.open("{}");
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
        var surface = root.keyboardSurface();
        if (surface)
            root.moveDirectional(dx, dy, surface.windowLayout, false);
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
        if (root.openingPending) {
            var sessionIndex = root.sessionToplevels.indexOf(top);
            if (sessionIndex >= 0) {
                var ratios = root.sessionAspectRatios.slice();
                ratios[sessionIndex] = root.liveAspectRatioFor(top);
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
        root.pendingActivation = top;
        root.dismiss();
    }

    // Runs once a surface has lost the keyboard, or once the surfaces are gone
    // if none held it. When an exclusive-keyboard layer lets go, Hyprland
    // returns focus to the previous window, overriding any earlier request.
    function dispatchPendingActivation() {
        var address = WindowModel.addressFor(root.pendingActivation);
        root.pendingActivation = null;
        if (!address)
            return;
        var focus = "hl.dispatch(hl.dsp.focus({ window = 'address:" + address + "' }))";
        Hyprland.dispatch(root.moveCursorToWindow
            ? "(function() " + focus + " end)"
            : "(function() local p = hl.get_cursor_pos(); " + focus
                + "; hl.dispatch(hl.dsp.cursor.move({ x = p.x, y = p.y })) end)");
    }

    function requestClose(top) {
        var wayland = WindowModel.waylandFor(top);
        if (!wayland || typeof wayland.close !== "function")
            return;
        wayland.close();
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
        if (root.multiMonitorMode === "per-monitor") {
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
        return WindowModel.isOnScreen(top, screenName, root.multiMonitorMode === "per-monitor");
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

    function moveDirectional(dx, dy, layout, slowMotion) {
        var bestIndex = GridLayout.neighbourIndex(layout, root.filteredToplevels.indexOf(root.selection), dx, dy);
        if (bestIndex < 0)
            return;

        var previousPreview = root.previewToplevel;
        var next = root.filteredToplevels[bestIndex];
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

    function handleKey(event, layout) {
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
            if (root.previewToplevel || root.previewExitToplevel)
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
            root.moveDirectional(-1, 0, layout, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Right)
            root.moveDirectional(1, 0, layout, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Up)
            root.moveDirectional(0, -1, layout, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Down)
            root.moveDirectional(0, 1, layout, Boolean(event.modifiers & Qt.ShiftModifier));
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.activate(root.selection);
        else if (event.key === Qt.Key_Q
                && Boolean(event.modifiers & Qt.ShiftModifier)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (!event.isAutoRepeat)
                root.requestClose(root.selection);
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
            if (event && event.name === "configreloaded")
                compositorBorders.refresh();
            if (event && event.name === "custom" && event.data === "expose.window-overview:toggle")
                root.toggle();
        }
    }

    IpcHandler {
        target: "expose"
        function open(): string {
            // Must not be root.toggle(): that makes "open" a duplicate of
            // "toggle", so calling open on an already-open overview closes it.
            // Mirrors close(), which correctly calls dismiss().
            root.open("{}");
            return "ok";
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
        function backgroundBlur(value: real): string { return root.setSettingFromIpc("backgroundBlur", value); }
        function backgroundDim(value: real): string { return root.setSettingFromIpc("backgroundDim", value); }
        function showFooter(mode: string): string { return root.setSettingFromIpc("showFooter", mode); }
        function initialWorkspaceScope(scope: string): string { return root.setSettingFromIpc("initialWorkspaceScope", scope); }
        function workspaceLabelStyle(style: string): string { return root.setSettingFromIpc("workspaceLabelStyle", style); }
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
                windows: open ? root.filteredToplevels.length : 0,
                selection: top ? root.windowLabel(top) : null,
                selectionAddress: top ? WindowModel.addressFor(top) : null,
                preview: root.previewToplevel !== null
            });
        }
        function get(name: string): string {
            if (!Object.prototype.hasOwnProperty.call(SettingsSchema.specs, name))
                return SettingsSchema.expectedOneOf(Object.keys(SettingsSchema.specs));
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
        function hotCornerDelay(value: real): string { return root.setSettingFromIpc("hotCornerDelay", value); }
        function hotCornerAllDisplays(mode: string): string { return root.setSettingFromIpc("hotCornerAllDisplays", mode); }
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

    // Full-screen surfaces take over corner handling while Exposé is mounted.
    Variants {
        id: hotCornerInstances
        model: root.hotCornerScreens

        PanelWindow { // qmllint disable uncreatable-type
            required property var modelData
            screen: modelData
            visible: !root.surfaceMounted
            anchors {
                top: root.hotCornerOnTop
                right: !root.hotCornerOnLeft
                bottom: !root.hotCornerOnTop
                left: root.hotCornerOnLeft
            }
            implicitWidth: root.hotCornerReach
            implicitHeight: root.hotCornerReach
            color: "#02000000"
            mask: Region {
                Region {
                    x: 0
                    y: root.hotCornerOnTop ? 0 : root.hotCornerReach - root.hotCornerDepth
                    width: root.hotCornerReach
                    height: root.hotCornerDepth
                }
                Region {
                    x: root.hotCornerOnLeft ? 0 : root.hotCornerReach - root.hotCornerDepth
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
            readonly property bool hotCornerHovered: closedHotCorner.hovered

            HotCornerTarget {
                id: closedHotCorner
                anchors.fill: parent
                enabled: !root.surfaceMounted
                onTop: root.hotCornerOnTop
                onLeft: root.hotCornerOnLeft
                onEntered: root.triggerHotCorner(String(modelData.name || ""))
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
        BackgroundEffect.blurRegion: root.effectiveBackgroundBlur > 0 // qmllint disable missing-type
                && !root.backgroundBlurFailed
            ? backgroundBlurRegion
            : null
        readonly property bool hotCornerHovered: openHotCorner.hovered

        Region {
            id: backgroundBlurRegion
            item: surface.contentItem
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
                if (!Window.active && root.pendingActivation)
                    root.dispatchPendingActivation();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                if (surface.modelData === root.effectiveOverviewScreen
                        && (root.previewToplevel || root.previewExitToplevel))
                    root.clearPreview();
                else
                    root.dismiss();
            }
            onWheel: function (wheel) { wheel.accepted = true; }
        }

        HotCornerTarget {
            id: openHotCorner
            width: root.hotCornerReach
            height: root.hotCornerReach
            x: root.hotCornerOnLeft ? 0 : parent.width - width
            y: root.hotCornerOnTop ? 0 : parent.height - height
            z: 100
            enabled: root.surfaceMounted && root.hotCornerScreens.indexOf(surface.modelData) !== -1
            onTop: root.hotCornerOnTop
            onLeft: root.hotCornerOnLeft
            onEntered: root.triggerHotCorner(String(surface.modelData.name || ""))
            onExited: root.scheduleHotCornerRearm()
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
                if (acceptsKeyboard && root.settingsOpen)
                    Qt.callLater(overviewWindow.focusSettingsCategory);
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
                    root.handleKey(event, overviewArea.windowLayout);
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
                                text: root.filterText || "Type to filter windows…"
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

                    Item {
                        id: overviewArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property var windowLayout: {
                            var revision = root.modelRevision;
                            var ratios = overviewWindow.screenToplevels.map(function (top) { return root.aspectRatioFor(top); });
                            return GridLayout.computeLayout(ratios, width, height, Style.space(64), Style.spacing.sm, root.windowFooterHeight);
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
                                model: overviewWindow.cardToplevels

                                delegate: WindowCard {
                                    controller: root
                                    screenToplevels: overviewWindow.screenToplevels
                                    acceptsKeyboard: overviewWindow.acceptsKeyboard
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
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Style.spacing.xl
                        visible: root.showFooter

                        Text {
                            text: "← ↑ ↓ → navigate   Space preview   Tab scope   Shift+Q close   Enter open   Esc close"
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
                    active: root.settingsOpen
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
