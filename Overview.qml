import QtQuick
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
    readonly property bool hotCornerEnabled: root.pluginEntry && root.pluginEntry.hotCornerEnabled === true
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
    readonly property int previewAnimationDuration: root.previewSlowMotion ? 4000 : 190
    readonly property int previewFadeDuration: root.previewSlowMotion ? 4000 : 130
    property var clients: []
    property var pendingClients: []
    property bool clientSnapshotRejected: false
    property int clientsRevision: 0
    property int modelRevision: 0
    readonly property var allToplevels: ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    readonly property var filteredToplevels: {
        var revision = root.modelRevision + root.clientsRevision;
        var needle = root.filterText.toLowerCase();
        var result = [];
        for (var i = 0; i < root.allToplevels.length; i++) {
            var top = root.allToplevels[i];
            if (!top)
                continue;
            var haystack = (String(top.appId || "") + " " + String(top.title || "")).toLowerCase();
            if (!needle || haystack.indexOf(needle) !== -1)
                result.push(top);
        }
        return result;
    }

    function open(payload) {
        dismissTimer.stop();
        dismissTimer.notifyShell = false;
        root.filterText = "";
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
        root.hoveredIndex = -1;
        root.clearPreview();
        var wasMounted = root.surfaceMounted;
        root.surfaceMounted = true;
        if (wasMounted)
            root.opened = true;
        root.refreshClients();
        Qt.callLater(function () {
            if (!root.surfaceMounted)
                return;
            root.opened = true;
            root.focusKeyboardWindow();
        });
    }

    function close() {
        if (root.surfaceMounted)
            root.startDismiss(false);
        else
            root.opened = false;
    }

    function startDismiss(notifyShell) {
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

    function togglePreviewPlacement() {
        root.setPreviewPlacement(root.previewPlacement === "centered" ? "in-place" : "centered");
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
        if (!clientQuery.running)
            clientQuery.running = true;
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
        if (exitCode === 0 && exitStatus === 0 && !root.clientSnapshotRejected) {
            root.clients = root.pendingClients.slice();
            root.clientsRevision++;
        }
        root.pendingClients = [];
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

    function workspaceLabel(top) {
        var client = clientFor(top);
        if (!client || !client.workspace)
            return "Workspace —";
        var name = String(client.workspace.name || client.workspace.id || "—");
        return "Workspace " + name;
    }

    function monitorFor(top) {
        var client = clientFor(top);
        return client ? Number(client.monitor) : -1;
    }

    function aspectRatioFor(top) {
        var client = clientFor(top);
        if (!client || !client.size || client.size.length < 2 || client.size[0] <= 0 || client.size[1] <= 0)
            return 1.6;
        return Math.max(0.45, Math.min(4, client.size[0] / client.size[1]));
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
                    height: previewHeight + footerHeight + padding * 3
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

    function computeWindowLayout(width, height, gap, padding, footerHeight) {
        var count = root.filteredToplevels.length;
        if (!count || width <= 0 || height <= 0)
            return [];

        var edgeInset = gap / 2;
        var availableWidth = Math.max(1, width - edgeInset * 2);
        var availableHeight = Math.max(1, height - edgeInset * 2);
        var entries = [];
        var active = ToplevelManager.activeToplevel;
        for (var index = 0; index < count; index++) {
            var ratio = root.aspectRatioFor(root.filteredToplevels[index]);
            var adaptiveWeight = Math.max(0.72, Math.min(1.28, Math.sqrt(ratio / 1.6)));
            if (root.filteredToplevels[index] === active)
                adaptiveWeight *= 1.15;
            entries.push({
                index: index,
                ratio: ratio,
                weight: adaptiveWeight,
                active: root.filteredToplevels[index] === active,
                extremity: Math.max(ratio, 1 / ratio)
            });
        }
        entries.sort(function (a, b) {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            if (a.extremity !== b.extremity)
                return b.extremity - a.extremity;
            return a.index - b.index;
        });

        var high = Math.min(availableWidth, availableHeight);
        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            var entry = entries[entryIndex];
            high = Math.min(high,
                (availableWidth - padding * 2) / Math.sqrt(entry.weight * entry.ratio),
                (availableHeight - footerHeight - padding * 3) / Math.sqrt(entry.weight / entry.ratio));
        }
        high = Math.max(1, high);

        var best = null;
        var bestScale = -1;
        var maxRows = Math.min(count, 4);
        for (var rowCount = 1; rowCount <= maxRows; rowCount++) {
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
        var previewWidth = Math.max(1, Math.min(maxWidth - padding * 2, (maxHeight - footerHeight - padding * 3) * ratio));
        var previewHeight = Math.max(1, previewWidth / ratio);
        var cardWidth = previewWidth + padding * 2;
        var cardHeight = previewHeight + footerHeight + padding * 3;
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
        if (event.key === Qt.Key_Escape) {
            if (root.previewIndex >= 0 || root.previewExitIndex >= 0)
                root.clearPreview();
            else
                root.dismiss();
        } else if (event.key === Qt.Key_Space || event.text === " ") {
            if (!event.isAutoRepeat)
                root.togglePreview(Boolean(event.modifiers & Qt.ShiftModifier));
        }
        else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))
            root.togglePreviewPlacement();
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
            root.modelRevision++;
            if (root.selectedIndex >= root.filteredToplevels.length)
                root.selectedIndex = Math.max(0, root.filteredToplevels.length - 1);
            if (root.previewIndex >= root.filteredToplevels.length || root.previewExitIndex >= 0)
                root.clearPreview();
            root.refreshClients();
        }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.modelRevision++;
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
            if (notifyShell && root.shell && typeof root.shell.hide === "function")
                root.shell.hide(root.pluginId);
            notifyShell = false;
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

            Rectangle {
                anchors.fill: parent
                color: Color.menu.scrim
                opacity: root.opened ? 1 : 0
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
                            var revision = root.modelRevision + root.clientsRevision;
                            var active = ToplevelManager.activeToplevel;
                            return root.computeWindowLayout(width, height, Style.space(64), Style.spacing.sm, Style.space(40));
                        }

                        Repeater {
                            model: root.filteredToplevels

                            delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    required property int index
                                    property bool hovered: false
                                    property bool closeArmed: false
                                    readonly property bool selected: index === root.selectedIndex
                                    readonly property bool focusedWindow: modelData === ToplevelManager.activeToplevel
                                    readonly property bool previewed: index === root.previewIndex
                                    readonly property bool exitingPreview: index === root.previewExitIndex
                                    readonly property var packedRect: overviewArea.windowLayout[index] || Qt.rect(0, 0, 1, 1)
                                    readonly property var previewRect: root.previewRectFor(modelData, packedRect, overviewArea.width, overviewArea.height, Style.spacing.sm, Style.space(40))
                                    readonly property var layoutRect: previewed ? previewRect : packedRect
                                    x: layoutRect.x
                                    y: layoutRect.y
                                    width: layoutRect.width
                                    height: layoutRect.height
                                    z: previewed || exitingPreview ? 10 : 0
                                    radius: Style.cornerRadius
                                    color: Color.menu.background
                                    border.color: focusedWindow ? Color.accent : (selected ? Color.menu.selectedText : Color.menu.border)
                                    border.width: hovered
                                        ? Math.max(4, Style.hoverBorderWidth * 2)
                                        : (focusedWindow
                                            ? Math.max(2, Style.selectedBorderWidth)
                                            : (selected ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)))
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

                                    Timer {
                                        id: disarmClose
                                        interval: 1600
                                        onTriggered: card.closeArmed = false
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.previewIndex < 0 || card.previewed
                                        hoverEnabled: true
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
                                        spacing: Style.spacing.sm

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            Rectangle {
                                                anchors.centerIn: parent
                                                readonly property real windowAspectRatio: root.aspectRatioFor(card.modelData)
                                                width: Math.min(parent.width, parent.height * windowAspectRatio)
                                                height: Math.min(parent.height, parent.width / windowAspectRatio)
                                                radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
                                                color: Color.background
                                                clip: true

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
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Style.space(40)
                                            spacing: Style.spacing.md

                                            Rectangle {
                                                Layout.preferredWidth: Style.space(30)
                                                Layout.preferredHeight: Style.space(30)
                                                radius: Style.cornerRadius
                                                color: Color.menu.selectedBackground
                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: Style.spacing.xs
                                                    source: root.iconFor(card.modelData.appId)
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: card.modelData.title || card.modelData.appId || "Untitled window"
                                                    textFormat: Text.PlainText
                                                    color: Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.body
                                                    font.bold: card.selected
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (card.modelData.appId || "Application") + "  ·  " + root.workspaceLabel(card.modelData)
                                                    textFormat: Text.PlainText
                                                    color: card.focusedWindow ? Color.accent : Color.menu.text
                                                    opacity: card.focusedWindow ? 1 : 0.62
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: Style.font.caption
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: card.closeArmed ? Style.space(72) : Style.space(30)
                                                Layout.preferredHeight: Style.space(30)
                                                radius: Style.cornerRadius
                                                color: card.closeArmed ? Color.urgent : Color.menu.selectedBackground
                                                Behavior on Layout.preferredWidth {
                                                    NumberAnimation {
                                                        duration: 100
                                                    }
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: card.closeArmed ? "Close?" : "×"
                                                    textFormat: Text.PlainText
                                                    color: card.closeArmed ? Color.background : Color.menu.text
                                                    font.family: Style.font.menuFamily
                                                    font.pixelSize: card.closeArmed ? Style.font.caption : Style.font.heading
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: root.previewIndex < 0 || card.previewed
                                                    onClicked: function (mouse) {
                                                        mouse.accepted = true;
                                                        if (card.closeArmed) {
                                                            card.opacity = 0;
                                                            card.modelData.close();
                                                        } else {
                                                            card.closeArmed = true;
                                                            disarmClose.restart();
                                                        }
                                                    }
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
                            text: "← ↑ ↓ → navigate   Space preview   Shift+Space slow motion   Enter open   Esc close   Click × twice to close"
                            textFormat: Text.PlainText
                            color: Color.menu.text
                            opacity: 0.55
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                            id: placementControl
                            property bool hovered: false
                            text: "Preview: " + (root.previewPlacement === "centered" ? "centered" : "in place") + "   Ctrl+P"
                            textFormat: Text.PlainText
                            color: placementControl.hovered ? Color.menu.selectedText : Color.menu.text
                            opacity: placementControl.hovered ? 1 : 0.7
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: placementControl.hovered = true
                                onExited: placementControl.hovered = false
                                onClicked: root.togglePreviewPlacement()
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
