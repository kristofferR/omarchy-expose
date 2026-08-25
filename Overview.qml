import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

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
    property int activeWorkspaceId: 0
    property string activeWorkspaceName: ""
    property int selectedIndex: 0
    property int hoveredIndex: -1
    property int previewIndex: -1
    property int previewExitIndex: -1
    property bool previewSlowMotion: false
    property bool previewNavigationSlowMotion: false
    property bool openingAfterClientRefresh: false
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
    property var clients: []
    property var pendingClients: []
    property var monitorStates: []
    property bool pendingDisplayStateSeen: false
    property int pendingActiveWorkspaceId: 0
    property string pendingActiveWorkspaceName: ""
    property var pendingMonitorStates: []
    property bool clientSnapshotRejected: false
    property bool clientRefreshPending: false
    property bool openingClientRefreshComplete: false
    property bool backgroundBlurPrimed: false
    property bool backgroundBlurFailed: false
    property bool dismissNotifyShell: false
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
    property var pendingAspectRatioToplevels: []
    readonly property var allToplevels: ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    property string focusedMonitorName: ""
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
        var active = ToplevelManager.activeToplevel;
        if (active && active.screens && active.screens.length)
            return String(active.screens[0].name || "");
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
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
    }

    onMotionProgressChanged: root.scheduleBackgroundBlurUpdate()

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

    // Hyprland binds defined through Omarchy's Lua API expose no command, only
    // a description. Binds described as Exposé (the README convention) are
    // treated as the toggle chord and close the overview from inside, since the
    // shortcut inhibitor stops the compositor from firing them itself.
    property var toggleShortcuts: []
    readonly property var keyNamesByQtKey: ({
        [Qt.Key_Space]: "space", [Qt.Key_Return]: "return", [Qt.Key_Enter]: "kp_enter",
        [Qt.Key_Tab]: "tab", [Qt.Key_Backspace]: "backspace", [Qt.Key_Delete]: "delete",
        [Qt.Key_Insert]: "insert", [Qt.Key_Home]: "home", [Qt.Key_End]: "end",
        [Qt.Key_PageUp]: "prior", [Qt.Key_PageDown]: "next",
        [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
        [Qt.Key_QuoteLeft]: "grave", [Qt.Key_Minus]: "minus", [Qt.Key_Equal]: "equal",
        [Qt.Key_Comma]: "comma", [Qt.Key_Period]: "period", [Qt.Key_Slash]: "slash",
        [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Apostrophe]: "apostrophe",
        [Qt.Key_BracketLeft]: "bracketleft", [Qt.Key_BracketRight]: "bracketright",
        [Qt.Key_Backslash]: "backslash"
    })

    function keyNameFor(event) {
        if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            return "f" + (event.key - Qt.Key_F1 + 1);
        var text = String(event.text || "").toLowerCase();
        return root.keyNamesByQtKey[event.key] || (text.length === 1 && text.charCodeAt(0) > 32 ? text : "");
    }

    function parseToggleShortcuts(text) {
        var binds;
        try {
            binds = JSON.parse(String(text || ""));
        } catch (e) {
            return [];
        }
        if (!Array.isArray(binds))
            return [];
        var result = [];
        for (var index = 0; index < binds.length; index++) {
            var bind = binds[index];
            if (!bind || typeof bind !== "object" || bind.mouse === true)
                continue;
            if (!/expos/i.test(String(bind.description || "")))
                continue;
            var modmask = (Number(bind.modmask) || 0) & 77;
            var key = String(bind.key || "").toLowerCase();
            var keycode = Number(bind.keycode) || 0;
            // A bare printable key would also collide with search typing.
            if (modmask === 0 && key.length === 1)
                continue;
            result.push({ modmask: modmask, key: key, keycode: keycode });
        }
        return result;
    }

    function matchesToggleShortcut(event) {
        if (!root.toggleShortcuts.length || event.isAutoRepeat)
            return false;
        var modmask = (event.modifiers & Qt.ShiftModifier ? 1 : 0)
            | (event.modifiers & Qt.ControlModifier ? 4 : 0)
            | (event.modifiers & Qt.AltModifier ? 8 : 0)
            | (event.modifiers & Qt.MetaModifier ? 64 : 0);
        var name = root.keyNameFor(event);
        for (var index = 0; index < root.toggleShortcuts.length; index++) {
            var shortcut = root.toggleShortcuts[index];
            if (shortcut.modmask !== modmask)
                continue;
            if (shortcut.keycode ? event.nativeScanCode === shortcut.keycode : (name && shortcut.key === name))
                return true;
        }
        return false;
    }

    function open(payload) {
        root.closeSettings();
        root.filterText = "";
        root.workspaceScope = "all";
        root.dismissNotifyShell = false;
        if (!bindQuery.running)
            bindQuery.running = true;
        if (root.surfaceMounted) {
            root.opened = true;
            root.animateMotionTo(1);
            root.refreshClients();
            Qt.callLater(root.focusKeyboardWindow);
            return;
        }
        if (root.openingAfterClientRefresh)
            return;
        if (!root.overviewScreenPinned)
            root.overviewScreenName = root.keyboardScreenName;
        overviewMotionAnimation.stop();
        root.motionTarget = 0;
        root.motionProgress = 0;
        root.resetSessionToplevels();
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
        root.hoveredIndex = -1;
        root.clearPreview();
        root.openingAfterClientRefresh = true;
        root.openingClientRefreshComplete = false;
        root.backgroundBlurPrimed = false;
        root.backgroundBlurFailed = false;
        root.refreshClients();
    }

    function close() {
        root.startDismiss(false);
    }

    function startDismiss(notifyShell) {
        root.openingAfterClientRefresh = false;
        root.openingClientRefreshComplete = false;
        root.closeSettings();
        root.hoveredIndex = -1;
        root.clearPreview();
        root.opened = false;
        root.dismissNotifyShell = root.dismissNotifyShell || notifyShell;
        if (root.surfaceMounted) {
            root.animateMotionTo(0);
            return;
        }
        overviewMotionAnimation.stop();
        root.motionTarget = 0;
        root.motionProgress = 0;
        root.backgroundBlurPrimed = false;
        backgroundBlurSession.running = false;
        root.clearOverviewScreen();
        root.finishDismiss();
    }

    function dismiss() {
        root.startDismiss(true);
    }

    function toggle() {
        (root.opened || root.openingAfterClientRefresh) ? root.dismiss() : root.open("{}");
    }

    function requestedBackgroundBlur() {
        if (root.effectiveBackgroundBlur <= 0 || root.motionProgress <= 0)
            return 0;
        return Math.max(1, Math.round(root.effectiveBackgroundBlur * root.motionProgress));
    }

    function scheduleBackgroundBlurUpdate() {
        if (backgroundBlurSession.running && !backgroundBlurUpdate.running)
            backgroundBlurUpdate.start();
    }

    function prepareOpenSurface() {
        if (!root.openingAfterClientRefresh || !root.openingClientRefreshComplete)
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
            if (!root.surfaceMounted || !root.openingAfterClientRefresh)
                return;
            root.openingAfterClientRefresh = false;
            root.openingClientRefreshComplete = false;
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
        root.scheduleBackgroundBlurUpdate();
        if (root.motionTarget > 0) {
            Qt.callLater(root.focusKeyboardWindow);
            return;
        }
        root.surfaceMounted = false;
        root.backgroundBlurPrimed = false;
        backgroundBlurSession.running = false;
        root.clearOverviewScreen();
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
        if (root.opened || root.openingAfterClientRefresh) {
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
        if (next === "current" && root.activeWorkspaceId === 0 && !root.activeWorkspaceName)
            return;
        if (next === root.workspaceScope)
            return;
        root.workspaceScope = next;
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
    }

    function toggleWorkspaceScope() {
        root.setWorkspaceScope(root.workspaceScope === "all" ? "current" : "all");
    }

    function monitorStatesEqual(left, right) {
        if (!left || left.length !== right.length)
            return false;
        for (var index = 0; index < left.length; index++) {
            var a = left[index];
            var b = right[index];
            if (a.id !== b.id
                    || a.name !== b.name
                    || a.focused !== b.focused
                    || a.activeWorkspace.id !== b.activeWorkspace.id
                    || a.activeWorkspace.name !== b.activeWorkspace.name)
                return false;
        }
        return true;
    }

    function focusedNameFromMonitors(monitors) {
        var list = monitors || [];
        for (var index = 0; index < list.length; index++) {
            var monitor = list[index];
            if (monitor && monitor.focused)
                return String(monitor.name || "");
        }
        return list.length && list[0] ? String(list[0].name || "") : "";
    }

    function applyDisplayState(id, name, monitors) {
        var nextId = Number(id) || 0;
        var nextName = String(name || "").slice(0, 128);
        var nextMonitors = monitors || [];
        var nextFocused = root.focusedNameFromMonitors(nextMonitors);
        if (nextId === root.activeWorkspaceId
                && nextName === root.activeWorkspaceName
                && nextFocused === root.focusedMonitorName
                && root.monitorStatesEqual(root.monitorStates, nextMonitors))
            return;
        root.activeWorkspaceId = nextId;
        root.activeWorkspaceName = nextName;
        root.monitorStates = nextMonitors;
        root.focusedMonitorName = nextFocused;
        if (!root.overviewScreenPinned && (!root.surfaceMounted || root.openingAfterClientRefresh))
            root.overviewScreenName = nextFocused || root.keyboardScreenName;
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
    }

    function activate(top) {
        if (!top)
            return;
        var client = root.clientFor(top);
        var address = client && client.address ? String(client.address) : "";
        // Resolve against fresh compositor state in the helper: the metadata
        // poll can be between updates at the exact moment Enter is pressed.
        var helper = root.pluginDir + "/activate-window";
        Quickshell.execDetached([
            helper,
            address,
            String(top.appId || ""),
            String(top.title || ""),
            root.moveCursorToWindow ? "true" : "false"
        ]);
        root.dismiss();
    }

    function requestClose(top) {
        if (!top || typeof top.close !== "function")
            return;
        top.close();
    }

    function refreshClients() {
        if (clientQuery.running) {
            root.clientRefreshPending = true;
            return;
        }
        root.clientRefreshPending = false;
        clientQuery.running = true;
    }

    function resetSessionToplevels() {
        var next = [];
        for (var index = 0; index < root.allToplevels.length; index++)
            if (root.allToplevels[index])
                next.push(root.allToplevels[index]);
        root.sessionToplevels = next;
        root.pendingAspectRatioToplevels = [];
        root.captureSessionAspectRatios();
        root.modelRevision++;
    }

    function syncSessionToplevels() {
        if (!root.surfaceMounted)
            return false;
        var current = [];
        for (var currentIndex = 0; currentIndex < root.allToplevels.length; currentIndex++)
            if (root.allToplevels[currentIndex])
                current.push(root.allToplevels[currentIndex]);

        var next = [];
        var nextRatios = [];
        var pendingRatios = [];
        for (var pendingIndex = 0; pendingIndex < root.pendingAspectRatioToplevels.length; pendingIndex++) {
            var pendingTop = root.pendingAspectRatioToplevels[pendingIndex];
            if (current.indexOf(pendingTop) !== -1)
                pendingRatios.push(pendingTop);
        }
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
            pendingRatios.push(candidate);
        }

        var changed = next.length !== root.sessionToplevels.length;
        for (var compareIndex = 0; !changed && compareIndex < next.length; compareIndex++)
            changed = next[compareIndex] !== root.sessionToplevels[compareIndex];
        if (!changed)
            return false;
        root.sessionToplevels = next;
        root.sessionAspectRatios = nextRatios;
        root.pendingAspectRatioToplevels = pendingRatios;
        root.modelRevision++;
        return true;
    }

    function captureSessionAspectRatios() {
        var ratios = [];
        for (var index = 0; index < root.sessionToplevels.length; index++)
            ratios.push(root.liveAspectRatioFor(root.sessionToplevels[index]));
        root.sessionAspectRatios = ratios;
    }

    function beginClientSnapshot() {
        root.pendingClients = [];
        root.pendingDisplayStateSeen = false;
        root.pendingActiveWorkspaceId = 0;
        root.pendingActiveWorkspaceName = "";
        root.pendingMonitorStates = [];
        root.clientSnapshotRejected = false;
    }

    function addClientLine(rawLine) {
        var line = String(rawLine || "");
        if (line.length === 0)
            return;
        if (line.length > 16384) {
            root.clientSnapshotRejected = true;
            return;
        }
        try {
            var row = JSON.parse(line);
            if (!row || typeof row !== "object") {
                root.clientSnapshotRejected = true;
                return;
            }
            if (row.kind === "display-state") {
                var activeWorkspace = row.activeWorkspace;
                if (root.pendingDisplayStateSeen
                        || !activeWorkspace
                        || typeof activeWorkspace !== "object"
                        || typeof activeWorkspace.id !== "number"
                        || !isFinite(activeWorkspace.id)
                        || typeof activeWorkspace.name !== "string"
                        || !Array.isArray(row.monitors)
                        || row.monitors.length > 32) {
                    root.clientSnapshotRejected = true;
                    return;
                }
                var monitors = [];
                for (var monitorIndex = 0; monitorIndex < row.monitors.length; monitorIndex++) {
                    var monitor = row.monitors[monitorIndex];
                    var monitorWorkspace = monitor && monitor.activeWorkspace;
                    if (!monitor
                            || typeof monitor !== "object"
                            || typeof monitor.id !== "number"
                            || !isFinite(monitor.id)
                            || typeof monitor.name !== "string"
                            || !monitorWorkspace
                            || typeof monitorWorkspace !== "object"
                            || typeof monitorWorkspace.id !== "number"
                            || !isFinite(monitorWorkspace.id)
                            || typeof monitorWorkspace.name !== "string") {
                        root.clientSnapshotRejected = true;
                        return;
                    }
                    monitors.push({
                        id: Number(monitor.id) || 0,
                        name: String(monitor.name || "").slice(0, 128),
                        focused: monitor.focused === true,
                        activeWorkspace: {
                            id: Number(monitorWorkspace.id) || 0,
                            name: String(monitorWorkspace.name || "").slice(0, 128)
                        }
                    });
                }
                root.pendingDisplayStateSeen = true;
                root.pendingActiveWorkspaceId = Number(activeWorkspace.id) || 0;
                root.pendingActiveWorkspaceName = String(activeWorkspace.name || "").slice(0, 128);
                root.pendingMonitorStates = monitors;
                return;
            }
            if ((row.kind && row.kind !== "client")
                    || typeof row.address !== "string"
                    || root.pendingClients.length >= 256) {
                root.clientSnapshotRejected = true;
                return;
            }
            var workspace = row.workspace && typeof row.workspace === "object" ? row.workspace : {};
            var size = row.size && typeof row.size === "object" && typeof row.size.length === "number" ? row.size : [];
            root.pendingClients.push({
                address: String(row.address).slice(0, 32),
                class: String(row.class || "").slice(0, 512),
                initialClass: String(row.initialClass || "").slice(0, 512),
                title: String(row.title || "").slice(0, 512),
                workspace: {
                    id: Number(workspace.id) || 0,
                    name: String(workspace.name || "").slice(0, 128)
                },
                pinned: row.pinned === true,
                monitor: Number(row.monitor) || 0,
                size: [
                    Math.max(0, Math.min(32768, Number(size[0]) || 0)),
                    Math.max(0, Math.min(32768, Number(size[1]) || 0))
                ]
            });
        } catch (e) {
            root.clientSnapshotRejected = true;
        }
    }

    function finishClientSnapshot(exitCode, exitStatus) {
        var snapshotAccepted = exitCode === 0 && exitStatus === 0 && !root.clientSnapshotRejected;
        if (snapshotAccepted) {
            var snapshot = root.pendingClients.slice();
            var comparableSnapshot = snapshot.slice();
            var comparablePrevious = root.clients.slice();
            comparableSnapshot.sort(function (a, b) { return a.address.localeCompare(b.address); });
            comparablePrevious.sort(function (a, b) { return a.address.localeCompare(b.address); });
            var placementsChanged = !root.clientPlacementsEqual(comparablePrevious, comparableSnapshot);
            var selectedTop = root.filteredToplevels[root.selectedIndex];
            if (!root.clientSnapshotsEqual(comparablePrevious, comparableSnapshot)) {
                root.clients = snapshot;
                root.modelRevision++;
                if ((root.workspaceScope === "current" || root.multiMonitorMode === "per-monitor") && placementsChanged) {
                    root.hoveredIndex = -1;
                    root.clearPreview();
                    var nextSelectedIndex = root.filteredToplevels.indexOf(selectedTop);
                    root.selectedIndex = nextSelectedIndex >= 0 ? nextSelectedIndex : 0;
                }
            }
            if (root.pendingDisplayStateSeen)
                root.applyDisplayState(root.pendingActiveWorkspaceId, root.pendingActiveWorkspaceName, root.pendingMonitorStates);
            if (!root.clientRefreshPending && root.pendingAspectRatioToplevels.length > 0) {
                var updatedRatios = root.sessionAspectRatios.slice();
                for (var pendingIndex = 0; pendingIndex < root.pendingAspectRatioToplevels.length; pendingIndex++) {
                    var sessionIndex = root.sessionToplevels.indexOf(root.pendingAspectRatioToplevels[pendingIndex]);
                    if (sessionIndex >= 0)
                        updatedRatios[sessionIndex] = root.liveAspectRatioFor(root.pendingAspectRatioToplevels[pendingIndex]);
                }
                root.pendingAspectRatioToplevels = [];
                root.sessionAspectRatios = updatedRatios;
                root.modelRevision++;
            }
        }
        root.pendingClients = [];
        root.pendingDisplayStateSeen = false;
        root.pendingActiveWorkspaceId = 0;
        root.pendingActiveWorkspaceName = "";
        root.pendingMonitorStates = [];
        if (!root.clientRefreshPending && root.openingAfterClientRefresh) {
            root.captureSessionAspectRatios();
            root.openingClientRefreshComplete = true;
            root.prepareOpenSurface();
        }
        if (root.clientRefreshPending)
            Qt.callLater(root.refreshClients);
    }

    function clientSnapshotsEqual(left, right) {
        if (!left || left.length !== right.length)
            return false;
        for (var index = 0; index < left.length; index++) {
            var a = left[index];
            var b = right[index];
            if (a.address !== b.address
                    || a.class !== b.class
                    || a.initialClass !== b.initialClass
                    || a.title !== b.title
                    || a.workspace.id !== b.workspace.id
                    || a.workspace.name !== b.workspace.name
                    || a.pinned !== b.pinned
                    || a.monitor !== b.monitor
                    || a.size[0] !== b.size[0]
                    || a.size[1] !== b.size[1])
                return false;
        }
        return true;
    }

    function clientPlacementsEqual(left, right) {
        if (!left || left.length !== right.length)
            return false;
        for (var index = 0; index < left.length; index++) {
            var a = left[index];
            var b = right[index];
            if (a.address !== b.address
                    || a.workspace.id !== b.workspace.id
                    || a.workspace.name !== b.workspace.name
                    || a.pinned !== b.pinned
                    || a.monitor !== b.monitor)
                return false;
        }
        return true;
    }

    function normalized(value) {
        return String(value || "").toLowerCase().replace(/\.desktop$/, "");
    }

    function clientFor(top) {
        if (!top)
            return null;
        var app = normalized(top.appId);
        var title = String(top.title || "");
        var occurrence = 0;
        for (var i = 0; i < root.allToplevels.length; i++) {
            var previous = root.allToplevels[i];
            if (previous === top)
                break;
            if (normalized(previous.appId) === app && String(previous.title || "") === title)
                occurrence++;
        }
        var seen = 0;
        for (var j = 0; j < root.clients.length; j++) {
            var client = root.clients[j];
            if ((normalized(client.class) === app || normalized(client.initialClass) === app) && String(client.title || "") === title) {
                if (seen === occurrence)
                    return client;
                seen++;
            }
        }
        for (var k = 0; k < root.clients.length; k++)
            if (normalized(root.clients[k].class) === app || normalized(root.clients[k].initialClass) === app)
                return root.clients[k];
        return null;
    }

    function workspaceName(top) {
        var client = clientFor(top);
        if (!client || !client.workspace)
            return "—";
        return String(client.workspace.name || client.workspace.id || "—");
    }

    function workspaceLabel(top) {
        return "Workspace " + root.workspaceName(top);
    }

    function monitorStateForScreen(screenName) {
        var wanted = String(screenName || "");
        for (var index = 0; index < root.monitorStates.length; index++) {
            var monitor = root.monitorStates[index];
            if (monitor && monitor.name === wanted)
                return monitor;
        }
        return null;
    }

    function workspaceForScreen(screenName) {
        if (root.multiMonitorMode === "per-monitor") {
            var monitor = root.monitorStateForScreen(screenName);
            if (monitor && monitor.activeWorkspace)
                return monitor.activeWorkspace;
        }
        return {id: root.activeWorkspaceId, name: root.activeWorkspaceName};
    }

    function activeWorkspaceLabelForScreen(screenName) {
        var workspace = root.workspaceForScreen(screenName);
        return String(workspace.name || workspace.id || "—");
    }

    function workspaceScopeLabelForScreen(screenName) {
        return root.workspaceScope === "current"
            ? "Workspace " + root.activeWorkspaceLabelForScreen(screenName)
            : "All workspaces";
    }

    function isOnScreen(top, screenName) {
        if (root.multiMonitorMode !== "per-monitor")
            return true;
        var screens = top && top.screens ? top.screens : [];
        if (screens.length) {
            for (var index = 0; index < screens.length; index++)
                if (String(screens[index].name || "") === String(screenName || ""))
                    return true;
            return false;
        }
        var monitor = root.monitorStateForScreen(screenName);
        var client = root.clientFor(top);
        if (monitor && client)
            return Number(client.monitor) === Number(monitor.id);
        return !monitor;
    }

    function isOnWorkspace(top, workspace) {
        var client = root.clientFor(top);
        if (!client || !client.workspace || !workspace)
            return false;
        if (client.pinned)
            return true;
        var workspaceId = Number(workspace.id) || 0;
        if (workspaceId !== 0)
            return Number(client.workspace.id) === workspaceId;
        var workspaceName = String(workspace.name || "");
        return Boolean(workspaceName) && String(client.workspace.name || "") === workspaceName;
    }

    function toplevelsOnScreen(screenName) {
        var result = [];
        var source = root.surfaceMounted ? root.sessionToplevels : root.allToplevels;
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
            var haystack = (String(top.appId || "") + " " + String(top.title || "")).toLowerCase();
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

    function monitorFor(top) {
        var client = clientFor(top);
        return client ? Number(client.monitor) : -1;
    }

    function liveAspectRatioFor(top) {
        var client = clientFor(top);
        if (!client || !client.size || client.size.length < 2 || client.size[0] <= 0 || client.size[1] <= 0)
            return 1.6;
        return Math.max(0.45, Math.min(4, client.size[0] / client.size[1]));
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

    function iconFor(appId) {
        var wanted = normalized(appId);
        if (Object.prototype.hasOwnProperty.call(root.iconCache, wanted))
            return root.iconCache[wanted];
        var result = "";
        var entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var id = normalized(entry.id);
            var name = normalized(entry.name);
            if (id === wanted || id.indexOf(wanted) !== -1 || wanted.indexOf(id) !== -1 || name === wanted) {
                result = Quickshell.iconPath(String(entry.icon || "application-x-executable"), true);
                break;
            }
        }
        if (!result)
            result = Quickshell.iconPath(wanted || "application-x-executable", true);
        root.iconCache[wanted] = result;
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
        target: ToplevelManager.toplevels
        function onValuesChanged() {
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
            // open() takes a fresh snapshot before mounting, so nothing needs
            // one while the overview is closed.
            if (root.surfaceMounted || root.openingAfterClientRefresh)
                root.refreshClients();
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.iconCache = {};
        }
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
            backgroundBlurSession.write(String(requested) + "\n");
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

    Timer {
        // Toplevel changes refresh immediately above. This slower fallback
        // catches workspace moves, which the foreign-toplevel protocol does
        // not expose, without continuously pressuring the shell process.
        interval: 5000
        repeat: true
        running: root.opened
        triggeredOnStart: true
        onTriggered: root.refreshClients()
    }

    Process {
        id: clientQuery
        command: [root.pluginDir + "/list-clients"]
        onStarted: root.beginClientSnapshot()
        stdout: SplitParser {
            onRead: function (line) {
                root.addClientLine(line);
            }
        }
        onExited: function (exitCode, exitStatus) {
            root.finishClientSnapshot(exitCode, exitStatus);
        }
    }

    Process {
        id: bindQuery
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.toggleShortcuts = root.parseToggleShortcuts(this.text)
        }
    }

    Process {
        id: backgroundBlurSession
        command: [root.pluginDir + "/background-blur-session"]
        stdinEnabled: true
        onStarted: {
            var initialBlur = root.openingAfterClientRefresh && root.effectiveBackgroundBlur > 0
                ? 1
                : root.requestedBackgroundBlur();
            root.lastRequestedBlur = initialBlur;
            backgroundBlurSession.write(String(initialBlur) + "\n");
        }
        stdout: SplitParser {
            onRead: function (line) {
                var applied = Number(line);
                if (!isFinite(applied))
                    return;
                if (applied < 0) {
                    root.backgroundBlurFailed = true;
                    root.prepareOpenSurface();
                    return;
                }
                if (root.openingAfterClientRefresh) {
                    root.backgroundBlurPrimed = true;
                    root.prepareOpenSurface();
                }
            }
        }
        onExited: function (exitCode, exitStatus) {
            root.backgroundBlurPrimed = false;
            root.lastRequestedBlur = -1;
            if (root.openingAfterClientRefresh) {
                root.backgroundBlurFailed = true;
                root.prepareOpenSurface();
            }
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

    component SettingSlider: Item {
        id: settingSlider
        property real from: 0
        property real to: 100
        property real value: 0
        property real stepSize: 1
        property string suffix: ""
        signal edited(real nextValue)
        signal committed(real nextValue)
        implicitWidth: Style.space(280)
        implicitHeight: Style.space(32)
        activeFocusOnTab: true
        readonly property real normalizedValue: Math.max(0, Math.min(1, (value - from) / Math.max(1, to - from)))

        function valueAt(position) {
            var availableWidth = Math.max(1, sliderTrackArea.width - sliderHandle.width);
            var normalized = Math.max(0, Math.min(1, (position - sliderHandle.width / 2) / availableWidth));
            var raw = settingSlider.from + normalized * (settingSlider.to - settingSlider.from);
            if (settingSlider.stepSize <= 0)
                return raw;
            var stepped = settingSlider.from + Math.round((raw - settingSlider.from) / settingSlider.stepSize) * settingSlider.stepSize;
            return Math.max(settingSlider.from, Math.min(settingSlider.to, stepped));
        }

        function commitKeyboardValue(nextValue) {
            var next = Math.max(settingSlider.from, Math.min(settingSlider.to, nextValue));
            settingSlider.edited(next);
            settingSlider.committed(next);
        }

        Keys.onPressed: function (event) {
            if (root.handleSettingsNavigation(event))
                return;
            if (event.key === Qt.Key_Left)
                settingSlider.commitKeyboardValue(settingSlider.value - settingSlider.stepSize);
            else if (event.key === Qt.Key_Right)
                settingSlider.commitKeyboardValue(settingSlider.value + settingSlider.stepSize);
            else if (event.key === Qt.Key_Home)
                settingSlider.commitKeyboardValue(settingSlider.from);
            else if (event.key === Qt.Key_End)
                settingSlider.commitKeyboardValue(settingSlider.to);
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        RowLayout {
            anchors.fill: parent
            spacing: Style.spacing.md

            Item {
                id: sliderTrackArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.max(1, Style.normalBorderWidth)
                    color: Color.menu.border
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * settingSlider.normalizedValue
                    height: Math.max(2, Style.focusBorderWidth)
                    color: Color.accent
                }

                Rectangle {
                    id: sliderHandle
                    width: Style.space(12)
                    height: width
                    x: Math.round((parent.width - width) * settingSlider.normalizedValue)
                    anchors.verticalCenter: parent.verticalCenter
                    color: Color.accent
                    border.color: Color.background
                    border.width: Math.max(1, Style.normalBorderWidth)
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function (mouse) {
                        settingSlider.forceActiveFocus();
                        settingSlider.edited(settingSlider.valueAt(mouse.x));
                    }
                    onPositionChanged: function (mouse) {
                        if (pressed)
                            settingSlider.edited(settingSlider.valueAt(mouse.x));
                    }
                    onReleased: function (mouse) {
                        settingSlider.committed(settingSlider.valueAt(mouse.x));
                    }
                }
            }

            Text {
                Layout.preferredWidth: Style.space(52)
                horizontalAlignment: Text.AlignRight
                text: Math.round(settingSlider.value) + settingSlider.suffix
                textFormat: Text.PlainText
                color: settingSlider.activeFocus ? Color.accent : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: settingSlider.activeFocus
            }
        }
    }

    component SettingChoices: RowLayout {
        id: settingChoices
        property var options: []
        property string value: ""
        signal chosen(string nextValue)
        spacing: Style.spacing.lg
        activeFocusOnTab: true

        // Arrows stop at either end; Space/Enter cycle through every option.
        function chooseOffset(offset, wrap) {
            var count = settingChoices.options.length;
            if (!count)
                return;
            var current = 0;
            for (var index = 0; index < count; index++)
                if (String(settingChoices.options[index].value) === settingChoices.value)
                    current = index;
            var next = wrap
                ? (current + offset + count) % count
                : Math.max(0, Math.min(count - 1, current + offset));
            if (next !== current)
                settingChoices.chosen(String(settingChoices.options[next].value));
        }

        Keys.onPressed: function (event) {
            if (root.handleSettingsNavigation(event))
                return;
            if (event.key === Qt.Key_Left)
                settingChoices.chooseOffset(-1, false);
            else if (event.key === Qt.Key_Right)
                settingChoices.chooseOffset(1, false);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                settingChoices.chooseOffset(1, true);
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Repeater {
            model: settingChoices.options

            delegate: Item {
                id: choice
                required property var modelData
                readonly property bool selected: String(modelData.value) === settingChoices.value
                Layout.preferredWidth: choiceLabel.implicitWidth
                Layout.preferredHeight: Style.space(28)

                Text {
                    id: choiceLabel
                    anchors.centerIn: parent
                    text: String(choice.modelData.label)
                    textFormat: Text.PlainText
                    color: choice.selected && settingChoices.activeFocus ? Color.accent : Color.menu.text
                    opacity: choice.selected ? 1 : 0.45
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    font.bold: choice.selected
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(2, Style.focusBorderWidth)
                    visible: choice.selected
                    color: Color.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingChoices.forceActiveFocus();
                        settingChoices.chosen(String(choice.modelData.value));
                    }
                }
            }
        }
    }

    component DisplayModeChoices: RowLayout {
        id: displayModeChoices
        property string value: "mirrored"
        signal chosen(string nextValue)
        readonly property var options: [
            {
                label: "Same overview",
                description: "Show all windows together on the selected display",
                value: "mirrored"
            },
            {
                label: "Per monitor",
                description: "Show only the selected display's windows",
                value: "per-monitor"
            }
        ]
        spacing: 0
        activeFocusOnTab: true

        function choose(index) {
            var next = Math.max(0, Math.min(displayModeChoices.options.length - 1, index));
            var value = String(displayModeChoices.options[next].value);
            if (value !== displayModeChoices.value)
                displayModeChoices.chosen(value);
        }

        Keys.onPressed: function (event) {
            if (root.handleSettingsNavigation(event))
                return;
            var current = displayModeChoices.value === "per-monitor" ? 1 : 0;
            if (event.key === Qt.Key_Left)
                displayModeChoices.choose(current - 1);
            else if (event.key === Qt.Key_Right)
                displayModeChoices.choose(current + 1);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                displayModeChoices.choose(1 - current);
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Repeater {
            model: displayModeChoices.options

            delegate: Rectangle {
                id: displayModeChoice
                required property var modelData
                readonly property bool selected: String(modelData.value) === displayModeChoices.value
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(64)
                color: "transparent"
                border.color: displayModeChoices.activeFocus && selected ? Color.accent : Color.menu.border
                border.width: Math.max(1, Style.normalBorderWidth)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.md
                    spacing: Style.spacing.xs

                    Text {
                        Layout.fillWidth: true
                        text: String(displayModeChoice.modelData.label)
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: displayModeChoice.selected ? 1 : 0.6
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: displayModeChoice.selected
                    }

                    Text {
                        Layout.fillWidth: true
                        text: String(displayModeChoice.modelData.description)
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(2, Style.focusBorderWidth)
                    visible: displayModeChoice.selected
                    color: Color.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        displayModeChoices.forceActiveFocus();
                        displayModeChoices.chosen(String(displayModeChoice.modelData.value));
                    }
                }
            }
        }
    }

    component SettingsCategoryButton: Item {
        id: categoryButton
        property int categoryIndex: 0
        property string label: ""
        property bool selected: false
        property bool horizontal: false
        property bool hovered: false
        signal chosen(int nextIndex)
        implicitWidth: Style.space(horizontal ? 140 : 200)
        implicitHeight: Style.space(horizontal ? 52 : 48)
        activeFocusOnTab: selected

        signal entered()

        function choose(nextIndex) {
            categoryButton.chosen(Math.max(0, Math.min(3, nextIndex)));
        }

        // The sidebar is a list: arrows along its axis pick a section, the
        // arrow pointing at the content (or Enter/Space) moves focus into it.
        Keys.onPressed: function (event) {
            if (root.handleSettingsTab(event))
                return;
            var previousKey = categoryButton.horizontal ? Qt.Key_Left : Qt.Key_Up;
            var nextKey = categoryButton.horizontal ? Qt.Key_Right : Qt.Key_Down;
            var enterKey = categoryButton.horizontal ? Qt.Key_Down : Qt.Key_Right;
            if (event.key === previousKey)
                categoryButton.choose(categoryButton.categoryIndex - 1);
            else if (event.key === nextKey)
                categoryButton.choose(categoryButton.categoryIndex + 1);
            else if (event.key === Qt.Key_Home)
                categoryButton.choose(0);
            else if (event.key === Qt.Key_End)
                categoryButton.choose(3);
            else if (event.key === enterKey
                    || event.key === Qt.Key_Space
                    || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter)
                categoryButton.entered();
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            color: Color.accent
            opacity: categoryButton.selected ? 0.07 : (categoryButton.hovered ? 0.035 : 0)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: categoryButton.horizontal ? parent.width : Math.max(2, Style.focusBorderWidth)
            height: categoryButton.horizontal ? Math.max(2, Style.focusBorderWidth) : parent.height
            visible: categoryButton.selected
            color: Color.accent
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(categoryButton.horizontal ? 8 : 18)
            anchors.rightMargin: Style.space(categoryButton.horizontal ? 8 : 18)
            spacing: Style.spacing.md

            Text {
                Layout.preferredWidth: Style.space(18)
                text: String(categoryButton.categoryIndex + 1)
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: categoryButton.selected ? Color.accent : Color.menu.text
                opacity: categoryButton.selected || categoryButton.hovered ? 1 : 0.45
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: categoryButton.selected
            }

            Text {
                Layout.fillWidth: true
                text: categoryButton.label
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                color: Color.menu.text
                opacity: categoryButton.selected || categoryButton.hovered ? 1 : 0.55
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: categoryButton.selected
                elide: Text.ElideRight
            }

        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            color: "transparent"
            border.color: categoryButton.activeFocus ? Color.accent : "transparent"
            border.width: categoryButton.activeFocus ? Math.max(2, Style.focusBorderWidth) : 0
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: categoryButton.hovered = true
            onExited: categoryButton.hovered = false
            onPressed: categoryButton.forceActiveFocus()
            onClicked: categoryButton.choose(categoryButton.categoryIndex)
        }
    }

    component SettingsDivider: Rectangle {
        implicitHeight: Math.max(1, Style.normalBorderWidth)
        color: Color.menu.border
    }

    component SettingToggle: Item {
        id: settingToggle
        property bool checked: false
        signal toggled(bool checked)
        implicitWidth: Style.space(72)
        implicitHeight: Style.space(28)
        activeFocusOnTab: true

        Keys.onPressed: function (event) {
            if (root.handleSettingsNavigation(event))
                return;
            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                event.accepted = false;
                return;
            }
            settingToggle.toggled(!settingToggle.checked);
            event.accepted = true;
        }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: settingToggle.checked ? "On" : "Off"
            textFormat: Text.PlainText
            color: Color.menu.text
            opacity: settingToggle.checked ? 1 : 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: Style.space(14)
            color: "transparent"
            border.color: settingToggle.checked ? Color.accent : Color.menu.border
            border.width: Math.max(1, Style.normalBorderWidth)

            Rectangle {
                width: Style.space(10)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                x: settingToggle.checked ? parent.width - width - Style.space(2) : Style.space(2)
                color: settingToggle.checked ? Color.accent : Color.menu.text
                opacity: settingToggle.checked ? 1 : 0.45
                Behavior on x { NumberAnimation { duration: 100 } }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            visible: settingToggle.activeFocus
            color: "transparent"
            border.color: Color.accent
            border.width: Math.max(2, Style.focusBorderWidth)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: settingToggle.forceActiveFocus()
            onClicked: settingToggle.toggled(!settingToggle.checked)
        }
    }

    component DialogButton: Rectangle {
        id: dialogButton
        property string label: ""
        property bool destructive: false
        property bool hovered: false
        signal clicked()
        implicitWidth: buttonLabel.implicitWidth + Style.space(28)
        implicitHeight: Style.space(36)
        activeFocusOnTab: true
        color: "transparent"
        border.color: enabled && (activeFocus || hovered || destructive) ? Color.accent : Color.menu.border
        border.width: activeFocus ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)
        opacity: enabled ? 1 : 0.38

        Keys.onPressed: function (event) {
            if (root.handleSettingsNavigation(event))
                return;
            if (!enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)) {
                event.accepted = false;
                return;
            }
            dialogButton.clicked();
            event.accepted = true;
        }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: dialogButton.label
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: dialogButton.destructive
        }

        MouseArea {
            anchors.fill: parent
            enabled: dialogButton.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: dialogButton.hovered = true
            onExited: dialogButton.hovered = false
            onPressed: dialogButton.forceActiveFocus()
            onClicked: dialogButton.clicked()
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
            implicitWidth: Style.space(12)
            implicitHeight: Style.space(12)
            color: "#02000000"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "expose-hot-corner"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            property alias hotCornerHovered: closedHotCorner.containsMouse

            MouseArea {
                id: closedHotCorner
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
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
            BackgroundEffect.blurRegion: root.effectiveBackgroundBlur > 0
                    && root.motionProgress > 0
                    && !root.backgroundBlurFailed
                ? backgroundBlurRegion
                : null
            property alias hotCornerHovered: openHotCorner.containsMouse
            readonly property bool acceptsKeyboard: {
                var wanted = root.effectiveOverviewScreenName;
                if (wanted)
                    return String(modelData.name || "") === wanted;
                return true;
            }
            WlrLayershell.keyboardFocus: root.opened && acceptsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            ShortcutInhibitor {
                window: overviewWindow
                enabled: root.opened && overviewWindow.acceptsKeyboard
            }

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
                var categoryButton = settingsCategoryRepeater.itemAt(root.settingsCategoryIndex);
                if (categoryButton)
                    categoryButton.forceActiveFocus();
            }

            function availableFocusItems(candidates) {
                var items = [];
                for (var index = 0; index < candidates.length; index++) {
                    var candidate = candidates[index];
                    if (candidate && candidate.visible && candidate.enabled)
                        items.push(candidate);
                }
                return items;
            }

            function settingsFocusItems() {
                var categoryButton = settingsCategoryRepeater.itemAt(root.settingsCategoryIndex);
                if (root.settingsCategoryIndex === 0)
                    return overviewWindow.availableFocusItems([
                        categoryButton,
                        backgroundBlurSlider,
                        backgroundDimSlider,
                        bottomTextToggle
                    ]);
                if (root.settingsCategoryIndex === 1)
                    return overviewWindow.availableFocusItems([
                        categoryButton,
                        hotCornerToggle,
                        hotCornerPositionChoices
                    ]);
                if (root.settingsCategoryIndex === 2)
                    return overviewWindow.availableFocusItems([
                        categoryButton,
                        previewPlacementChoices,
                        windowFooterChoices,
                        movePointerToggle,
                        displayModeChoicesControl
                    ]);
                return overviewWindow.availableFocusItems([
                    categoryButton,
                    motionAnimateButton,
                    animationStyleChoices,
                    animationSpeedSlider,
                    animationInSlider,
                    animationOutSlider,
                    animationSameSpeedToggle
                ]);
            }

            function footerConfirmationFocusItems() {
                return overviewWindow.availableFocusItems([
                    footerHideAcknowledgement,
                    footerHideCancelButton,
                    footerHideConfirmButton
                ]);
            }

            function moveFocus(items, forward, forwardFallbackIndex, wrap) {
                if (!items.length)
                    return;
                var focusedIndex = -1;
                for (var index = 0; index < items.length; index++) {
                    if (items[index].activeFocus) {
                        focusedIndex = index;
                        break;
                    }
                }
                var nextIndex;
                if (focusedIndex < 0)
                    nextIndex = forward ? Math.min(forwardFallbackIndex, items.length - 1) : items.length - 1;
                else if (wrap)
                    nextIndex = (focusedIndex + (forward ? 1 : items.length - 1)) % items.length;
                else
                    nextIndex = focusedIndex + (forward ? 1 : -1);
                if (nextIndex < 0 || nextIndex >= items.length)
                    return;
                root.focusSettingsItem(items[nextIndex]);
            }

            function moveSettingsFocus(forward, wrap) {
                overviewWindow.moveFocus(overviewWindow.settingsFocusItems(), forward, 1, wrap);
            }

            function focusFirstSettingsControl() {
                var items = overviewWindow.settingsFocusItems();
                if (items.length > 1)
                    root.focusSettingsItem(items[1]);
            }

            function moveFooterConfirmationFocus(forward, wrap) {
                overviewWindow.moveFocus(overviewWindow.footerConfirmationFocusItems(), forward, 0, wrap);
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
                opacity: root.motionProgress * root.effectiveBackgroundDim / 100
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: overviewWindow.acceptsKeyboard
                enabled: root.opened
                opacity: root.motionProgress
                scale: root.animationStyle === "zoom"
                    ? 0.82 + 0.18 * root.motionProgress
                    : (root.animationStyle === "slide"
                        ? 0.97 + 0.03 * root.motionProgress
                        : (root.animationStyle === "original"
                            ? 0.96 + 0.04 * root.motionProgress
                            : 1))
                transformOrigin: Item.Center
                transform: Translate {
                    x: root.animationStyle === "slide"
                        ? -overviewWindow.width * 0.11 * (1 - root.motionProgress)
                        : 0
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    if (root.matchesToggleShortcut(event)) {
                        root.dismiss();
                        event.accepted = true;
                        return;
                    }
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

                                delegate: Rectangle {
                                        id: card
                                        required property var modelData
                                        // Position in the filtered list; -1 hides the card.
                                        readonly property int slot: overviewWindow.screenToplevels.indexOf(modelData)
                                        readonly property bool inLayout: slot >= 0
                                        property bool hovered: false
                                        readonly property bool selected: overviewWindow.acceptsKeyboard && inLayout && slot === root.selectedIndex
                                        readonly property bool focusedWindow: modelData === ToplevelManager.activeToplevel
                                        readonly property bool previewed: overviewWindow.acceptsKeyboard && inLayout && slot === root.previewIndex
                                        readonly property bool exitingPreview: overviewWindow.acceptsKeyboard && inLayout && slot === root.previewExitIndex
                                        readonly property bool floatingFooter: root.windowFooterStyle === "floating"
                                        readonly property bool integratedFooter: root.windowFooterStyle === "integrated"
                                        readonly property bool overlayFooter: root.windowFooterStyle === "overlay"
                                        readonly property bool centeredFooter: root.windowFooterStyle === "centered"
                                        readonly property string windowTitle: String(modelData.title || modelData.appId || "Untitled window")
                                        readonly property string applicationName: String(modelData.appId || "Application")
                                        readonly property string workspaceName: root.workspaceName(modelData)
                                        readonly property string iconSource: root.iconFor(modelData.appId)
                                        readonly property color outlineColor: focusedWindow ? Color.accent : (selected ? Color.menu.selectedText : Color.menu.border)
                                        readonly property real outlineWidth: hovered
                                            ? Math.max(4, Style.hoverBorderWidth * 2)
                                            : (focusedWindow
                                                ? Math.max(2, Style.selectedBorderWidth)
                                                : (selected ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)))
                                        // An excluded card keeps its last rectangle, so it neither
                                        // animates toward the origin nor flies back in from it.
                                        readonly property var packedRectSource: inLayout ? overviewArea.windowLayout[slot] : null
                                        property var packedRect: Qt.rect(0, 0, 1, 1)
                                        onPackedRectSourceChanged: {
                                            if (packedRectSource)
                                                packedRect = packedRectSource;
                                        }
                                        Component.onCompleted: {
                                            if (packedRectSource)
                                                packedRect = packedRectSource;
                                        }
                                        readonly property var previewRect: root.previewRectFor(modelData, packedRect, overviewArea.width, overviewArea.height, Style.spacing.sm, root.windowFooterHeight)
                                        readonly property var layoutRect: previewed ? previewRect : packedRect
                                        visible: inLayout
                                        x: layoutRect.x
                                        y: layoutRect.y
                                        width: layoutRect.width
                                        height: layoutRect.height
                                        z: previewed ? 11 : (exitingPreview ? 10 : 0)
                                        radius: integratedFooter ? Style.cornerRadius : 0
                                        color: integratedFooter ? Color.menu.background : "transparent"
                                        border.color: integratedFooter ? outlineColor : "transparent"
                                        border.width: integratedFooter ? outlineWidth : 0
                                        opacity: root.previewIndex < 0 || previewed ? 1 : 0.28
                                        Behavior on x {
                                            enabled: root.motionSettled
                                            NumberAnimation {
                                                duration: root.previewAnimationDuration
                                                easing.type: root.previewAnimationEasing
                                            }
                                        }
                                        Behavior on y {
                                            enabled: root.motionSettled
                                            NumberAnimation {
                                                duration: root.previewAnimationDuration
                                                easing.type: root.previewAnimationEasing
                                            }
                                        }
                                        Behavior on width {
                                            enabled: root.motionSettled
                                            NumberAnimation {
                                                duration: root.previewAnimationDuration
                                                easing.type: root.previewAnimationEasing
                                            }
                                        }
                                        Behavior on height {
                                            enabled: root.motionSettled
                                            NumberAnimation {
                                                duration: root.previewAnimationDuration
                                                easing.type: root.previewAnimationEasing
                                            }
                                        }
                                        Behavior on opacity {
                                            enabled: root.motionSettled
                                            NumberAnimation {
                                                duration: root.previewFadeDuration
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !root.settingsOpen && (root.previewIndex < 0 || card.previewed)
                                            hoverEnabled: true
                                            onEnabledChanged: {
                                                if (!enabled) {
                                                    card.hovered = false;
                                                    if (root.hoveredIndex === card.slot)
                                                        root.hoveredIndex = -1;
                                                }
                                            }
                                            onEntered: {
                                                card.hovered = true;
                                                if (overviewWindow.acceptsKeyboard) {
                                                    root.hoveredIndex = card.slot;
                                                    root.selectedIndex = card.slot;
                                                }
                                            }
                                            onExited: {
                                                card.hovered = false;
                                                if (overviewWindow.acceptsKeyboard && root.hoveredIndex === card.slot)
                                                    root.hoveredIndex = -1;
                                            }
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: function (mouse) {
                                                if (mouse.button === Qt.MiddleButton)
                                                    root.requestClose(card.modelData);
                                                else
                                                    root.activate(card.modelData);
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Style.spacing.sm
                                            spacing: card.overlayFooter ? 0 : Style.spacing.sm

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: previewFrame
                                                    anchors.centerIn: parent
                                                    readonly property real windowAspectRatio: root.aspectRatioFor(card.modelData)
                                                    width: Math.min(parent.width, parent.height * windowAspectRatio)
                                                    height: Math.min(parent.height, parent.width / windowAspectRatio)
                                                    radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
                                                    color: Color.background
                                                    clip: true
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: previewMask
                                                        maskThresholdMin: 0.5
                                                        maskSpreadAtMin: 1.0
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Live preview unavailable"
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        opacity: 0.45
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.body
                                                    }

                                                    Item {
                                                        anchors.centerIn: parent
                                                        width: parent.width * 2
                                                        height: parent.height * 2
                                                        scale: 0.5
                                                        layer.enabled: true
                                                        layer.smooth: true

                                                        ScreencopyView {
                                                            anchors.fill: parent
                                                            captureSource: card.modelData
                                                            live: root.opened && card.inLayout
                                                            paintCursor: false
                                                        }
                                                    }

                                                    Loader {
                                                        anchors.fill: parent
                                                        z: 2
                                                        active: card.overlayFooter
                                                        sourceComponent: overlayFooter
                                                    }
                                                }

                                                Rectangle {
                                                    anchors.fill: previewFrame
                                                    visible: !card.integratedFooter
                                                    z: 5
                                                    radius: previewFrame.radius
                                                    color: "transparent"
                                                    border.color: card.outlineColor
                                                    border.width: card.outlineWidth
                                                }

                                                Rectangle {
                                                    id: previewMask
                                                    anchors.fill: previewFrame
                                                    radius: previewFrame.radius
                                                    color: "black"
                                                    visible: false
                                                    layer.enabled: true
                                                    layer.smooth: true
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(40)
                                                visible: !card.overlayFooter

                                                Loader {
                                                    anchors.fill: parent
                                                    sourceComponent: card.floatingFooter
                                                        ? floatingFooter
                                                        : (card.integratedFooter
                                                            ? integratedFooter
                                                            : (card.centeredFooter ? centeredFooter : null))
                                                }
                                            }
                                        }

                                        // Only the configured footer style is instantiated per card.
                                        Component {
                                            id: overlayFooter

                                            Item {
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: Math.min(parent.height * 0.45, Style.space(84))
                                                    gradient: Gradient {
                                                        orientation: Gradient.Vertical
                                                        GradientStop { position: 0; color: "transparent" }
                                                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.94) }
                                                    }
                                                }

                                                RowLayout {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: Style.spacing.md
                                                    spacing: Style.spacing.md

                                                    Image {
                                                        Layout.preferredWidth: Style.space(28)
                                                        Layout.preferredHeight: Style.space(28)
                                                        source: card.iconSource
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 0
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: card.windowTitle
                                                            textFormat: Text.PlainText
                                                            color: Color.menu.text
                                                            font.family: Style.font.menuFamily
                                                            font.pixelSize: Style.font.body
                                                            font.bold: card.selected
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: card.applicationName
                                                            textFormat: Text.PlainText
                                                            color: Color.menu.text
                                                            opacity: 0.68
                                                            font.family: Style.font.menuFamily
                                                            font.pixelSize: Style.font.caption
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        spacing: 0
                                                        Text {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: card.workspaceName
                                                            textFormat: Text.PlainText
                                                            color: card.focusedWindow ? Color.accent : Color.menu.text
                                                            font.family: Style.font.menuFamily
                                                            font.pixelSize: Style.font.heading
                                                            font.bold: true
                                                        }
                                                        Text {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: "Workspace"
                                                            textFormat: Text.PlainText
                                                            color: Color.menu.text
                                                            opacity: 0.55
                                                            font.family: Style.font.menuFamily
                                                            font.pixelSize: Style.font.caption
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Component {
                                            id: floatingFooter

                                            RowLayout {
                                                spacing: Style.spacing.md

                                                Image {
                                                    Layout.preferredWidth: Style.space(30)
                                                    Layout.preferredHeight: Style.space(30)
                                                    source: card.iconSource
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: card.windowTitle
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.body
                                                        font.bold: card.selected
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: card.applicationName
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        opacity: 0.62
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.caption
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                ColumnLayout {
                                                    spacing: 0
                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        text: card.workspaceName
                                                        textFormat: Text.PlainText
                                                        color: card.focusedWindow ? Color.accent : Color.menu.text
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.heading
                                                        font.bold: true
                                                    }
                                                    Text {
                                                        Layout.alignment: Qt.AlignRight
                                                        text: "Workspace"
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        opacity: 0.55
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.caption
                                                    }
                                                }
                                            }
                                        }

                                        Component {
                                            id: integratedFooter

                                            RowLayout {
                                                spacing: Style.spacing.md

                                                Image {
                                                    Layout.preferredWidth: Style.space(24)
                                                    Layout.preferredHeight: Style.space(24)
                                                    source: card.iconSource
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: card.windowTitle
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                    font.bold: card.selected
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: "WS " + card.workspaceName
                                                    textFormat: Text.PlainText
                                                    color: card.focusedWindow ? Color.accent : Color.menu.text
                                                    opacity: card.focusedWindow ? 1 : 0.68
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        Component {
                                            id: centeredFooter

                                            ColumnLayout {
                                                spacing: 0

                                                RowLayout {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: Style.spacing.md

                                                    Image {
                                                        Layout.preferredWidth: Style.space(24)
                                                        Layout.preferredHeight: Style.space(24)
                                                        source: card.iconSource
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                    }

                                                    Text {
                                                        Layout.maximumWidth: Math.max(1, card.width - Style.space(80))
                                                        text: card.windowTitle
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.body
                                                        font.bold: card.selected
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.maximumWidth: Math.max(1, card.width - Style.space(32))
                                                    text: card.applicationName + "  ·  Workspace " + card.workspaceName
                                                    textFormat: Text.PlainText
                                                    color: card.focusedWindow ? Color.accent : Color.menu.text
                                                    opacity: card.focusedWindow ? 1 : 0.62
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

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

                Item {
                    id: settingsLayer
                    anchors.fill: parent
                    visible: root.settingsOpen
                    z: 200
                    onVisibleChanged: {
                        if (visible && overviewWindow.acceptsKeyboard)
                            Qt.callLater(overviewWindow.focusSettingsCategory);
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.closeSettings()
                    }

                    Rectangle {
                        id: settingsDialog
                        readonly property bool narrow: width < Style.space(760)
                        anchors.centerIn: parent
                        width: Math.min(Style.space(920), parent.width - Style.space(80))
                        height: Math.min(Style.space(narrow ? 720 : 640), parent.height - Style.space(80))
                        radius: Style.cornerRadius
                        color: Color.menu.background
                        border.color: Color.menu.border
                        border.width: Math.max(1, Style.normalBorderWidth)
                        enabled: !root.footerHideConfirmationOpen

                        MouseArea {
                            anchors.fill: parent
                            onClicked: function (mouse) { mouse.accepted = true; }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(66)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(24)
                                    anchors.rightMargin: Style.space(24)
                                    spacing: Style.spacing.lg

                                    Text {
                                        text: "Exposé settings"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.heading
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "1-4 section   ↑↓ move   ←→ adjust   Esc close"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.5
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: settingsDialog.narrow ? 1 : 2
                                columnSpacing: 0
                                rowSpacing: 0

                                Item {
                                    Layout.fillWidth: settingsDialog.narrow
                                    Layout.fillHeight: !settingsDialog.narrow
                                    Layout.preferredWidth: settingsDialog.narrow ? 0 : Style.space(218)
                                    Layout.preferredHeight: settingsDialog.narrow ? Style.space(54) : 0

                                    GridLayout {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        columns: settingsDialog.narrow ? 4 : 1
                                        columnSpacing: 0
                                        rowSpacing: 0

                                        Repeater {
                                            id: settingsCategoryRepeater
                                            model: [
                                                "Appearance",
                                                "Hot corner",
                                                "Windows",
                                                "Motion"
                                            ]

                                            delegate: SettingsCategoryButton {
                                                required property int index
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(settingsDialog.narrow ? 52 : 48)
                                                categoryIndex: index
                                                label: String(modelData)
                                                selected: root.settingsCategoryIndex === index
                                                horizontal: settingsDialog.narrow
                                                onChosen: function (nextIndex) {
                                                    root.settingsCategoryIndex = nextIndex;
                                                    var nextButton = settingsCategoryRepeater.itemAt(nextIndex);
                                                    if (nextButton)
                                                        nextButton.forceActiveFocus();
                                                }
                                                onEntered: overviewWindow.focusFirstSettingsControl()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        width: settingsDialog.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
                                        height: settingsDialog.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
                                        color: Color.menu.border
                                    }
                                }

                                Item {
                                    id: settingsCategoryContent
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                                        visible: root.settingsCategoryIndex === 0
                                        enabled: visible

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: Style.spacing.md

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.spacing.xs

                                                Text {
                                                    text: "Appearance"
                                                    textFormat: Text.PlainText
                                                    color: Color.accent
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                    font.capitalization: Font.AllUppercase
                                                }

                                                Text {
                                                    text: "Backdrop and footer"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.heading
                                                    font.bold: true
                                                }
                                            }

                                            Item { Layout.preferredHeight: Style.spacing.sm }
                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Blur"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                SettingSlider {
                                                    id: backgroundBlurSlider
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 20
                                                    value: root.effectiveBackgroundBlur
                                                    suffix: " px"
                                                    onEdited: function (value) { root.backgroundBlurPreview = value; }
                                                    onCommitted: function (value) {
                                                        root.backgroundBlurPreview = Math.round(value);
                                                        root.setBackgroundBlur(value);
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Dim"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                SettingSlider {
                                                    id: backgroundDimSlider
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 90
                                                    value: root.effectiveBackgroundDim
                                                    suffix: "%"
                                                    onEdited: function (value) { root.backgroundDimPreview = value; }
                                                    onCommitted: function (value) {
                                                        root.backgroundDimPreview = Math.round(value);
                                                        root.setBackgroundDim(value);
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    text: "Bottom text"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingToggle {
                                                    id: bottomTextToggle
                                                    checked: root.showFooter
                                                    onToggled: function (checked) {
                                                        if (checked)
                                                            root.updatePluginSetting("showFooter", true);
                                                        else
                                                            root.requestFooterHide();
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }
                                            Item { Layout.fillHeight: true }
                                        }
                                    }

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                                        visible: root.settingsCategoryIndex === 1
                                        enabled: visible

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: Style.spacing.md

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.spacing.xs

                                                Text {
                                                    text: "Hot corner"
                                                    textFormat: Text.PlainText
                                                    color: Color.accent
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                    font.capitalization: Font.AllUppercase
                                                }

                                                Text {
                                                    text: "Overview activation"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.heading
                                                    font.bold: true
                                                }
                                            }

                                            Item { Layout.preferredHeight: Style.spacing.sm }
                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    text: "Enabled"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingToggle {
                                                    id: hotCornerToggle
                                                    checked: root.hotCornerEnabled
                                                    onToggled: function (checked) { root.setHotCornerEnabled(checked); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Position"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingChoices {
                                                    id: hotCornerPositionChoices
                                                    value: root.hotCornerPosition
                                                    options: [
                                                        { label: "TL", value: "top-left" },
                                                        { label: "TR", value: "top-right" },
                                                        { label: "BL", value: "bottom-left" },
                                                        { label: "BR", value: "bottom-right" }
                                                    ]
                                                    onChosen: function (value) { root.setHotCornerPosition(value); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }
                                            Item { Layout.fillHeight: true }
                                        }
                                    }

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                                        visible: root.settingsCategoryIndex === 2
                                        enabled: visible

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: Style.spacing.md

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.spacing.xs

                                                Text {
                                                    text: "Windows"
                                                    textFormat: Text.PlainText
                                                    color: Color.accent
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                    font.capitalization: Font.AllUppercase
                                                }

                                                Text {
                                                    text: "Window behavior"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.heading
                                                    font.bold: true
                                                }
                                            }

                                            Item { Layout.preferredHeight: Style.spacing.sm }
                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Preview"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingChoices {
                                                    id: previewPlacementChoices
                                                    value: root.previewPlacement
                                                    options: [
                                                        { label: "In place", value: "in-place" },
                                                        { label: "Centered", value: "centered" }
                                                    ]
                                                    onChosen: function (value) { root.setPreviewPlacement(value); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Labels"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingChoices {
                                                    id: windowFooterChoices
                                                    value: root.windowFooterStyle
                                                    spacing: Style.spacing.md
                                                    options: [
                                                        { label: "Floating", value: "floating" },
                                                        { label: "Rail", value: "integrated" },
                                                        { label: "Overlay", value: "overlay" },
                                                        { label: "Centered", value: "centered" }
                                                    ]
                                                    onChosen: function (value) { root.setWindowFooterStyle(value); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    text: "Move pointer"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingToggle {
                                                    id: movePointerToggle
                                                    checked: root.moveCursorToWindow
                                                    onToggled: function (checked) { root.setMoveCursorToWindow(checked); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(76)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Displays"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                DisplayModeChoices {
                                                    id: displayModeChoicesControl
                                                    Layout.fillWidth: true
                                                    value: root.multiMonitorMode
                                                    onChosen: function (value) { root.setMultiMonitorMode(value); }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }
                                            Item { Layout.fillHeight: true }
                                        }
                                    }

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                                        visible: root.settingsCategoryIndex === 3
                                        enabled: visible

                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: Style.spacing.md

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Style.spacing.lg

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Style.spacing.xs

                                                    Text {
                                                        text: "Motion"
                                                        textFormat: Text.PlainText
                                                        color: Color.accent
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.caption
                                                        font.bold: true
                                                        font.capitalization: Font.AllUppercase
                                                    }

                                                    Text {
                                                        text: "Overview transition"
                                                        textFormat: Text.PlainText
                                                        color: Color.menu.text
                                                        font.family: Style.font.menuFamily
                                                        font.pixelSize: Style.font.heading
                                                        font.bold: true
                                                    }
                                                }

                                                DialogButton {
                                                    id: motionAnimateButton
                                                    label: "Animate"
                                                    onClicked: root.previewAnimation()
                                                }
                                            }

                                            Item { Layout.preferredHeight: Style.spacing.sm }
                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Style"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingChoices {
                                                    id: animationStyleChoices
                                                    value: root.animationStyle
                                                    options: [
                                                        { label: "Original", value: "original" },
                                                        { label: "Fade", value: "fade" },
                                                        { label: "Zoom", value: "zoom" },
                                                        { label: "Slide", value: "slide" }
                                                    ]
                                                    onChosen: function (value) {
                                                        root.clearAnimationTimingPreview();
                                                        root.setAnimationStyle(value);
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                visible: !root.animationTimingFor(root.animationStyle).separate
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Speed"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                SettingSlider {
                                                    id: animationSpeedSlider
                                                    Layout.fillWidth: true
                                                    from: 100
                                                    to: 800
                                                    stepSize: 10
                                                    value: root.animationInDurationFor(root.animationStyle)
                                                    suffix: " ms"
                                                    onEdited: function (value) {
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationInDurationPreview = value;
                                                        root.animationOutDurationPreview = value;
                                                    }
                                                    onCommitted: function (value) {
                                                        var next = root.setAnimationDuration(root.animationStyle, value);
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationInDurationPreview = next;
                                                        root.animationOutDurationPreview = next;
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                visible: root.animationTimingFor(root.animationStyle).separate
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "In"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                SettingSlider {
                                                    id: animationInSlider
                                                    Layout.fillWidth: true
                                                    from: 100
                                                    to: 800
                                                    stepSize: 10
                                                    value: root.animationInDurationFor(root.animationStyle)
                                                    suffix: " ms"
                                                    onEdited: function (value) {
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationInDurationPreview = value;
                                                    }
                                                    onCommitted: function (value) {
                                                        var next = root.setAnimationDurationIn(root.animationStyle, value);
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationInDurationPreview = next;
                                                    }
                                                }
                                            }

                                            SettingsDivider {
                                                Layout.fillWidth: true
                                                visible: root.animationTimingFor(root.animationStyle).separate
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                visible: root.animationTimingFor(root.animationStyle).separate
                                                Text {
                                                    Layout.preferredWidth: Style.space(120)
                                                    text: "Out"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                SettingSlider {
                                                    id: animationOutSlider
                                                    Layout.fillWidth: true
                                                    from: 100
                                                    to: 800
                                                    stepSize: 10
                                                    value: root.animationOutDurationFor(root.animationStyle)
                                                    suffix: " ms"
                                                    onEdited: function (value) {
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationOutDurationPreview = value;
                                                    }
                                                    onCommitted: function (value) {
                                                        var next = root.setAnimationDurationOut(root.animationStyle, value);
                                                        root.animationDurationPreviewStyle = root.animationStyle;
                                                        root.animationOutDurationPreview = next;
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Style.space(48)
                                                Text {
                                                    text: "Same speed in and out"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                }
                                                Item { Layout.fillWidth: true }
                                                SettingToggle {
                                                    id: animationSameSpeedToggle
                                                    checked: !root.animationTimingFor(root.animationStyle).separate
                                                    onToggled: function (checked) {
                                                        root.clearAnimationTimingPreview();
                                                        root.setAnimationTimingSeparate(root.animationStyle, !checked);
                                                    }
                                                }
                                            }

                                            SettingsDivider { Layout.fillWidth: true }
                                            Item { Layout.fillHeight: true }
                                        }
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(44)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(24)
                                    anchors.rightMargin: Style.space(24)
                                    spacing: Style.spacing.lg

                                    Text {
                                        text: "Changes save immediately"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.45
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        visible: !settingsDialog.narrow
                                        text: "1–4 category   Tab controls"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.45
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        id: footerHideConfirmationLayer
                        anchors.fill: parent
                        visible: root.footerHideConfirmationOpen
                        z: 10
                        onVisibleChanged: {
                            if (visible && overviewWindow.acceptsKeyboard)
                                Qt.callLater(function () {
                                    if (footerHideConfirmationLayer.visible)
                                        footerHideAcknowledgement.forceActiveFocus();
                                });
                            else if (!visible && root.settingsOpen && overviewWindow.acceptsKeyboard)
                                Qt.callLater(function () {
                                    if (settingsLayer.visible && !footerHideConfirmationLayer.visible)
                                        bottomTextToggle.forceActiveFocus();
                                });
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.closeFooterHideConfirmation()
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: 0.72
                        }

                        Rectangle {
                            id: footerHideDialog
                            anchors.centerIn: parent
                            width: Math.min(Style.space(560), parent.width - Style.space(80))
                            height: Math.min(parent.height - Style.space(80), footerHideContent.implicitHeight + Style.space(56))
                            radius: Style.cornerRadius
                            color: Color.menu.background
                            border.color: Color.menu.border
                            border.width: Math.max(1, Style.normalBorderWidth)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: function (mouse) { mouse.accepted = true; }
                            }

                            ColumnLayout {
                                id: footerHideContent
                                anchors.fill: parent
                                anchors.margins: Style.space(28)
                                spacing: Style.spacing.lg

                                Text {
                                    Layout.fillWidth: true
                                    text: "Hide bottom text?"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.heading
                                    font.bold: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "This also hides the Settings link. You can turn it back on while this panel remains open."
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: recoveryText.implicitHeight + Style.space(24)
                                    color: Color.background
                                    border.color: Color.menu.border
                                    border.width: Math.max(1, Style.normalBorderWidth)

                                    Text {
                                        id: recoveryText
                                        anchors.fill: parent
                                        anchors.margins: Style.space(12)
                                        text: "After closing Settings, restore it in ~/.config/omarchy/shell.json by setting showFooter to true in the expose.window-overview plugin entry."
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        color: Color.menu.text
                                        opacity: 0.72
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                    }
                                }

                                Item {
                                    id: footerHideAcknowledgement
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(Style.space(40), acknowledgementText.implicitHeight)
                                    activeFocusOnTab: true

                                    Keys.onPressed: function (event) {
                                        if (root.handleSettingsNavigation(event))
                                            return;
                                        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                                            event.accepted = false;
                                            return;
                                        }
                                        root.footerHideAcknowledged = !root.footerHideAcknowledged;
                                        event.accepted = true;
                                    }

                                    RowLayout {
                                        id: acknowledgementRow
                                        anchors.fill: parent
                                        spacing: Style.spacing.md

                                        Rectangle {
                                            Layout.preferredWidth: Style.space(18)
                                            Layout.preferredHeight: Style.space(18)
                                            color: root.footerHideAcknowledged ? Color.accent : "transparent"
                                            border.color: footerHideAcknowledgement.activeFocus || root.footerHideAcknowledged
                                                ? Color.accent
                                                : Color.menu.border
                                            border.width: footerHideAcknowledgement.activeFocus
                                                ? Math.max(2, Style.focusBorderWidth)
                                                : Math.max(1, Style.normalBorderWidth)

                                            Text {
                                                anchors.centerIn: parent
                                                visible: root.footerHideAcknowledged
                                                text: "✓"
                                                textFormat: Text.PlainText
                                                color: Color.background
                                                font.family: Style.font.menuFamily
                                                font.pixelSize: Style.font.caption
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            id: acknowledgementText
                                            Layout.fillWidth: true
                                            text: "I understand that closing Settings while it is hidden requires editing the config."
                                            textFormat: Text.PlainText
                                            wrapMode: Text.WordWrap
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.bodySmall
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: footerHideAcknowledgement.forceActiveFocus()
                                        onClicked: root.footerHideAcknowledged = !root.footerHideAcknowledged
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Style.spacing.sm
                                    spacing: Style.spacing.md

                                    Item { Layout.fillWidth: true }

                                    DialogButton {
                                        id: footerHideCancelButton
                                        label: "Cancel"
                                        onClicked: root.closeFooterHideConfirmation()
                                    }

                                    DialogButton {
                                        id: footerHideConfirmButton
                                        label: "Hide bottom text"
                                        destructive: true
                                        enabled: root.footerHideAcknowledged
                                        onClicked: root.confirmFooterHide()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: openHotCorner
                width: Style.space(12)
                height: Style.space(12)
                x: root.hotCornerOnLeft ? 0 : parent.width - width
                y: root.hotCornerOnTop ? 0 : parent.height - height
                z: 100
                enabled: root.hotCornerEnabled
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: root.triggerHotCorner()
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }
}
