import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
ShellRoot {
    id: test
    property int phase: 0
    WindowBorders { id: windowBorders }
    QtObject {
        id: controller
        readonly property alias windowBorders: windowBorders
        property int settingsCategoryIndex: 0
        property bool settingsOpen: true
        property bool footerHideConfirmationOpen: false
        property bool footerHideAcknowledged: false
        property bool showFooter: true
        property int effectiveBackgroundBlur: 4
        property int effectiveBackgroundDim: 6
        property bool hotCornerEnabled: false
        property bool hotCornerAllDisplays: false
        property string hotCornerPosition: "top-left"
        property int hotCornerDelayPreview: -1
        property int hotCornerDelay: 0
        readonly property int effectiveHotCornerDelay: hotCornerDelayPreview >= 0 ? hotCornerDelayPreview : hotCornerDelay
        property bool moveCursorToWindow: true
        property string multiMonitorMode: "mirrored"
        property string initialWorkspaceScope: "all"
        property string workspaceLabelStyle: "full"
        property bool separateTiming: false
        property string previewPlacement: "in-place"
        property string windowFooterStyle: "floating"
        property string animationStyle: "original"
        property string animationDurationPreviewStyle: ""
        property int animationInDurationPreview: -1
        property int animationOutDurationPreview: -1
        property var slideDirection: ({"in":"left", "out":"left"})
        property int previewIndex: -1
        property int previewExitIndex: -1
        property int selectedIndex: -1
        property string selectionScreenName: ""
        property string previewScreenName: ""
        property string previewExitScreenName: ""
        property string hoveredScreenName: ""
        property int hoveredIndex: -1
        property bool opened: false
        property int windowFooterHeight: 40
        property bool motionSettled: true
        property int previewAnimationDuration: 190
        property int previewAnimationEasing: Easing.OutQuart
        property int previewFadeDuration: 130
        function animationTimingFor(style) { return {"in":190,"out":190,separate:separateTiming}; }
        function focusSettingsItem(item) { item.forceActiveFocus(); return true; }
        function setHotCornerDelay(value) { hotCornerDelay = value; return value; }
        function animationInDurationFor(style) { return 190; }
        function animationOutDurationFor(style) { return 190; }
        function aspectRatioFor(model) { return 1.8; }
        function previewRectFor(model, rect) { return rect; }
        function workspaceName(model) { return "1"; }
        function iconFor(model) { return ""; }
    }
    Window {
        id: window
        visible: true
        width: 1240
        height: 1040
        color: Color.menu.background
        Rectangle {
            id: canvas
            color: Color.menu.background
            anchors.fill: parent
            Row {
                id: samples
                x: 40; y: 30; spacing: 20
                ThemedControl { id: normal; width: 200; height: 65; Text { anchors.centerIn: parent; text: "Normal"; color: parent.stateColor } }
                ThemedControl { id: hover; hovered: true; width: 200; height: 65; Text { anchors.centerIn: parent; text: "Hover"; color: parent.stateColor } }
                ThemedControl { id: focus; focused: true; width: 200; height: 65; Text { anchors.centerIn: parent; text: "Focus"; color: parent.stateColor } }
                ThemedControl { id: selected; selected: true; width: 200; height: 65; Text { anchors.centerIn: parent; text: "Selected"; color: parent.stateColor } }
                ThemeDivider { id: divider; vertical: true; width: implicitWidth; height: 65 }
            }
            SettingsView {
                id: settings
                y: 100
                width: parent.width
                height: 800
                controller: controller
                hostWindow: QtObject {
                    property bool acceptsKeyboard: false
                    function focusFirstSettingsControl() {}
                }
            }
            WindowCard {
                id: card
                modelData: ({title: "Window preview", lastIpcObject: {class: "example"}, workspace: {id:1,name:"1"}})
                controller: controller
                screenToplevels: [modelData]
                screenName: "DP-1"
                windowLayout: [Qt.rect(960, 25, 240, 160)]
                layoutAreaWidth: 1240
                layoutAreaHeight: 1040
            }
        }
    }
    function checkBorderless(item) {
        if ("borderSpec" in item) require(Border.isNone(item.borderSpec), "borderless view component " + item);
        if ("narrow" in item) require(Math.abs(Qt.color(item.borderSpec.color).a - 0.3) < 0.01, "menu alpha applied once without an explicit border color");
        for (var i = 0; i < item.children.length; i++) checkBorderless(item.children[i]);
    }
    function prepareSettingsPage(index) {
        controller.settingsCategoryIndex = index % 6;
        controller.hotCornerEnabled = true;
        controller.animationStyle = "slide";
        controller.separateTiming = true;
        window.width = index < 6 ? 1240 : (index < 12 ? 680 : 480);
        window.height = index < 6 ? 1040 : 760;
        samples.visible = false;
        card.visible = false;
    }
    function checkSettingsPage(index) {
        var items = settings.settingsFocusItems();
        var expectedCounts = [4, 3, 3, 3, 5, 8];
        require(items.length === expectedCounts[index % 6], "focusable controls on page " + index);
        settings.focusSettingsCategory();
        require(items[0].activeFocus, "category focus on page " + index);
        for (var i = 1; i < items.length; i++) {
            settings.moveSettingsFocus(true, false);
            require(items[i].activeFocus, "forward focus on page " + index + " control " + i);
            var page = items[i].parent;
            while (page && !(page instanceof Flickable)) page = page.parent;
            require(page !== null, "control belongs to a scrollable page");
            var point = items[i].mapToItem(page, 0, 0);
            require(point.y >= -1 && point.y + items[i].height <= page.height + 1, "focused control is visible on page " + index);
            require(point.x >= -1 && point.x + items[i].width <= page.width + 1, "control fits page width " + index);
        }
        settings.moveSettingsFocus(true, true);
        require(items[0].activeFocus, "Tab wraps to the category on page " + index);
        settings.moveSettingsFocus(false, true);
        require(items[items.length - 1].activeFocus, "Backtab wraps to the last control on page " + index);
        if (index % 6 === 4) {
            controller.hotCornerEnabled = false;
            require(settings.settingsFocusItems().length === 2, "disabled hot corner controls are skipped");
            controller.hotCornerEnabled = true;
        }
        if (index % 6 === 5) {
            controller.separateTiming = false;
            require(settings.settingsFocusItems().length === 6, "linked Slide hides separate controls");
            controller.animationStyle = "original";
            require(settings.settingsFocusItems().length === 5, "non-Slide hides directions");
            controller.animationStyle = "slide";
            controller.separateTiming = true;
        }
        settings.focusFirstSettingsControl();
    }
    function finish() {
        console.log("PASS: real shell theme tokens, views, compositor window borders, gradients, per-side widths, alpha, zero borders, live reload, settings layout and focus navigation");
        Qt.quit();
    }
    function require(condition, message) {
        if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw Error(message); }
    }
    function compositorBorders(width, active, inactive) {
        windowBorders.applySnapshot([
            JSON.stringify({option: "general:border_size", int: width}),
            JSON.stringify({option: "general:col.active_border", gradient: active}),
            JSON.stringify({option: "general:col.inactive_border", gradient: inactive})
        ].join("\n\n"));
    }
    Timer {
        id: testTimer
        interval: 350
        running: true
        repeat: true
        onTriggered: {
            if (test.phase === 0) {
                Color.loadUserShell("");
                Color.loadShell('[menu]\nbackground = "#18202b"\ntext = "#eff5ff"\nborder = "#ff6600 #44bbff 45deg"\nborder-width = "2 4 6 8"\nborder-alpha = 0.7\nscrim = "#101a20"\nscrim-alpha = 0.2\n[controls]\nnormal-color = "#b6dfff"\nnormal-fill-alpha = 0.12\nnormal-border = "#ff000080 #00ff0080 90deg"\nnormal-border-width = "1 2 3 4"\nnormal-border-width-left = 0\nnormal-border-alpha = 0.5\nhover-cursor-border-width = 0\nfocus-border-width = 0\nselected-border-width = 0\n[font]\nbase-size = 14\n[spacing]\ncontrol-height = 35\n');
                Style.cornerRadius = 12;
                compositorBorders(2, "ff4a9a68 ff44bbff 45deg", "aa595959 0deg");
                test.phase++;
            } else if (test.phase === 1) {
                require(normal.borderTop === 1 && normal.borderRight === 2 && normal.borderBottom === 3 && normal.borderLeft === 0, "per-side widths");
                require(normal.usesOverlayBorder && normal.borderSpec.gradient.enabled, "gradient renderer");
                require(Math.abs(normal.color.a - 0.12) < 0.01, "normal fill alpha");
                require(Math.abs(Qt.color(normal.borderSpec.gradient.colors[0]).a - 0.25) < 0.01, "border alpha");
                require(Border.isNone(hover.borderSpec) && Border.isNone(focus.borderSpec) && Border.isNone(selected.borderSpec), "zero state widths");
                require(card.outlineSpec.widths.left === 2, "idle window keeps compositor width");
                require(Math.abs(Qt.color(card.outlineSpec.color).a - 170 / 255) < 0.01, "inactive compositor alpha");
                card.hovered = true;
                require(card.outlineSpec.widths.left === 2 && card.outlineSpec.gradient.enabled, "hover uses active compositor gradient without doubling width");
                require(card.outlineSpec.gradient.angle === 45 && Qt.color(card.outlineSpec.gradient.colors[0]).r === Qt.color("#4a9a68").r, "ARGB conversion and angle");
                card.hovered = false;
                controller.selectedIndex = 0;
                controller.selectionScreenName = card.screenName;
                require(card.outlineSpec.widths.top === 2 && card.outlineSpec.gradient.enabled, "keyboard selection keeps window border despite zero control borders");
                windowBorders.applySnapshot("not json");
                compositorBorders(-1, "ff000000", "ff000000");
                compositorBorders(4, "invalid", "ff000000");
                require(card.outlineSpec.widths.top === 2, "invalid queries preserve last compositor state");
                require(normal.radius === 12 && Style.font.baseSize === 14 && Style.spacing.controlHeight === 35, "radius font and spacing");
                if (Quickshell.env("EXPOSE_THEME_OUTPUT_DIR"))
                    canvas.grabToImage(function(result) { result.saveToFile(Quickshell.env("EXPOSE_THEME_OUTPUT_DIR") + "/theme-dark.png"); });
                test.phase++;
            } else if (test.phase === 2) {
                Color.loadShell('[menu]\nbackground = "#f1f5fa"\ntext = "#172331"\nborder-width = 0\nborder-alpha = 0.3\n[controls]\nnormal-border-width = 0\nhover-cursor-border-width = 0\nfocus-border-width = 0\nselected-border-width = 0\nnormal-color = "#172331"\nnormal-fill-alpha = 0\nhover-cursor-color = "#365ca0"\nhover-cursor-fill-alpha = 0.1\nfocus-color = "#365ca0"\nfocus-fill-alpha = 0.1\nselected-color = "#1a6380"\nselected-fill-alpha = 0.15\n');
                Style.cornerRadius = 0;
                test.phase++;
            } else if (test.phase === 3) {
                require(normal.border.width === 0 && !normal.usesOverlayBorder, "borderless normal");
                require(card.outlineSpec.widths.top === 2, "borderless controls do not remove window borders");
                require(divider.width === 0, "borderless divider");
                require(normal.radius === 0 && normal.color.a === 0, "square transparent controls");
                checkBorderless(settings);
                checkBorderless(samples);
                compositorBorders(0, "0 0deg", "0 0deg");
                require(Border.isNone(card.outlineSpec) && Qt.color(card.outlineSpec.color).a === 0, "compositor zero width and transparent colors are respected");
                compositorBorders(3, "ff224466 0deg", "aa595959 0deg");
                require(card.outlineSpec.widths.top === 3 && !card.outlineSpec.gradient.enabled, "live compositor change replaces prior gradient and width");
                if (Quickshell.env("EXPOSE_THEME_OUTPUT_DIR"))
                    canvas.grabToImage(function(result) { result.saveToFile(Quickshell.env("EXPOSE_THEME_OUTPUT_DIR") + "/theme-light.png"); });
                test.phase++;
            } else if (test.phase === 4) {
                prepareSettingsPage(0);
                test.phase++;
            } else if (test.phase >= 5 && test.phase <= 22) {
                var index = test.phase - 5;
                checkSettingsPage(index);
                if (Quickshell.env("EXPOSE_THEME_OUTPUT_DIR")) {
                    var path = Quickshell.env("EXPOSE_THEME_OUTPUT_DIR") + "/settings-" + index + ".png";
                    testTimer.stop();
                    canvas.grabToImage(function(result) {
                        result.saveToFile(path);
                        if (index < 17) prepareSettingsPage(index + 1);
                        testTimer.start();
                    });
                } else if (index < 17) {
                    prepareSettingsPage(index + 1);
                }
                test.phase++;
            } else if (test.phase === 23) {
                finish();
            }
        }
    }
}
