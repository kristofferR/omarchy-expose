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
    property bool opened: false
    property bool surfaceMounted: false
    property bool hotCornerArmed: true
    property string filterText: ""
    property int selectedIndex: 0
    property int hoveredIndex: -1
    property int previewIndex: -1
    property int previewExitIndex: -1
    property bool previewSlowMotion: false
    property bool openingAfterClientRefresh: false
    property bool settingsOpen: false
    property real backgroundBlurPreview: -1
    property real backgroundDimPreview: -1
    readonly property real effectiveBackgroundBlur: root.backgroundBlurPreview >= 0 ? root.backgroundBlurPreview : root.backgroundBlur
    readonly property real effectiveBackgroundDim: root.backgroundDimPreview >= 0 ? root.backgroundDimPreview : root.backgroundDim
    readonly property int previewAnimationDuration: root.previewSlowMotion ? 4000 : 190
    readonly property int previewFadeDuration: root.previewSlowMotion ? 4000 : 130
    property var clients: []
    property var pendingClients: []
    property bool clientSnapshotRejected: false
    property bool clientRefreshPending: false
    property int modelRevision: 0
    property var sessionToplevels: []
    property var sessionAspectRatios: []
    property var pendingAspectRatioToplevels: []
    readonly property var allToplevels: ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    readonly property var filteredToplevels: {
        var revision = root.modelRevision;
        var needle = root.filterText.toLowerCase();
        var result = [];
        var source = root.surfaceMounted ? root.sessionToplevels : root.allToplevels;
        for (var i = 0; i < source.length; i++) {
            var top = source[i];
            if (!top)
                continue;
            var haystack = (String(top.appId || "") + " " + String(top.title || "")).toLowerCase();
            if (!needle || haystack.indexOf(needle) !== -1)
                result.push(top);
        }
        return result;
    }

    onEffectiveBackgroundBlurChanged: {
        if (!root.opened)
            return;
        if (!backgroundBlurSession.running && root.effectiveBackgroundBlur > 0)
            backgroundBlurSession.running = true;
        else if (backgroundBlurSession.running && !backgroundBlurUpdate.running)
            backgroundBlurUpdate.start();
    }

    function open(payload) {
        dismissTimer.stop();
        dismissTimer.notifyShell = false;
        root.closeSettings();
        root.filterText = "";
        var wasMounted = root.surfaceMounted;
        if (!wasMounted)
            root.resetSessionToplevels();
        root.surfaceMounted = true;
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
        root.hoveredIndex = -1;
        root.clearPreview();
        if (wasMounted) {
            root.opened = true;
            root.refreshClients();
            Qt.callLater(root.focusKeyboardWindow);
            return;
        }
        root.openingAfterClientRefresh = true;
        root.refreshClients();
    }

    function close() {
        if (root.surfaceMounted)
            root.startDismiss(false);
        else
            root.opened = false;
    }

    function startDismiss(notifyShell) {
        root.openingAfterClientRefresh = false;
        root.closeSettings();
        root.hoveredIndex = -1;
        root.clearPreview();
        root.opened = false;
        dismissTimer.notifyShell = notifyShell;
        dismissTimer.restart();
    }

    function dismiss() {
        root.startDismiss(true);
    }

    function toggle() {
        root.opened ? root.dismiss() : root.open("{}");
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
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        root.settingsOpen = true;
    }

    function closeSettings() {
        var restoreKeyboardFocus = root.settingsOpen && root.opened;
        root.settingsOpen = false;
        root.backgroundBlurPreview = -1;
        root.backgroundDimPreview = -1;
        if (restoreKeyboardFocus)
            Qt.callLater(function () {
                if (root.opened)
                    root.focusKeyboardWindow();
            });
    }

    onOpenedChanged: {
        if (root.opened && root.effectiveBackgroundBlur > 0 && !backgroundBlurSession.running)
            backgroundBlurSession.running = true;
    }

    function clearPreview() {
        previewExitTimer.stop();
        root.previewSlowMotion = false;
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

    function triggerHotCorner() {
        if (!root.hotCornerEnabled || !root.hotCornerArmed)
            return;
        root.hotCornerArmed = false;
        root.toggle();
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

    function setFilter(value) {
        root.filterText = value;
        root.selectedIndex = 0;
        root.hoveredIndex = -1;
        root.clearPreview();
        root.modelRevision++;
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
        root.clientSnapshotRejected = false;
    }

    function addClientLine(rawLine) {
        var line = String(rawLine || "");
        if (line.length === 0)
            return;
        if (line.length > 16384 || root.pendingClients.length >= 256) {
            root.clientSnapshotRejected = true;
            return;
        }
        try {
            var row = JSON.parse(line);
            if (!row || typeof row !== "object" || typeof row.address !== "string") {
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
            if (!root.clientSnapshotsEqual(comparablePrevious, comparableSnapshot)) {
                root.clients = snapshot;
            }
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
        if (!root.clientRefreshPending && root.openingAfterClientRefresh) {
            root.openingAfterClientRefresh = false;
            root.captureSessionAspectRatios();
            Qt.callLater(function () {
                if (!root.surfaceMounted)
                    return;
                root.opened = true;
                root.focusKeyboardWindow();
            });
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
                    || a.monitor !== b.monitor
                    || a.size[0] !== b.size[0]
                    || a.size[1] !== b.size[1])
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

    function computeWindowLayout(width, height, gap, padding, footerHeight, viewportRatioHint) {
        var count = root.filteredToplevels.length;
        if (!count || width <= 0 || height <= 0)
            return [];

        var edgeInset = gap / 2;
        var availableWidth = Math.max(1, width - edgeInset * 2);
        var availableHeight = Math.max(1, height - edgeInset * 2);
        var entries = [];
        for (var index = 0; index < count; index++) {
            var ratio = root.aspectRatioFor(root.filteredToplevels[index]);
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

    function moveDirectional(dx, dy, layout) {
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
        if (bestIndex >= 0)
            root.selectedIndex = bestIndex;
    }

    function togglePreview(slowMotion) {
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
        var entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var id = normalized(entry.id);
            var name = normalized(entry.name);
            if (id === wanted || id.indexOf(wanted) !== -1 || wanted.indexOf(id) !== -1 || name === wanted)
                return Quickshell.iconPath(String(entry.icon || "application-x-executable"), true);
        }
        return Quickshell.iconPath(wanted || "application-x-executable", true);
    }

    function handleKey(event, layout) {
        if (root.settingsOpen) {
            if (event.key === Qt.Key_Escape) {
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
        else if (event.key === Qt.Key_Left)
            root.moveDirectional(-1, 0, layout);
        else if (event.key === Qt.Key_Right)
            root.moveDirectional(1, 0, layout);
        else if (event.key === Qt.Key_Up)
            root.moveDirectional(0, -1, layout);
        else if (event.key === Qt.Key_Down)
            root.moveDirectional(0, 1, layout);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.activate(root.filteredToplevels[root.selectedIndex]);
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
            root.refreshClients();
        }
    }

    Timer {
        id: previewExitTimer
        interval: root.previewAnimationDuration
        onTriggered: {
            root.previewExitIndex = -1;
            root.previewSlowMotion = false;
        }
    }

    Timer {
        id: dismissTimer
        property bool notifyShell: false
        interval: 190
        onTriggered: {
            root.surfaceMounted = false;
            backgroundBlurSession.running = false;
            if (notifyShell && root.shell && typeof root.shell.hide === "function")
                root.shell.hide(root.pluginId);
            notifyShell = false;
        }
    }

    Timer {
        id: backgroundBlurUpdate
        interval: 80
        onTriggered: {
            if (backgroundBlurSession.running)
                backgroundBlurSession.write(String(Math.round(root.effectiveBackgroundBlur)) + "\n");
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
        id: backgroundBlurSession
        command: [root.pluginDir + "/background-blur-session"]
        stdinEnabled: true
        onStarted: {
            if (!backgroundBlurUpdate.running)
                backgroundBlurUpdate.start();
        }
    }

    IpcHandler {
        target: "expose"
        function open(): string {
            root.toggle();
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
            return settingSlider.from + normalized * (settingSlider.to - settingSlider.from);
        }

        function commitKeyboardValue(nextValue) {
            var next = Math.max(settingSlider.from, Math.min(settingSlider.to, nextValue));
            settingSlider.edited(next);
            settingSlider.committed(next);
        }

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Down)
                settingSlider.commitKeyboardValue(settingSlider.value - settingSlider.stepSize);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up)
                settingSlider.commitKeyboardValue(settingSlider.value + settingSlider.stepSize);
            else if (event.key === Qt.Key_Home)
                settingSlider.commitKeyboardValue(settingSlider.from);
            else if (event.key === Qt.Key_End)
                settingSlider.commitKeyboardValue(settingSlider.to);
            else
                return;
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
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
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

        function chooseOffset(offset) {
            if (!settingChoices.options.length)
                return;
            var current = 0;
            for (var index = 0; index < settingChoices.options.length; index++)
                if (String(settingChoices.options[index].value) === settingChoices.value)
                    current = index;
            var next = (current + offset + settingChoices.options.length) % settingChoices.options.length;
            settingChoices.chosen(String(settingChoices.options[next].value));
        }

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                settingChoices.chooseOffset(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                settingChoices.chooseOffset(1);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                settingChoices.chooseOffset(0);
            else
                return;
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
                    color: Color.menu.text
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

    component SettingToggle: Item {
        id: settingToggle
        property bool checked: false
        signal toggled(bool checked)
        implicitWidth: Style.space(72)
        implicitHeight: Style.space(28)
        activeFocusOnTab: true

        Keys.onPressed: function (event) {
            if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                return;
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

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: settingToggle.forceActiveFocus()
            onClicked: settingToggle.toggled(!settingToggle.checked)
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
                onEntered: root.triggerHotCorner()
                onExited: root.scheduleHotCornerRearm()
            }
        }
    }

    Variants {
        id: surfaceInstances
        model: root.surfaceMounted ? Quickshell.screens : []

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
            BackgroundEffect.blurRegion: root.effectiveBackgroundBlur > 0 ? backgroundBlurRegion : null
            property alias hotCornerHovered: openHotCorner.containsMouse
            readonly property bool acceptsKeyboard: {
                var active = ToplevelManager.activeToplevel;
                if (!active || !active.screens || !active.screens.length)
                    return Quickshell.screens.length > 0 && Quickshell.screens[0].name === modelData.name;
                return active.screens[0].name === modelData.name;
            }
            WlrLayershell.keyboardFocus: root.opened && acceptsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            property alias keyboardItem: keyCatcher
            readonly property int screenMonitorId: {
                for (var i = 0; i < Quickshell.screens.length; i++)
                    if (Quickshell.screens[i] === modelData)
                        return i;
                return -1;
            }

            Region {
                id: backgroundBlurRegion
                item: overviewWindow.contentItem
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.opened ? root.effectiveBackgroundDim / 100 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 130
                    }
                }
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: overviewWindow.acceptsKeyboard
                enabled: root.opened
                opacity: root.opened ? 1 : 0
                scale: root.opened ? 1 : 0.96
                transformOrigin: Item.Center
                Behavior on opacity {
                    NumberAnimation {
                        duration: 190
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 190
                        easing.type: Easing.OutQuart
                    }
                }
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
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
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(Style.space(560), overviewWindow.width - Style.space(48))
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
                                text: root.filteredToplevels.length + " windows"
                                textFormat: Text.PlainText
                                color: Color.menu.text
                                opacity: 0.55
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
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
                            return root.computeWindowLayout(width, height, Style.space(64), Style.spacing.sm, root.windowFooterHeight, screenRatio);
                        }

                        Repeater {
                            model: root.filteredToplevels

                            delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    required property int index
                                    property bool hovered: false
                                    readonly property bool selected: index === root.selectedIndex
                                    readonly property bool focusedWindow: modelData === ToplevelManager.activeToplevel
                                    readonly property bool previewed: index === root.previewIndex
                                    readonly property bool exitingPreview: index === root.previewExitIndex
                                    readonly property bool floatingFooter: root.windowFooterStyle === "floating"
                                    readonly property bool integratedFooter: root.windowFooterStyle === "integrated"
                                    readonly property bool overlayFooter: root.windowFooterStyle === "overlay"
                                    readonly property bool centeredFooter: root.windowFooterStyle === "centered"
                                    readonly property string windowTitle: String(modelData.title || modelData.appId || "Untitled window")
                                    readonly property string applicationName: String(modelData.appId || "Application")
                                    readonly property string workspaceName: root.workspaceName(modelData)
                                    readonly property color outlineColor: focusedWindow ? Color.accent : (selected ? Color.menu.selectedText : Color.menu.border)
                                    readonly property real outlineWidth: hovered
                                        ? Math.max(4, Style.hoverBorderWidth * 2)
                                        : (focusedWindow
                                            ? Math.max(2, Style.selectedBorderWidth)
                                            : (selected ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)))
                                    readonly property var packedRect: overviewArea.windowLayout[index] || Qt.rect(0, 0, 1, 1)
                                    readonly property var previewRect: root.previewRectFor(modelData, packedRect, overviewArea.width, overviewArea.height, Style.spacing.sm, root.windowFooterHeight)
                                    readonly property var layoutRect: previewed ? previewRect : packedRect
                                    x: layoutRect.x
                                    y: layoutRect.y
                                    width: layoutRect.width
                                    height: layoutRect.height
                                    z: previewed || exitingPreview ? 10 : 0
                                    radius: integratedFooter ? Style.cornerRadius : 0
                                    color: integratedFooter ? Color.menu.background : "transparent"
                                    border.color: integratedFooter ? outlineColor : "transparent"
                                    border.width: integratedFooter ? outlineWidth : 0
                                    opacity: root.previewIndex < 0 || previewed ? 1 : 0.28
                                    Behavior on x {
                                        NumberAnimation {
                                            duration: root.previewAnimationDuration
                                            easing.type: Easing.OutQuart
                                        }
                                    }
                                    Behavior on y {
                                        NumberAnimation {
                                            duration: root.previewAnimationDuration
                                            easing.type: Easing.OutQuart
                                        }
                                    }
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: root.previewAnimationDuration
                                            easing.type: Easing.OutQuart
                                        }
                                    }
                                    Behavior on height {
                                        NumberAnimation {
                                            duration: root.previewAnimationDuration
                                            easing.type: Easing.OutQuart
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: root.previewFadeDuration
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.previewIndex < 0 || card.previewed
                                        hoverEnabled: true
                                        onEnabledChanged: {
                                            if (!enabled) {
                                                card.hovered = false;
                                                if (root.hoveredIndex === card.index)
                                                    root.hoveredIndex = -1;
                                            }
                                        }
                                        onEntered: {
                                            card.hovered = true;
                                            root.hoveredIndex = card.index;
                                            root.selectedIndex = card.index;
                                        }
                                        onExited: {
                                            card.hovered = false;
                                            if (root.hoveredIndex === card.index)
                                                root.hoveredIndex = -1;
                                        }
                                        onClicked: root.activate(card.modelData)
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
                                                        live: root.opened
                                                        paintCursor: false
                                                    }
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: Math.min(parent.height * 0.45, Style.space(84))
                                                    visible: card.overlayFooter
                                                    z: 2
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
                                                    visible: card.overlayFooter
                                                    z: 3
                                                    spacing: Style.spacing.md

                                                    Image {
                                                        Layout.preferredWidth: Style.space(28)
                                                        Layout.preferredHeight: Style.space(28)
                                                        source: root.iconFor(card.modelData.appId)
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

                                            RowLayout {
                                                anchors.fill: parent
                                                visible: card.floatingFooter
                                                spacing: Style.spacing.md

                                                Image {
                                                    Layout.preferredWidth: Style.space(30)
                                                    Layout.preferredHeight: Style.space(30)
                                                    source: root.iconFor(card.modelData.appId)
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

                                            RowLayout {
                                                anchors.fill: parent
                                                visible: card.integratedFooter
                                                spacing: Style.spacing.md

                                                Image {
                                                    Layout.preferredWidth: Style.space(24)
                                                    Layout.preferredHeight: Style.space(24)
                                                    source: root.iconFor(card.modelData.appId)
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

                                            ColumnLayout {
                                                anchors.fill: parent
                                                visible: card.centeredFooter
                                                spacing: 0

                                                RowLayout {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: Style.spacing.md

                                                    Image {
                                                        Layout.preferredWidth: Style.space(24)
                                                        Layout.preferredHeight: Style.space(24)
                                                        source: root.iconFor(card.modelData.appId)
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
                            visible: root.filteredToplevels.length === 0
                            text: root.filterText ? "No matching windows" : "No open windows"
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

                        Text {
                            text: "← ↑ ↓ → navigate   Space preview   Shift+Space slow motion   Enter open   Esc close"
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
                            Qt.callLater(function () {
                                if (settingsLayer.visible)
                                    backgroundBlurSlider.forceActiveFocus();
                            });
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.closeSettings()
                    }

                    Rectangle {
                        id: settingsDialog
                        anchors.centerIn: parent
                        width: Math.min(Style.space(920), parent.width - Style.space(80))
                        height: Math.min(Style.space(400), parent.height - Style.space(80))
                        radius: Style.cornerRadius
                        color: Color.menu.background
                        border.color: Color.menu.border
                        border.width: Math.max(1, Style.normalBorderWidth)

                        MouseArea {
                            anchors.fill: parent
                            onClicked: function (mouse) { mouse.accepted = true; }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Style.space(28)
                            spacing: Style.spacing.xl

                            RowLayout {
                                Layout.fillWidth: true

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
                                    text: "Click outside or Esc to close"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    opacity: 0.5
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(1, Style.normalBorderWidth)
                                color: Color.menu.border
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 2
                                columnSpacing: Style.space(48)
                                rowSpacing: 0

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: Style.spacing.lg

                                    Text {
                                        text: "Background"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.55
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                        font.capitalization: Font.AllUppercase
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Dim"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        SettingSlider {
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

                                    Item { Layout.preferredHeight: Style.spacing.md }

                                    Text {
                                        text: "Hot corner"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.55
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                        font.capitalization: Font.AllUppercase
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Enabled"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingToggle {
                                            checked: root.hotCornerEnabled
                                            onToggled: function (checked) { root.setHotCornerEnabled(checked); }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Position"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingChoices {
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

                                    Item { Layout.fillHeight: true }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: Style.spacing.lg

                                    Text {
                                        text: "Windows"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        opacity: 0.55
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                        font.capitalization: Font.AllUppercase
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Preview"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingChoices {
                                            value: root.previewPlacement
                                            options: [
                                                { label: "In place", value: "in-place" },
                                                { label: "Centered", value: "centered" }
                                            ]
                                            onChosen: function (value) { root.setPreviewPlacement(value); }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Labels"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingChoices {
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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.preferredWidth: Style.space(112)
                                            text: "Move pointer"
                                            textFormat: Text.PlainText
                                            color: Color.menu.text
                                            font.family: Style.font.menuFamily
                                            font.pixelSize: Style.font.body
                                        }
                                        Item { Layout.fillWidth: true }
                                        SettingToggle {
                                            checked: root.moveCursorToWindow
                                            onToggled: function (checked) { root.setMoveCursorToWindow(checked); }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }
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
