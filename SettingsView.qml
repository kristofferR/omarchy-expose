import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: settingsView

    required property var controller
    required property var hostWindow
    readonly property var slideDirectionOptions: [
        { label: "Left", value: "left" },
        { label: "Right", value: "right" },
        { label: "Up", value: "up" },
        { label: "Down", value: "down" }
    ]

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
        readonly property real span: Math.max(0.000001, to - from)
        readonly property real normalizedValue: Math.max(0, Math.min(1, (value - from) / span))

        function valueAt(position) {
            var availableWidth = Math.max(1, sliderTrackArea.width - sliderHandle.width);
            var normalized = Math.max(0, Math.min(1, (position - sliderHandle.width / 2) / availableWidth));
            var raw = settingSlider.from + normalized * settingSlider.span;
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
            if (settingsView.controller.handleSettingsNavigation(event))
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
            if (settingsView.controller.handleSettingsNavigation(event))
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
            if (settingsView.controller.handleSettingsNavigation(event))
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
        property int categoryCount: 1
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
            categoryButton.chosen(Math.max(0, Math.min(categoryButton.categoryCount - 1, nextIndex)));
        }

        // The sidebar is a list: arrows along its axis pick a section, the
        // arrow pointing at the content (or Enter/Space) moves focus into it.
        Keys.onPressed: function (event) {
            if (settingsView.controller.handleSettingsTab(event))
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
                categoryButton.choose(categoryButton.categoryCount - 1);
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
            if (settingsView.controller.handleSettingsNavigation(event))
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
            if (settingsView.controller.handleSettingsNavigation(event))
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

    anchors.fill: parent

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
        var categoryButton = settingsCategoryRepeater.itemAt(settingsView.controller.settingsCategoryIndex);
        if (settingsView.controller.settingsCategoryIndex === 0)
            return settingsView.availableFocusItems([
                categoryButton,
                backgroundBlurSlider,
                backgroundDimSlider,
                bottomTextToggle
            ]);
        if (settingsView.controller.settingsCategoryIndex === 1)
            return settingsView.availableFocusItems([
                categoryButton,
                hotCornerToggle,
                hotCornerPositionChoices
            ]);
        if (settingsView.controller.settingsCategoryIndex === 2)
            return settingsView.availableFocusItems([
                categoryButton,
                previewPlacementChoices,
                windowFooterChoices,
                movePointerToggle,
                displayModeChoicesControl
            ]);
        return settingsView.availableFocusItems([
            categoryButton,
            motionAnimateButton,
            animationStyleChoices,
            slideDirectionChoices,
            slideDirectionInChoices,
            slideDirectionOutChoices,
            animationSpeedSlider,
            animationInSlider,
            animationOutSlider,
            animationSameSpeedToggle
        ]);
    }

    function footerConfirmationFocusItems() {
        return settingsView.availableFocusItems([
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
        settingsView.controller.focusSettingsItem(items[nextIndex]);
    }

    function focusSettingsCategory() {
        var categoryButton = settingsCategoryRepeater.itemAt(settingsView.controller.settingsCategoryIndex);
        if (categoryButton)
            categoryButton.forceActiveFocus();
    }

    function moveSettingsFocus(forward, wrap) {
        settingsView.moveFocus(settingsView.settingsFocusItems(), forward, 1, wrap);
    }

    function focusFirstSettingsControl() {
        var items = settingsView.settingsFocusItems();
        if (items.length > 1)
            settingsView.controller.focusSettingsItem(items[1]);
    }

    function moveFooterConfirmationFocus(forward, wrap) {
        settingsView.moveFocus(settingsView.footerConfirmationFocusItems(), forward, 0, wrap);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: settingsView.controller.closeSettings()
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
        enabled: !settingsView.controller.footerHideConfirmationOpen

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
                                categoryCount: settingsCategoryRepeater.count
                                label: String(modelData)
                                selected: settingsView.controller.settingsCategoryIndex === index
                                horizontal: settingsDialog.narrow
                                onChosen: function (nextIndex) {
                                    settingsView.controller.settingsCategoryIndex = nextIndex;
                                    var nextButton = settingsCategoryRepeater.itemAt(nextIndex);
                                    if (nextButton)
                                        nextButton.forceActiveFocus();
                                }
                                onEntered: settingsView.hostWindow.focusFirstSettingsControl()
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
                        visible: settingsView.controller.settingsCategoryIndex === 0
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
                                    value: settingsView.controller.effectiveBackgroundBlur
                                    suffix: " px"
                                    onEdited: function (value) { settingsView.controller.backgroundBlurPreview = value; }
                                    onCommitted: function (value) {
                                        settingsView.controller.backgroundBlurPreview = Math.round(value);
                                        settingsView.controller.setBackgroundBlur(value);
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
                                    value: settingsView.controller.effectiveBackgroundDim
                                    suffix: "%"
                                    onEdited: function (value) { settingsView.controller.backgroundDimPreview = value; }
                                    onCommitted: function (value) {
                                        settingsView.controller.backgroundDimPreview = Math.round(value);
                                        settingsView.controller.setBackgroundDim(value);
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
                                    checked: settingsView.controller.showFooter
                                    onToggled: function (checked) {
                                        if (checked)
                                            settingsView.controller.updatePluginSetting("showFooter", true);
                                        else
                                            settingsView.controller.requestFooterHide();
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
                        visible: settingsView.controller.settingsCategoryIndex === 1
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
                                    checked: settingsView.controller.hotCornerEnabled
                                    onToggled: function (checked) { settingsView.controller.setHotCornerEnabled(checked); }
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
                                    value: settingsView.controller.hotCornerPosition
                                    options: [
                                        { label: "TL", value: "top-left" },
                                        { label: "TR", value: "top-right" },
                                        { label: "BL", value: "bottom-left" },
                                        { label: "BR", value: "bottom-right" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setHotCornerPosition(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 2
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
                                    value: settingsView.controller.previewPlacement
                                    options: [
                                        { label: "In place", value: "in-place" },
                                        { label: "Centered", value: "centered" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setPreviewPlacement(value); }
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
                                    value: settingsView.controller.windowFooterStyle
                                    spacing: Style.spacing.md
                                    options: [
                                        { label: "Floating", value: "floating" },
                                        { label: "Rail", value: "integrated" },
                                        { label: "Overlay", value: "overlay" },
                                        { label: "Centered", value: "centered" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setWindowFooterStyle(value); }
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
                                    checked: settingsView.controller.moveCursorToWindow
                                    onToggled: function (checked) { settingsView.controller.setMoveCursorToWindow(checked); }
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
                                    value: settingsView.controller.multiMonitorMode
                                    onChosen: function (value) { settingsView.controller.setMultiMonitorMode(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 3
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
                                    onClicked: settingsView.controller.previewAnimation()
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
                                    value: settingsView.controller.animationStyle
                                    options: [
                                        { label: "Original", value: "original" },
                                        { label: "Fade", value: "fade" },
                                        { label: "Zoom", value: "zoom" },
                                        { label: "Slide", value: "slide" }
                                    ]
                                    onChosen: function (value) {
                                        settingsView.controller.clearAnimationTimingPreview();
                                        settingsView.controller.setAnimationStyle(value);
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && !settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Direction"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    id: slideDirectionChoices
                                    value: String(settingsView.controller.slideDirection["in"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirection(value); }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "In from"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    id: slideDirectionInChoices
                                    value: String(settingsView.controller.slideDirection["in"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirectionIn(value); }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Out to"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    id: slideDirectionOutChoices
                                    value: String(settingsView.controller.slideDirection["out"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirectionOut(value); }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationStyle === "slide"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
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
                                    value: settingsView.controller.animationInDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = value;
                                        settingsView.controller.animationOutDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDuration(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = next;
                                        settingsView.controller.animationOutDurationPreview = next;
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
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
                                    value: settingsView.controller.animationInDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDurationIn(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = next;
                                    }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
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
                                    value: settingsView.controller.animationOutDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationOutDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDurationOut(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationOutDurationPreview = next;
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    text: "Same in and out"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingToggle {
                                    id: animationSameSpeedToggle
                                    checked: !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                                    onToggled: function (checked) {
                                        settingsView.controller.clearAnimationTimingPreview();
                                        settingsView.controller.setAnimationTimingSeparate(settingsView.controller.animationStyle, !checked);
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
        visible: settingsView.controller.footerHideConfirmationOpen
        z: 10
        onVisibleChanged: {
            if (visible && settingsView.hostWindow.acceptsKeyboard)
                Qt.callLater(function () {
                    if (footerHideConfirmationLayer.visible)
                        footerHideAcknowledgement.forceActiveFocus();
                });
            else if (!visible && settingsView.controller.settingsOpen && settingsView.hostWindow.acceptsKeyboard)
                Qt.callLater(function () {
                    if (!settingsView.visible || footerHideConfirmationLayer.visible)
                        return;
                    if (settingsView.controller.settingsCategoryIndex === 0
                            && bottomTextToggle.visible && bottomTextToggle.enabled)
                        bottomTextToggle.forceActiveFocus();
                    else
                        settingsView.focusSettingsCategory();
                });
        }

        MouseArea {
            anchors.fill: parent
            onClicked: settingsView.controller.closeFooterHideConfirmation()
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
                        if (settingsView.controller.handleSettingsNavigation(event))
                            return;
                        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                            event.accepted = false;
                            return;
                        }
                        settingsView.controller.footerHideAcknowledged = !settingsView.controller.footerHideAcknowledged;
                        event.accepted = true;
                    }

                    RowLayout {
                        id: acknowledgementRow
                        anchors.fill: parent
                        spacing: Style.spacing.md

                        Rectangle {
                            Layout.preferredWidth: Style.space(18)
                            Layout.preferredHeight: Style.space(18)
                            color: settingsView.controller.footerHideAcknowledged ? Color.accent : "transparent"
                            border.color: footerHideAcknowledgement.activeFocus || settingsView.controller.footerHideAcknowledged
                                ? Color.accent
                                : Color.menu.border
                            border.width: footerHideAcknowledgement.activeFocus
                                ? Math.max(2, Style.focusBorderWidth)
                                : Math.max(1, Style.normalBorderWidth)

                            Text {
                                anchors.centerIn: parent
                                visible: settingsView.controller.footerHideAcknowledged
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
                        onClicked: settingsView.controller.footerHideAcknowledged = !settingsView.controller.footerHideAcknowledged
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
                        onClicked: settingsView.controller.closeFooterHideConfirmation()
                    }

                    DialogButton {
                        id: footerHideConfirmButton
                        label: "Hide bottom text"
                        destructive: true
                        enabled: settingsView.controller.footerHideAcknowledged
                        onClicked: settingsView.controller.confirmFooterHide()
                    }
                }
            }
        }
    }
}
