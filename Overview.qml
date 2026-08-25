import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "IconResolver.js" as IconResolver
import "WindowModel.js" as WindowModel

Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property string pluginId: String((root.manifest && root.manifest.id) || "expose.window-overview")
    readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir)
        || (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId))
    readonly property var pluginEntry: {
        var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null;
        var plugins = config && Array.isArray(config.plugins) ? config.plugins : [];
        for (var i = 0; i < plugins.length; i++)
            if (plugins[i] && String(plugins[i].id || "") === root.pluginId)
                return plugins[i];
        return null;
    }
    readonly property string previewPlacement: root.pluginEntry && root.pluginEntry.previewPlacement === "centered" ? "centered" : "in-place"
    readonly property var windowFooterStyles: ["floating", "integrated", "overlay", "centered"]
    readonly property string windowFooterStyle: {
        var style = String((root.pluginEntry && root.pluginEntry.windowFooterStyle) || "floating");
        return root.windowFooterStyles.indexOf(style) !== -1 ? style : "floating";
    }
    readonly property var animationStyles: ["original", "fade", "zoom", "slide"]
    readonly property string animationStyle: {
        var style = String((root.pluginEntry && root.pluginEntry.animationStyle) || "original");
        return root.animationStyles.indexOf(style) !== -1 ? style : "original";
    }
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
    readonly property int backgroundBlur: {
        var raw = root.pluginEntry ? root.pluginEntry.backgroundBlur : undefined;
        var value = raw === null || raw === undefined ? NaN : Number(raw);
        return isFinite(value) ? Math.max(0, Math.min(20, Math.round(value))) : 4;
    }
    readonly property int backgroundDim: {
        var raw = root.pluginEntry ? root.pluginEntry.backgroundDim : undefined;
        var value = raw === null || raw === undefined ? NaN : Number(raw);
        return isFinite(value) ? Math.max(0, Math.min(90, Math.round(value))) : 6;
    }
    readonly property bool hotCornerEnabled: !root.pluginEntry || root.pluginEntry.hotCornerEnabled !== false
    readonly property string hotCornerPosition: {
        var position = String((root.pluginEntry && root.pluginEntry.hotCornerPosition) || "top-left");
        return ["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(position) !== -1
            ? position
            : "top-left";
    }
    readonly property bool hotCornerOnTop: root.hotCornerPosition.indexOf("top-") === 0
    readonly property bool hotCornerOnLeft: root.hotCornerPosition.indexOf("-left") !== -1
    // Reach farther along both screen edges than into the desktop. Fast flings
    // are easier to catch without stealing a large square from the bar below.
    readonly property int hotCornerReach: Style.space(48)
    readonly property int hotCornerDepth: Style.space(6)
    readonly property bool moveCursorToWindow: !root.pluginEntry || root.pluginEntry.moveCursorToWindow !== false
    readonly property string multiMonitorMode: root.pluginEntry && root.pluginEntry.multiMonitorMode === "per-monitor"
        ? "per-monitor"
        : "mirrored"
    readonly property bool showFooter: !root.pluginEntry || root.pluginEntry.showFooter !== false
    property bool opened: false
    property bool surfaceMounted: false
    property bool hotCornerArmed: true
    property string filterText: ""
    property string workspaceScope: "all"
    property int selectedIndex: 0
    property int hoveredIndex: -1
    property int previewIndex: -1
    property int previewExitIndex: -1
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
    readonly property real effectiveBackgroundBlur: root.backgroundBlurPreview >= 0 ? root.backgroundBlurPreview : root.backgroundBlur
    readonly property real effectiveBackgroundDim: root.backgroundDimPreview >= 0 ? root.backgroundDimPreview : root.backgroundDim
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
    // One overlay surface: the focused monitor, or the display whose hot
    // corner opened Exposé. Instantiating on every enabled output duplicates
    // screencopy captures and layer textures.
    readonly property var mountedScreens: {
        if (!root.surfaceMounted || !root.effectiveOverviewScreen)
            return [];
        return [root.effectiveOverviewScreen];
    }
    readonly property var filteredToplevels: {
        var revision = root.modelRevision;
        return root.toplevelsForScreen(root.keyboardScreenName);
    }

    onMultiMonitorModeChanged: {
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(Hyprland.activeToplevel));
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
        var blurRestoreInFlight = root.backgroundBlurReleasePhase === 1 && backgroundBlurSession.running;
        if (!blurRestoreInFlight)
            root.backgroundBlurReleasePhase = 0;
        root.closeSettings();
        root.filterText = "";
        root.workspaceScope = "all";
        root.dismissNotifyShell = false;
        if (root.surfaceMounted) {
            if (blurRestoreInFlight) {
                root.openingPending = true;
                return;
            }
            root.opened = true;
            root.animateMotionTo(1);
            root.refreshHyprlandState();
            Qt.callLater(root.focusKeyboardWindow);
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
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(Hyprland.activeToplevel));
        root.hoveredIndex = -1;
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
        root.hoveredIndex = -1;
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
            root.focusKeyboardWindow();
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
            Qt.callLater(root.focusKeyboardWindow);
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
    }

    function finishDismiss() {
        var notifyShell = root.dismissNotifyShell;
        root.dismissNotifyShell = false;
        if (notifyShell && root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId);
    }

    function updatePluginSetting(name, value) {
        if (!root.shell || typeof root.shell.updateEntryInline !== "function")
            return;
        var settings = {};
        var current = root.pluginEntry || {};
        for (var key in current)
            if (key !== "id")
                settings[key] = current[key];
        settings[name] = value;
        root.shell.updateEntryInline(root.pluginId, settings);
    }

    function setPreviewPlacement(value) {
        var mode = value === "centered" ? "centered" : "in-place";
        if (mode !== root.previewPlacement)
            root.updatePluginSetting("previewPlacement", mode);
    }

    function setWindowFooterStyle(value) {
        var style = root.windowFooterStyles.indexOf(value) !== -1 ? value : "floating";
        if (style !== root.windowFooterStyle)
            root.updatePluginSetting("windowFooterStyle", style);
    }

    function setAnimationStyle(value) {
        var style = root.animationStyles.indexOf(value) !== -1 ? value : "original";
        if (style !== root.animationStyle)
            root.updatePluginSetting("animationStyle", style);
        return style;
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
        return Object.prototype.hasOwnProperty.call(root.slideVectors, direction);
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

    function setBackgroundBlur(value) {
        var numeric = Number(value);
        if (!isFinite(numeric))
            return root.backgroundBlur;
        var next = Math.max(0, Math.min(20, Math.round(numeric)));
        if (next !== root.backgroundBlur)
            root.updatePluginSetting("backgroundBlur", next);
        return next;
    }

    function setBackgroundDim(value) {
        var numeric = Number(value);
        if (!isFinite(numeric))
            return root.backgroundDim;
        var next = Math.max(0, Math.min(90, Math.round(numeric)));
        if (next !== root.backgroundDim)
            root.updatePluginSetting("backgroundDim", next);
        return next;
    }

    function openSettings() {
        if (!root.surfaceMounted)
            root.open("{}");
        root.closeFooterHideConfirmation();
        root.clearAnimationTimingPreview();
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        root.settingsCategoryIndex = 0;
        root.settingsOpen = true;
        Qt.callLater(function () {
            if (root.settingsOpen)
                root.focusSettingsCategory();
        });
    }

    function closeSettings() {
        var restoreKeyboardFocus = root.settingsOpen && root.opened;
        root.closeFooterHideConfirmation();
        root.settingsOpen = false;
        root.clearAnimationTimingPreview();
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        if (restoreKeyboardFocus)
            Qt.callLater(function () {
                if (root.opened)
                    root.focusKeyboardWindow();
            });
    }

    function clearPreview() {
        previewExitTimer.stop();
        root.previewSlowMotion = false;
        root.previewNavigationSlowMotion = false;
        root.previewIndex = -1;
        root.previewExitIndex = -1;
    }

    function setHotCornerEnabled(enabled) {
        var next = enabled === true;
        if (next !== root.hotCornerEnabled)
            root.updatePluginSetting("hotCornerEnabled", next);
    }

    function setHotCornerPosition(value) {
        var positions = ["top-left", "top-right", "bottom-left", "bottom-right"];
        var position = positions.indexOf(value) !== -1 ? value : "top-left";
        if (position !== root.hotCornerPosition)
            root.updatePluginSetting("hotCornerPosition", position);
    }

    function setMoveCursorToWindow(enabled) {
        var next = enabled === true;
        if (next !== root.moveCursorToWindow)
            root.updatePluginSetting("moveCursorToWindow", next);
    }

    function setMultiMonitorMode(value) {
        var mode = value === "per-monitor" ? "per-monitor" : "mirrored";
        if (mode !== root.multiMonitorMode)
            root.updatePluginSetting("multiMonitorMode", mode);
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
        var groups = [hotCornerInstances, surfaceInstances];
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

    function focusKeyboardWindow() {
        for (var i = 0; i < surfaceInstances.instances.length; i++) {
            var surface = surfaceInstances.instances[i];
            if (surface && surface.acceptsKeyboard) {
                surface.keyboardItem.forceActiveFocus();
                return;
            }
        }
    }

    function focusSettingsCategory() {
        for (var i = 0; i < surfaceInstances.instances.length; i++) {
            var surface = surfaceInstances.instances[i];
            if (surface && surface.acceptsKeyboard) {
                surface.focusSettingsCategory();
                return;
            }
        }
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
        for (var index = 0; index < surfaceInstances.instances.length; index++) {
            var surface = surfaceInstances.instances[index];
            if (!surface || !surface.acceptsKeyboard)
                continue;
            if (root.footerHideConfirmationOpen)
                surface.moveFooterConfirmationFocus(forward, isTab);
            else
                surface.moveSettingsFocus(forward, isTab);
            event.accepted = true;
            return true;
        }
        return false;
    }

    function handleSettingsTab(event) {
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return false;
        return root.handleSettingsNavigation(event);
    }

    function setFilter(value) {
        root.filterText = value;
        root.selectedIndex = 0;
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
    }

    function setWorkspaceScope(value) {
        var next = value === "current" ? "current" : "all";
        if (next === "current" && !root.workspaceForScreen(root.keyboardScreenName))
            return;
        if (next === root.workspaceScope)
            return;
        root.workspaceScope = next;
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(Hyprland.activeToplevel));
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
        var selectedTop = root.filteredToplevels[root.selectedIndex];
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
        var nextIndex = root.filteredToplevels.indexOf(selectedTop);
        root.selectedIndex = nextIndex >= 0 ? nextIndex : Math.max(0, root.filteredToplevels.indexOf(Hyprland.activeToplevel));
    }

    function handleToplevelMetadataChanged(top) {
        if (!root.surfaceMounted && !root.openingPending)
            return;
        var selectedTop = root.filteredToplevels[root.selectedIndex];
        var previewTop = root.previewIndex >= 0 ? root.filteredToplevels[root.previewIndex] : null;
        var previewExitTop = root.previewExitIndex >= 0 ? root.filteredToplevels[root.previewExitIndex] : null;
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

        var selectedIndex = root.filteredToplevels.indexOf(selectedTop);
        if (selectedIndex < 0)
            selectedIndex = root.filteredToplevels.indexOf(Hyprland.activeToplevel);
        root.selectedIndex = Math.max(0, selectedIndex);

        if (previewTop) {
            var previewIndex = root.filteredToplevels.indexOf(previewTop);
            if (previewIndex < 0)
                root.clearPreview();
            else
                root.previewIndex = previewIndex;
        } else if (previewExitTop) {
            var previewExitIndex = root.filteredToplevels.indexOf(previewExitTop);
            if (previewExitIndex < 0)
                root.clearPreview();
            else
                root.previewExitIndex = previewExitIndex;
        }
    }

    function handleToplevelCollectionChanged() {
        if (!root.surfaceMounted && !root.openingPending)
            return;
        var membershipChanged = root.syncSessionToplevels();
        var filteredMembershipMayChange = !membershipChanged && root.filterText.length > 0;
        if ((membershipChanged || filteredMembershipMayChange)
                && (root.previewIndex >= 0 || root.previewExitIndex >= 0))
            root.clearPreview();
        if (filteredMembershipMayChange)
            root.modelRevision++;
        if (root.selectedIndex >= root.filteredToplevels.length)
            root.selectedIndex = Math.max(0, root.filteredToplevels.length - 1);
        if (root.previewIndex >= root.filteredToplevels.length)
            root.clearPreview();
    }

    function activate(top) {
        if (!top)
            return;
        var helper = root.pluginDir + "/activate-window";
        Quickshell.execDetached([
            helper,
            WindowModel.addressFor(top),
            WindowModel.appIdFor(top),
            String(top.title || ""),
            root.moveCursorToWindow ? "true" : "false"
        ]);
        root.dismiss();
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

    function workspaceName(top) {
        return WindowModel.workspaceName(top);
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
        return String(workspace.name || workspace.id || "—");
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

    function assignCompositionRows(entries, rowCount) {
        var rows = [];
        for (var rowIndex = 0; rowIndex < rowCount; rowIndex++)
            rows.push({ entries: [], naturalWidth: 0 });

        var ordered = entries.slice();
        ordered.sort(function (a, b) {
            var widthA = Math.sqrt(a.weight * a.ratio);
            var widthB = Math.sqrt(b.weight * b.ratio);
            if (widthA !== widthB)
                return widthB - widthA;
            return a.index - b.index;
        });

        for (var entryIndex = 0; entryIndex < ordered.length; entryIndex++) {
            var bestRow = 0;
            for (var candidateRow = 1; candidateRow < rows.length; candidateRow++) {
                if (rows[candidateRow].naturalWidth < rows[bestRow].naturalWidth
                        || (rows[candidateRow].naturalWidth === rows[bestRow].naturalWidth
                            && rows[candidateRow].entries.length < rows[bestRow].entries.length))
                    bestRow = candidateRow;
            }
            var entry = ordered[entryIndex];
            rows[bestRow].entries.push(entry);
            rows[bestRow].naturalWidth += Math.sqrt(entry.weight * entry.ratio);
        }

        for (var sortRow = 0; sortRow < rows.length; sortRow++)
            rows[sortRow].entries.sort(function (a, b) { return a.index - b.index; });
        return rows;
    }

    function composeRows(rows, scale, width, height, gap, padding, footerHeight) {
        var measuredRows = [];
        var totalHeight = 0;
        var footerSpacing = footerHeight > 0 ? padding : 0;
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
            var entries = rows[rowIndex].entries;
            var cards = [];
            var totalWidth = Math.max(0, entries.length - 1) * gap;
            var rowHeight = 0;
            for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
                var entry = entries[entryIndex];
                var previewWidth = scale * Math.sqrt(entry.weight * entry.ratio);
                var previewHeight = scale * Math.sqrt(entry.weight / entry.ratio);
                var card = {
                    index: entry.index,
                    width: previewWidth + padding * 2,
                    height: previewHeight + footerHeight + padding * 2 + footerSpacing
                };
                cards.push(card);
                totalWidth += card.width;
                rowHeight = Math.max(rowHeight, card.height);
            }
            if (totalWidth > width || rowHeight > height)
                return null;
            measuredRows.push({ cards: cards, width: totalWidth, height: rowHeight });
            totalHeight += rowHeight;
        }
        totalHeight += Math.max(0, measuredRows.length - 1) * gap;
        if (totalHeight > height)
            return null;

        var verticalGap = measuredRows.length > 1 ? gap : 0;
        var y = (height - totalHeight) / 2;
        var result = [];
        for (var outputRow = 0; outputRow < measuredRows.length; outputRow++) {
            var row = measuredRows[outputRow];
            var horizontalGap = row.cards.length > 1 ? gap : 0;
            var x = (width - row.width) / 2;
            for (var cardIndex = 0; cardIndex < row.cards.length; cardIndex++) {
                var card = row.cards[cardIndex];
                var align = ((card.index + outputRow) % 3) / 2;
                result[card.index] = {
                    x: x,
                    y: y + (row.height - card.height) * align,
                    width: card.width,
                    height: card.height
                };
                x += card.width + horizontalGap;
            }
            y += row.height + verticalGap;
        }
        return result;
    }

    function computeWindowLayout(toplevels, width, height, gap, padding, footerHeight, viewportRatioHint) {
        var count = toplevels.length;
        if (!count || width <= 0 || height <= 0)
            return [];

        var edgeInset = gap / 2;
        var availableWidth = Math.max(1, width - edgeInset * 2);
        var availableHeight = Math.max(1, height - edgeInset * 2);
        var entries = [];
        for (var index = 0; index < count; index++) {
            var ratio = root.aspectRatioFor(toplevels[index]);
            var adaptiveWeight = Math.max(0.72, Math.min(1.28, Math.sqrt(ratio / 1.6)));
            entries.push({
                index: index,
                ratio: ratio,
                weight: adaptiveWeight,
                extremity: Math.max(ratio, 1 / ratio)
            });
        }
        entries.sort(function (a, b) {
            if (a.extremity !== b.extremity)
                return b.extremity - a.extremity;
            return a.index - b.index;
        });

        var high = Math.min(availableWidth, availableHeight);
        var footerSpacing = footerHeight > 0 ? padding : 0;
        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            var entry = entries[entryIndex];
            high = Math.min(high,
                (availableWidth - padding * 2) / Math.sqrt(entry.weight * entry.ratio),
                (availableHeight - footerHeight - padding * 2 - footerSpacing) / Math.sqrt(entry.weight / entry.ratio));
        }
        high = Math.max(1, high);

        var best = null;
        var bestScale = -1;
        var minimumCardHeight = footerHeight + padding * 2 + footerSpacing + 1;
        var maxRows = Math.max(1, Math.min(count, Math.floor((availableHeight + gap) / (minimumCardHeight + gap))));
        var totalNaturalWidth = 0;
        var totalNaturalHeight = 0;
        for (var naturalIndex = 0; naturalIndex < entries.length; naturalIndex++) {
            totalNaturalWidth += Math.sqrt(entries[naturalIndex].weight * entries[naturalIndex].ratio);
            totalNaturalHeight += Math.sqrt(entries[naturalIndex].weight / entries[naturalIndex].ratio);
        }
        var averageNaturalHeight = totalNaturalHeight / entries.length;
        var viewportRatio = Number(viewportRatioHint);
        if (!isFinite(viewportRatio) || viewportRatio <= 0)
            viewportRatio = availableWidth / availableHeight;
        var balancedRows = Math.round(Math.sqrt(totalNaturalWidth / Math.max(0.01, viewportRatio * averageNaturalHeight)));
        var minimumRows = Math.max(1, Math.min(maxRows, balancedRows));
        for (var rowCount = minimumRows; rowCount <= maxRows; rowCount++) {
            var rows = root.assignCompositionRows(entries, rowCount);
            var low = 0;
            var rowHigh = high;
            var rowBest = null;
            for (var iteration = 0; iteration < 12; iteration++) {
                var scale = (low + rowHigh) / 2;
                var composed = root.composeRows(rows, scale, availableWidth, availableHeight, gap, padding, footerHeight);
                if (composed) {
                    rowBest = composed;
                    low = scale;
                } else {
                    rowHigh = scale;
                }
            }
            if (rowBest && low > bestScale) {
                best = rowBest;
                bestScale = low;
            }
        }
        if (!best)
            best = root.composeRows(root.assignCompositionRows(entries, 1), 1, availableWidth, availableHeight, gap, padding, footerHeight) || [];
        for (var resultIndex = 0; resultIndex < best.length; resultIndex++) {
            if (!best[resultIndex])
                continue;
            best[resultIndex].x += edgeInset;
            best[resultIndex].y += edgeInset;
        }
        return best;
    }

    function previewRectFor(top, sourceRect, width, height, padding, footerHeight) {
        var ratio = root.aspectRatioFor(top);
        var maxWidth = width * 0.84;
        var maxHeight = height * 0.78;
        var footerSpacing = footerHeight > 0 ? padding : 0;
        var previewWidth = Math.max(1, Math.min(maxWidth - padding * 2, (maxHeight - footerHeight - padding * 2 - footerSpacing) * ratio));
        var previewHeight = Math.max(1, previewWidth / ratio);
        var cardWidth = previewWidth + padding * 2;
        var cardHeight = previewHeight + footerHeight + padding * 2 + footerSpacing;
        var centerX = width / 2;
        var centerY = height / 2;
        if (root.previewPlacement === "in-place" && sourceRect) {
            centerX = sourceRect.x + sourceRect.width / 2;
            centerY = sourceRect.y + sourceRect.height / 2;
        }
        return {
            x: Math.max(padding, Math.min(width - cardWidth - padding, centerX - cardWidth / 2)),
            y: Math.max(padding, Math.min(height - cardHeight - padding, centerY - cardHeight / 2)),
            width: cardWidth,
            height: cardHeight
        };
    }

    function moveDirectional(dx, dy, layout, slowMotion) {
        if (!layout || !layout[root.selectedIndex])
            return;
        var current = layout[root.selectedIndex];
        var currentX = current.x + current.width / 2;
        var currentY = current.y + current.height / 2;
        var bestIndex = -1;
        var bestScore = Number.MAX_VALUE;
        for (var index = 0; index < layout.length; index++) {
            if (index === root.selectedIndex || !layout[index])
                continue;
            var candidate = layout[index];
            var deltaX = candidate.x + candidate.width / 2 - currentX;
            var deltaY = candidate.y + candidate.height / 2 - currentY;
            var primary = dx !== 0 ? deltaX * dx : deltaY * dy;
            if (primary <= 0)
                continue;
            var cross = dx !== 0 ? Math.abs(deltaY) : Math.abs(deltaX);
            var score = primary + cross * cross / Math.max(1, primary) * 2;
            if (score < bestScore) {
                bestScore = score;
                bestIndex = index;
            }
        }
        if (bestIndex < 0)
            return;

        var previousPreviewIndex = root.previewIndex;
        root.selectedIndex = bestIndex;
        if (previousPreviewIndex >= 0) {
            root.previewSlowMotion = false;
            root.previewNavigationSlowMotion = slowMotion === true;
            previewExitTimer.stop();
            root.previewExitIndex = previousPreviewIndex;
            root.previewIndex = bestIndex;
            previewExitTimer.restart();
        }
    }

    function togglePreview(slowMotion) {
        root.previewNavigationSlowMotion = false;
        root.previewSlowMotion = slowMotion === true;
        if (root.previewIndex >= 0) {
            root.previewExitIndex = root.previewIndex;
            root.previewIndex = -1;
            previewExitTimer.restart();
            return;
        }
        previewExitTimer.stop();
        root.previewExitIndex = -1;
        var target = root.hoveredIndex >= 0 ? root.hoveredIndex : root.selectedIndex;
        if (target >= 0 && target < root.filteredToplevels.length) {
            root.selectedIndex = target;
            root.previewIndex = target;
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
            if (root.previewIndex >= 0 || root.previewExitIndex >= 0)
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
            root.activate(root.filteredToplevels[root.selectedIndex]);
        else if (event.key === Qt.Key_Q
                && Boolean(event.modifiers & Qt.ShiftModifier)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (!event.isAutoRepeat)
                root.requestClose(root.filteredToplevels[root.selectedIndex]);
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
            root.previewExitIndex = -1;
            root.previewNavigationSlowMotion = false;
            if (root.previewIndex < 0)
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
        onExited: function (exitCode, exitStatus) {
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
            if (!root.opened)
                return;
            var index = root.filteredToplevels.indexOf(Hyprland.activeToplevel);
            if (index >= 0)
                root.selectedIndex = index;
        }
        function onRawEvent(event) {
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
        function previewPlacement(mode: string): string {
            if (mode !== "in-place" && mode !== "centered")
                return "expected in-place or centered";
            root.setPreviewPlacement(mode);
            return mode;
        }
        function windowFooterStyle(style: string): string {
            if (root.windowFooterStyles.indexOf(style) === -1)
                return "expected floating, integrated, overlay, or centered";
            root.setWindowFooterStyle(style);
            return style;
        }
        function animationStyle(style: string): string {
            if (root.animationStyles.indexOf(style) === -1)
                return "expected original, fade, zoom, or slide";
            return root.setAnimationStyle(style);
        }
        function animationDuration(style: string, value: real): string {
            if (root.animationStyles.indexOf(style) === -1)
                return "expected original, fade, zoom, or slide";
            return String(root.setAnimationDuration(style, value));
        }
        function animationDurationIn(style: string, value: real): string {
            if (root.animationStyles.indexOf(style) === -1)
                return "expected original, fade, zoom, or slide";
            return String(root.setAnimationDurationIn(style, value));
        }
        function animationDurationOut(style: string, value: real): string {
            if (root.animationStyles.indexOf(style) === -1)
                return "expected original, fade, zoom, or slide";
            return String(root.setAnimationDurationOut(style, value));
        }
        function slideDirection(direction: string): string {
            if (!root.isSlideDirection(direction))
                return "expected left, right, up, or down";
            return root.setSlideDirection(direction);
        }
        function slideDirectionIn(direction: string): string {
            if (!root.isSlideDirection(direction))
                return "expected left, right, up, or down";
            return root.setSlideDirectionIn(direction);
        }
        function slideDirectionOut(direction: string): string {
            if (!root.isSlideDirection(direction))
                return "expected left, right, up, or down";
            return root.setSlideDirectionOut(direction);
        }
        function backgroundBlur(value: real): string {
            return String(root.setBackgroundBlur(value));
        }
        function backgroundDim(value: real): string {
            return String(root.setBackgroundDim(value));
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
        function hotCorner(mode: string): string {
            if (mode !== "on" && mode !== "off")
                return "expected on or off";
            root.setHotCornerEnabled(mode === "on");
            return mode;
        }
        function hotCornerPosition(position: string): string {
            if (["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(position) === -1)
                return "expected top-left, top-right, bottom-left, or bottom-right";
            root.setHotCornerPosition(position);
            return position;
        }
        function moveCursorToWindow(mode: string): string {
            if (mode !== "on" && mode !== "off")
                return "expected on or off";
            root.setMoveCursorToWindow(mode === "on");
            return mode;
        }
        function multiMonitorMode(mode: string): string {
            if (mode !== "mirrored" && mode !== "per-monitor")
                return "expected mirrored or per-monitor";
            root.setMultiMonitorMode(mode);
            return mode;
        }
    }

    component HotCornerTarget: Item {
        id: cornerTarget
        required property bool onTop
        required property bool onLeft
        readonly property bool hovered: horizontalTarget.containsMouse || verticalTarget.containsMouse
        signal entered()
        signal exited()

        implicitWidth: root.hotCornerReach
        implicitHeight: root.hotCornerReach

        MouseArea {
            id: horizontalTarget
            x: 0
            y: cornerTarget.onTop ? 0 : parent.height - height
            width: parent.width
            height: root.hotCornerDepth
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: cornerTarget.entered()
            onExited: cornerTarget.exited()
        }

        MouseArea {
            id: verticalTarget
            x: cornerTarget.onLeft ? 0 : parent.width - width
            y: 0
            width: root.hotCornerDepth
            height: parent.height
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: cornerTarget.entered()
            onExited: cornerTarget.exited()
        }
    }

    Variants {
        id: hotCornerInstances
        model: root.hotCornerEnabled && !root.surfaceMounted ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: true
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
                onTop: root.hotCornerOnTop
                onLeft: root.hotCornerOnLeft
                onEntered: root.triggerHotCorner(String(modelData.name || ""))
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }

    Variants {
        id: surfaceInstances
        model: root.mountedScreens

        PanelWindow {
            id: overviewWindow
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
            HyprlandWindow.opacity: root.motionProgress
            BackgroundEffect.blurRegion: root.effectiveBackgroundBlur > 0
                    && !root.backgroundBlurFailed
                ? backgroundBlurRegion
                : null
            readonly property bool hotCornerHovered: openHotCorner.hovered
            readonly property bool acceptsKeyboard: {
                var wanted = root.effectiveOverviewScreenName;
                if (wanted)
                    return String(modelData.name || "") === wanted;
                return true;
            }
            WlrLayershell.keyboardFocus: root.opened && acceptsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property alias keyboardItem: keyCatcher
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
                    settings.focusSettingsCategory();
            }

            function moveSettingsFocus(forward, wrap) {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.moveSettingsFocus(forward, wrap);
            }

            function focusFirstSettingsControl() {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.focusFirstSettingsControl();
            }

            function moveFooterConfirmationFocus(forward, wrap) {
                var settings = settingsLayerLoader.item;
                if (settings)
                    settings.moveFooterConfirmationFocus(forward, wrap);
            }

            onAcceptsKeyboardChanged: {
                if (acceptsKeyboard && root.settingsOpen)
                    Qt.callLater(overviewWindow.focusSettingsCategory);
            }

            Region {
                id: backgroundBlurRegion
                item: overviewWindow.contentItem
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.effectiveBackgroundDim / 100
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
                            && event.key <= Qt.Key_4) {
                        root.settingsCategoryIndex = event.key - Qt.Key_1;
                        Qt.callLater(overviewWindow.focusSettingsCategory);
                        event.accepted = true;
                        return;
                    }
                    if (root.handleSettingsNavigation(event))
                        return;
                    root.handleKey(event, overviewArea.windowLayout);
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.previewIndex >= 0 || root.previewExitIndex >= 0)
                            root.clearPreview();
                        else
                            root.dismiss();
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.sm
                    spacing: Style.spacing.md

                    Rectangle {
                        id: searchBar
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(Style.space(760), overviewWindow.width - Style.space(48))
                        Layout.preferredHeight: Style.space(48)
                        radius: Style.cornerRadius
                        color: Color.menu.background
                        border.color: root.filterText ? Color.menu.selectedText : Color.menu.border
                        border.width: Math.max(1, Style.normalBorderWidth)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.spacing.xl
                            anchors.rightMargin: Style.spacing.xl
                            spacing: Style.spacing.md
                            Text {
                                text: "⌕"
                                textFormat: Text.PlainText
                                color: Color.menu.text
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.heading
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.filterText || "Type to filter windows…"
                                textFormat: Text.PlainText
                                color: Color.menu.text
                                opacity: root.filterText ? 1 : 0.6
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.heading
                                elide: Text.ElideRight
                            }
                            Text {
                                text: overviewWindow.screenToplevels.length + " windows"
                                textFormat: Text.PlainText
                                color: Color.menu.text
                                opacity: 0.55
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
                            }

                            Rectangle {
                                Layout.preferredWidth: Math.max(1, Style.normalBorderWidth)
                                Layout.preferredHeight: Style.space(24)
                                color: Color.menu.border
                            }

                            Text {
                                Layout.maximumWidth: Style.space(176)
                                text: searchBar.width < Style.space(640)
                                    ? (root.workspaceScope === "all" ? "All" : "WS " + overviewWindow.screenWorkspaceLabel)
                                    : overviewWindow.screenScopeLabel
                                textFormat: Text.PlainText
                                color: Color.accent
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredWidth: Style.space(34)
                                Layout.preferredHeight: Style.space(24)
                                radius: Math.max(2, Style.cornerRadius - Style.spacing.sm)
                                color: "transparent"
                                border.color: Color.menu.border
                                border.width: Math.max(1, Style.normalBorderWidth)

                                Text {
                                    anchors.centerIn: parent
                                    text: "Tab"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
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
                            var screenRatio = overviewWindow.screen && overviewWindow.screen.height > 0
                                ? overviewWindow.screen.width / overviewWindow.screen.height
                                : 0;
                            return root.computeWindowLayout(overviewWindow.screenToplevels, width, height, Style.space(64), Style.spacing.sm, root.windowFooterHeight, screenRatio);
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
                            color: Color.menu.text
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
                            color: Color.menu.text
                            opacity: 0.55
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                            id: settingsControl
                            property bool hovered: false
                            text: "Settings"
                            textFormat: Text.PlainText
                            color: settingsControl.hovered ? Color.menu.selectedText : Color.menu.text
                            opacity: settingsControl.hovered ? 1 : 0.7
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

            HotCornerTarget {
                id: openHotCorner
                width: root.hotCornerReach
                height: root.hotCornerReach
                x: root.hotCornerOnLeft ? 0 : parent.width - width
                y: root.hotCornerOnTop ? 0 : parent.height - height
                z: 100
                enabled: root.hotCornerEnabled
                onTop: root.hotCornerOnTop
                onLeft: root.hotCornerOnLeft
                onEntered: root.triggerHotCorner()
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }
}
