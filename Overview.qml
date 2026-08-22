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
    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
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
        root.filterText = "";
        root.selectedIndex = Math.max(0, root.filteredToplevels.indexOf(ToplevelManager.activeToplevel));
        root.opened = true;
        root.refreshClients();
        Qt.callLater(root.focusKeyboardWindow);
    }

    function close() {
        root.opened = false;
    }

    function dismiss() {
        root.opened = false;
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "birdseye.window-overview");
    }

    function toggle() {
        root.opened ? root.dismiss() : root.open("{}");
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
        root.modelRevision++;
    }

    function moveSelection(delta) {
        var count = root.filteredToplevels.length;
        if (!count)
            return;
        root.selectedIndex = (root.selectedIndex + delta + count) % count;
    }

    function moveRow(delta, columns) {
        var count = root.filteredToplevels.length;
        if (!count)
            return;
        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta * Math.max(1, columns)));
    }

    function activate(top) {
        if (!top)
            return;
        var client = root.clientFor(top);
        var address = client && client.address ? String(client.address) : "";
        // Resolve against fresh compositor state in the helper: the metadata
        // poll can be between updates at the exact moment Enter is pressed.
        var helper = Quickshell.env("HOME") + "/.config/omarchy/plugins/birdseye.window-overview/activate-window";
        Quickshell.execDetached([helper, address, String(top.appId || ""), String(top.title || "")]);
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
            root.pendingClients.push({
                address: String(row.address).slice(0, 32),
                class: String(row.class || "").slice(0, 512),
                initialClass: String(row.initialClass || "").slice(0, 512),
                title: String(row.title || "").slice(0, 512),
                workspace: {
                    id: Number(workspace.id) || 0,
                    name: String(workspace.name || "").slice(0, 128)
                },
                monitor: Number(row.monitor) || 0
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

    function handleKey(event, columns) {
        if (event.key === Qt.Key_Escape)
            root.dismiss();
        else if (event.key === Qt.Key_Left)
            root.moveSelection(-1);
        else if (event.key === Qt.Key_Right)
            root.moveSelection(1);
        else if (event.key === Qt.Key_Up)
            root.moveRow(-1, columns);
        else if (event.key === Qt.Key_Down)
            root.moveRow(1, columns);
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
        command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/birdseye.window-overview/list-clients"]
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
        target: "birdseye"
        function open(): string {
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
    }

    Variants {
        id: surfaceInstances
        model: root.opened ? Quickshell.screens : []

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
            WlrLayershell.namespace: "birdseye-window-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            readonly property bool acceptsKeyboard: {
                var active = ToplevelManager.activeToplevel;
                if (!active || !active.screens || !active.screens.length)
                    return Quickshell.screens.length > 0 && Quickshell.screens[0].name === modelData.name;
                return active.screens[0].name === modelData.name;
            }
            WlrLayershell.keyboardFocus: acceptsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            property alias keyboardItem: keyCatcher
            readonly property int screenMonitorId: {
                for (var i = 0; i < Quickshell.screens.length; i++)
                    if (Quickshell.screens[i] === modelData)
                        return i;
                return -1;
            }
            readonly property int columns: Math.max(1, Math.ceil(Math.sqrt(Math.max(1, root.filteredToplevels.length) * width / Math.max(1, height) * 0.72)))
            readonly property int rows: Math.max(1, Math.ceil(Math.max(1, root.filteredToplevels.length) / columns))
            readonly property real cardWidth: Math.min(Style.space(430), (width - Style.spacing.panelPadding * 2 - Style.spacing.lg * (columns - 1)) / columns)
            readonly property real cardHeight: Math.min(Style.space(300), (height - Style.space(112) - Style.spacing.lg * (rows - 1)) / rows)

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
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    root.handleKey(event, overviewWindow.columns);
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.panelPadding
                    spacing: Style.spacing.xl

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
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Grid {
                            id: windowGrid
                            anchors.centerIn: parent
                            columns: overviewWindow.columns
                            spacing: Style.spacing.lg

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
                                    width: overviewWindow.cardWidth
                                    height: overviewWindow.cardHeight
                                    radius: Style.cornerRadius
                                    color: selected ? Color.menu.selectedBackground : Color.menu.background
                                    border.color: focusedWindow ? Color.accent : (selected ? Color.menu.selectedText : Color.menu.border)
                                    border.width: focusedWindow ? Math.max(2, Style.selectedBorderWidth) : (selected ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth))
                                    scale: selected ? 1.018 : 1
                                    opacity: 0
                                    Component.onCompleted: opacity = 1
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 100
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 140
                                        }
                                    }

                                    Timer {
                                        id: disarmClose
                                        interval: 1600
                                        onTriggered: card.closeArmed = false
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Style.spacing.sm
                                        spacing: Style.spacing.sm

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
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

                                            ScreencopyView {
                                                anchors.fill: parent
                                                captureSource: card.modelData
                                                live: root.opened
                                                paintCursor: false
                                                constraintSize: Qt.size(width, height)
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

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: {
                                            card.hovered = true;
                                            root.selectedIndex = card.index;
                                        }
                                        onExited: card.hovered = false
                                        onClicked: root.activate(card.modelData)
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

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "← ↑ ↓ → navigate   Enter open   Esc close   Click × twice to close a window"
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: 0.55
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }
        }
    }
}
