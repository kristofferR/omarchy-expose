import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "SettingsSchema.js" as SettingsSchema

Item {
    id: settingsView

    required property var controller
    required property var hostWindow
    readonly property var categories: ["Appearance", "Windows", "Window labels", "Workspaces", "Hot corners", "Motion"]
    readonly property int navigationColumns: settingsDialog.narrow ? (settingsDialog.width < Style.space(540) ? 2 : 3) : 1
    readonly property int navigationRows: Math.ceil(categories.length / navigationColumns)
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
        implicitHeight: Style.spacing.controlHeight
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
                    // The track is value geometry, not a border.
                    height: Style.space(2)
                    color: Style.normalFillFor(Commons.Color.menu.text, Commons.Color.accent)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * settingSlider.normalizedValue
                    height: Style.space(3)
                    color: Style.selectedStateColor(Commons.Color.menu.text, Commons.Color.accent)
                }

                ThemedControl {
                    id: sliderHandle
                    width: Style.space(12)
                    height: width
                    x: Math.round((parent.width - width) * settingSlider.normalizedValue)
                    anchors.verticalCenter: parent.verticalCenter
                    focused: settingSlider.activeFocus
                    hovered: sliderMouse.containsMouse
                    pressed: sliderMouse.pressed
                    color: stateColor
                }

                MouseArea {
                    id: sliderMouse
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
                color: sliderHandle.stateColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: settingSlider.activeFocus
            }
        }
    }

    component SettingChoices: Flow {
        id: settingChoices
        Layout.fillWidth: true
        property var options: []
        property string value: ""
        signal chosen(string nextValue)
        spacing: Style.spacing.md
        Layout.minimumWidth: 0
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

            delegate: ThemedControl {
                id: choice
                required property var modelData
                selected: String(modelData.value) === settingChoices.value
                focused: settingChoices.activeFocus && selected
                hovered: choiceMouse.containsMouse
                pressed: choiceMouse.pressed
                width: choiceLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                height: Math.max(Style.spacing.controlHeight, choiceLabel.implicitHeight + Style.spacing.controlPaddingY * 2)

                Text {
                    id: choiceLabel
                    anchors.centerIn: parent
                    text: String(choice.modelData.label)
                    textFormat: Text.PlainText
                    color: choice.stateColor
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    font.bold: choice.selected
                }

                MouseArea {
                    id: choiceMouse
                    anchors.fill: parent
                    hoverEnabled: true
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
        Layout.fillWidth: true
        property string value: "mirrored"
        signal chosen(string nextValue)
        readonly property var options: SettingsSchema.options("multiMonitorMode")
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
            var current = 0;
            for (var index = 0; index < displayModeChoices.options.length; index++)
                if (displayModeChoices.options[index].value === displayModeChoices.value)
                    current = index;
            if (event.key === Qt.Key_Left)
                displayModeChoices.choose(current - 1);
            else if (event.key === Qt.Key_Right)
                displayModeChoices.choose(current + 1);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                displayModeChoices.choose((current + 1) % displayModeChoices.options.length);
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Repeater {
            model: displayModeChoices.options

            delegate: ThemedControl {
                id: displayModeChoice
                required property var modelData
                selected: String(modelData.value) === displayModeChoices.value
                focused: displayModeChoices.activeFocus && selected
                hovered: displayModeMouse.containsMouse
                pressed: displayModeMouse.pressed
                Layout.fillWidth: true
                Layout.preferredHeight: displayModeText.implicitHeight + Style.spacing.md * 2

                ColumnLayout {
                    id: displayModeText
                    anchors.fill: parent
                    anchors.margins: Style.spacing.md
                    spacing: Style.spacing.xs

                    Text {
                        Layout.fillWidth: true
                        text: String(displayModeChoice.modelData.label)
                        textFormat: Text.PlainText
                        color: displayModeChoice.stateColor
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: displayModeChoice.selected
                    }

                    Text {
                        Layout.fillWidth: true
                        text: String(displayModeChoice.modelData.description)
                        textFormat: Text.PlainText
                        color: Commons.Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }
                }

                MouseArea {
                    id: displayModeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        displayModeChoices.forceActiveFocus();
                        displayModeChoices.chosen(String(displayModeChoice.modelData.value));
                    }
                }
            }
        }
    }

    component SettingsCategoryButton: ThemedControl {
        id: categoryButton
        property int categoryIndex: 0
        property int categoryCount: 1
        property string label: ""
        property bool horizontal: false
        property int navigationColumns: 1
        focused: activeFocus
        pressed: categoryMouse.pressed
        signal chosen(int nextIndex)
        implicitWidth: Style.space(horizontal ? 140 : 200)
        implicitHeight: Style.space(horizontal ? 52 : 48)
        activeFocusOnTab: selected

        signal entered()

        function choose(nextIndex) {
            categoryButton.chosen(Math.max(0, Math.min(categoryButton.categoryCount - 1, nextIndex)));
        }

        // Navigate the sidebar or wrapped category grid. Enter/Space moves
        // into the page; Down from the grid’s last row also enters it.
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
            else if (categoryButton.horizontal && event.key === Qt.Key_Up)
                categoryButton.choose(Math.max(0, categoryButton.categoryIndex - categoryButton.navigationColumns));
            else if (categoryButton.horizontal && event.key === Qt.Key_Down
                    && categoryButton.categoryIndex + categoryButton.navigationColumns < categoryButton.categoryCount)
                categoryButton.choose(categoryButton.categoryIndex + categoryButton.navigationColumns);
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
                color: categoryButton.stateColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: categoryButton.selected
            }

            Text {
                Layout.fillWidth: true
                text: categoryButton.label
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                color: categoryButton.stateColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: categoryButton.selected
                elide: Text.ElideRight
            }

        }

        MouseArea {
            id: categoryMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: categoryButton.hovered = true
            onExited: categoryButton.hovered = false
            onPressed: categoryButton.forceActiveFocus()
            onClicked: categoryButton.choose(categoryButton.categoryIndex)
        }
    }

    component SettingsDivider: ThemeDivider {}

    component SettingRow: ColumnLayout {
        id: settingRow
        default property alias controls: rowControls.data
        property string label: ""
        property string description: ""
        property bool stacked: settingsDialog.narrow
        objectName: "settingRow"
        Layout.fillWidth: true
        spacing: Style.spacing.sm
        opacity: enabled ? 1 : 0.45

        SettingsDivider { Layout.fillWidth: true }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.sm
            columns: settingRow.stacked ? 1 : 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.sm

            Text {
                Layout.fillWidth: true
                Layout.preferredWidth: settingRow.stacked ? -1 : Style.space(180)
                text: settingRow.label
                textFormat: Text.PlainText
                color: Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: rowControls
                Layout.fillWidth: true
                Layout.preferredWidth: Style.space(320)
                spacing: 0
            }
        }

        Text {
            Layout.fillWidth: true
            text: settingRow.description
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            opacity: 0.65
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }
    }

    // One corner in the Hot corners group: an icon of the corner, its label,
    // and its choices, without a divider or description of its own.
    component CornerRow: GridLayout {
        id: cornerRow
        default property alias controls: cornerControls.data
        property string label: ""
        property string position: ""
        objectName: "settingRow"
        Layout.fillWidth: true
        columns: settingsDialog.narrow ? 1 : 2
        columnSpacing: Style.spacing.md
        rowSpacing: Style.spacing.xs

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: settingsDialog.narrow ? -1 : Style.space(180)
            spacing: Style.spacing.sm

            Rectangle {
                implicitWidth: Style.space(16)
                implicitHeight: Style.space(12)
                radius: Style.space(2)
                color: "transparent"
                border.color: Commons.Color.menu.text
                border.width: 1
                opacity: 0.65

                Rectangle {
                    readonly property int inset: Style.space(2)
                    width: Style.space(5)
                    height: Style.space(4)
                    radius: 1
                    x: cornerRow.position.indexOf("-left") !== -1 ? inset : parent.width - width - inset
                    y: cornerRow.position.indexOf("top-") === 0 ? inset : parent.height - height - inset
                    color: Commons.Color.menu.text
                }
            }

            Text {
                Layout.fillWidth: true
                text: cornerRow.label
                textFormat: Text.PlainText
                color: Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
            }
        }

        GridLayout {
            id: cornerControls
            Layout.fillWidth: true
            Layout.preferredWidth: Style.space(320)
            // Rows without a command field still share widths with those that
            // have one, so every dropdown starts at the same x.
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            columns: settingsDialog.narrow ? 1 : 2
            columnSpacing: Style.spacing.sm
            rowSpacing: Style.spacing.xs
        }
    }

    // A corner's action: the current one on a button that opens the grouped
    // list. Left/Right step through the actions as SettingChoices do,
    // Space/Enter open the list, and Up/Down keep moving between controls.
    component SettingDropdown: ThemedControl {
        id: settingDropdown
        property var options: []
        property string value: ""
        signal chosen(string nextValue)
        readonly property int currentIndex: {
            for (var index = 0; index < settingDropdown.options.length; index++)
                if (String(settingDropdown.options[index].value) === settingDropdown.value)
                    return index;
            return -1;
        }
        focused: activeFocus || dropdownPopup.opened
        hovered: dropdownMouse.containsMouse
        pressed: dropdownMouse.pressed
        implicitWidth: Style.space(168)
        implicitHeight: Style.spacing.controlHeight
        activeFocusOnTab: true

        function step(offset) {
            var next = Math.max(0, Math.min(settingDropdown.options.length - 1, settingDropdown.currentIndex + offset));
            if (next !== settingDropdown.currentIndex)
                settingDropdown.chosen(String(settingDropdown.options[next].value));
        }

        Keys.onPressed: function (event) {
            if (settingsView.controller.handleSettingsNavigation(event))
                return;
            // Changing a corner can stall the shell past the key-repeat delay,
            // and the repeat would then skip an action; the list is the way
            // to move far.
            if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && event.isAutoRepeat) {
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Left)
                settingDropdown.step(-1);
            else if (event.key === Qt.Key_Right)
                settingDropdown.step(1);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dropdownPopup.open();
            else {
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Text {
            anchors.left: parent.left
            anchors.right: dropdownChevron.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.sm
            text: settingDropdown.currentIndex >= 0 ? String(settingDropdown.options[settingDropdown.currentIndex].label) : ""
            textFormat: Text.PlainText
            color: settingDropdown.stateColor
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
        }

        Text {
            id: dropdownChevron
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.spacing.controlPaddingX
            text: "▾"
            color: settingDropdown.stateColor
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
            id: dropdownMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: settingDropdown.forceActiveFocus()
            onClicked: dropdownPopup.opened ? dropdownPopup.close() : dropdownPopup.open()
        }

        Controls.Popup {
            id: dropdownPopup
            property int highlighted: 0
            y: settingDropdown.height + Style.spacing.xs
            width: Math.max(settingDropdown.width, Style.space(200))
            margins: Style.spacing.md
            padding: Style.spacing.xs
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent

            onOpened: {
                dropdownPopup.highlighted = Math.max(0, settingDropdown.currentIndex);
                dropdownList.forceActiveFocus();
            }
            onClosed: settingDropdown.forceActiveFocus()

            function choose(index) {
                dropdownPopup.close();
                if (index !== settingDropdown.currentIndex)
                    settingDropdown.chosen(String(settingDropdown.options[index].value));
            }

            background: Ui.BorderSurface {
                readonly property color menu: Commons.Color.menu.background
                radius: Style.cornerRadius
                color: Qt.rgba(menu.r, menu.g, menu.b, 1)
                borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.foreground, Style.normalBorderWidth)
            }

            contentItem: Column {
                id: dropdownList
                spacing: 0
                focus: true

                Keys.onPressed: function (event) {
                    var count = settingDropdown.options.length;
                    if (event.key === Qt.Key_Down)
                        dropdownPopup.highlighted = Math.min(count - 1, dropdownPopup.highlighted + 1);
                    else if (event.key === Qt.Key_Up)
                        dropdownPopup.highlighted = Math.max(0, dropdownPopup.highlighted - 1);
                    else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        dropdownPopup.choose(dropdownPopup.highlighted);
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                        dropdownPopup.close();
                    event.accepted = true;
                }

                Repeater {
                    model: settingDropdown.options

                    delegate: Column {
                        id: dropdownEntry
                        required property var modelData
                        required property int index
                        readonly property string group: String(modelData.group || "")
                        readonly property bool startsGroup: index === 0
                            || String(settingDropdown.options[index - 1].group || "") !== group
                        // Exposé's and Omarchy's actions get a heading; the
                        // single-entry groups after them only a divider.
                        readonly property bool headed: group === "Exposé" || group === "Omarchy"
                        width: parent ? parent.width : 0

                        ThemeDivider {
                            width: parent.width
                            visible: dropdownEntry.startsGroup && dropdownEntry.index > 0
                        }

                        Text {
                            visible: dropdownEntry.startsGroup && dropdownEntry.headed
                            leftPadding: Style.spacing.controlPaddingX
                            topPadding: Style.spacing.sm
                            bottomPadding: Style.spacing.xs
                            text: dropdownEntry.group
                            textFormat: Text.PlainText
                            color: Commons.Color.menu.text
                            opacity: 0.65
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.caption
                            font.capitalization: Font.AllUppercase
                        }

                        // A plain fill per row, as the shell's own Dropdown
                        // draws them; a bordered control per row reads as a
                        // stack of buttons under themes with control borders.
                        Rectangle {
                            id: dropdownRow
                            readonly property bool selected: dropdownEntry.index === settingDropdown.currentIndex
                            readonly property bool highlighted: dropdownEntry.index === dropdownPopup.highlighted
                            readonly property color stateColor: highlighted
                                ? Style.hoverStateColor(Commons.Color.menu.text, Commons.Color.accent)
                                : selected ? Style.selectedStateColor(Commons.Color.menu.text, Commons.Color.accent)
                                : Commons.Color.menu.text
                            width: parent.width
                            height: Style.spacing.controlHeight
                            radius: Style.cornerRadius
                            color: highlighted ? Style.hoverFillFor(Commons.Color.menu.text, Commons.Color.accent)
                                : selected ? Style.selectedFillFor(Commons.Color.menu.text, Commons.Color.accent)
                                : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Style.spacing.controlPaddingX
                                text: String(dropdownEntry.modelData.label)
                                textFormat: Text.PlainText
                                color: dropdownRow.stateColor
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: dropdownRow.selected
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: Style.spacing.controlPaddingX
                                visible: text !== ""
                                text: String(dropdownEntry.modelData.hint || "")
                                textFormat: Text.PlainText
                                color: Commons.Color.menu.text
                                opacity: 0.65
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: dropdownPopup.highlighted = dropdownEntry.index
                                onClicked: dropdownPopup.choose(dropdownEntry.index)
                            }
                        }
                    }
                }
            }
        }
    }

    // The shell command a corner runs, saved on Enter or when focus leaves.
    component SettingCommandField: Ui.TextField {
        id: commandField
        property string position: ""
        foreground: Commons.Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        placeholderText: "Shell command"
        activeFocusOnTab: true

        // Follows the stored command except while being edited.
        Binding on text {
            when: !commandField.activeFocus
            value: settingsView.controller.hotCornerCommands[commandField.position] || ""
            restoreMode: Binding.RestoreNone
        }

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                    || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                settingsView.controller.handleSettingsNavigation(event);
            // Escape closes settings before the field loses focus, which
            // would drop the edit, so it is saved first and Escape goes on.
            else if (event.key === Qt.Key_Escape) {
                settingsView.controller.setHotCornerCommand(commandField.position, commandField.text);
                event.accepted = false;
            }
        }
        onEditingFinished: settingsView.controller.setHotCornerCommand(commandField.position, commandField.text)
    }

    component SettingsPage: Flickable {
        id: settingsPage
        default property alias settings: pageColumn.data
        property int categoryIndex: 0
        property string title: ""
        anchors.fill: parent
        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
        visible: settingsView.controller.settingsCategoryIndex === categoryIndex
        enabled: visible
        clip: true
        contentWidth: width
        contentHeight: pageColumn.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        function reveal(item) {
            var row = item;
            while (row.parent && row.parent !== settingsPage.contentItem && row.objectName !== "settingRow")
                row = row.parent;
            var top = row.mapToItem(settingsPage.contentItem, 0, 0).y;
            var bottom = top + row.height;
            if (top < contentY || row.height > height)
                contentY = Math.max(0, top);
            else if (bottom > contentY + height)
                contentY = Math.min(Math.max(0, contentHeight - height), bottom - height);
        }

        Rectangle {
            parent: settingsPage
            anchors.right: parent.right
            width: Style.space(2)
            height: settingsPage.height * settingsPage.visibleArea.heightRatio
            y: settingsPage.height * settingsPage.visibleArea.yPosition
            color: Commons.Color.menu.text
            opacity: 0.35
            visible: settingsPage.contentHeight > settingsPage.height
        }

        ColumnLayout {
            id: pageColumn
            width: settingsPage.width - Style.spacing.md
            spacing: Style.spacing.lg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                Text {
                    Layout.fillWidth: true
                    text: settingsView.categories[settingsPage.categoryIndex]
                    textFormat: Text.PlainText
                    color: Commons.Color.accent
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                }

                Text {
                    Layout.fillWidth: true
                    text: settingsPage.title
                    textFormat: Text.PlainText
                    color: Commons.Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    function revealSettingsItem(item) {
        for (var parent = item.parent; parent; parent = parent.parent) {
            if (parent instanceof Flickable) {
                parent.reveal(item);
                return;
            }
        }
    }

    component SettingToggle: Item {
        id: settingToggle
        property bool checked: false
        signal toggled(bool checked)
        implicitWidth: Style.space(72)
        implicitHeight: Style.spacing.controlHeight
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
            color: Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
        }

        ThemedControl {
            id: toggleTrack
            selected: settingToggle.checked
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: Style.space(14)

            Rectangle {
                width: Style.space(10)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                x: settingToggle.checked ? parent.width - width - Style.space(2) : Style.space(2)
                color: toggleTrack.stateColor
                radius: Math.min(Style.cornerRadius, height / 2)
                Behavior on x { NumberAnimation { duration: Style.duration(100) } }
            }
        }

        ThemedControl {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            visible: settingToggle.activeFocus
            focused: true
            color: "transparent"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: settingToggle.forceActiveFocus()
            onClicked: settingToggle.toggled(!settingToggle.checked)
        }
    }

    component DialogButton: ThemedControl {
        id: dialogButton
        property string label: ""
        property bool destructive: false
        focused: activeFocus
        pressed: dialogMouse.pressed
        signal clicked()
        implicitWidth: buttonLabel.implicitWidth + Style.spacing.controlPaddingX * 2
        implicitHeight: Math.max(Style.spacing.controlHeight, buttonLabel.implicitHeight + Style.spacing.controlPaddingY * 2)
        activeFocusOnTab: true
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
            color: dialogButton.destructive ? Commons.Color.urgent : dialogButton.stateColor
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: dialogButton.destructive
        }

        MouseArea {
            id: dialogMouse
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

    // Desktop works only on floating workspaces, so the corner group says so
    // while any corner uses it.
    readonly property bool desktopCornerUsed: {
        var actions = settingsView.controller.hotCornerActions;
        for (var position in actions)
            if (actions[position] === "desktop")
                return true;
        return false;
    }

    function settingsFocusItems() {
        var categoryButton = settingsCategoryRepeater.itemAt(settingsView.controller.settingsCategoryIndex);
        var controls = [
            [backgroundModeChoices, backgroundBlurSlider, backgroundDimSlider, bottomTextToggle],
            [selectionStyleChoices, previewPlacementChoices, movePointerToggle, closeButtonToggle, closeButtonSideChoices],
            [windowFooterChoices, workspaceLabelStyleChoices],
            [initialWorkspaceScopeChoices, displayModeChoicesControl, workspaceStripToggle, workspaceDragToggle],
            [hotCornerToggle, hotCornerTopLeftAction, hotCornerTopLeftCommand, hotCornerTopRightAction, hotCornerTopRightCommand, hotCornerBottomLeftAction, hotCornerBottomLeftCommand, hotCornerBottomRightAction, hotCornerBottomRightCommand, hotCornerAllDisplaysToggle, hotCornerIgnoreFullscreenToggle, hotCornerDelaySlider],
            [motionAnimateButton, animationStyleChoices, animationSameSpeedToggle, slideDirectionChoices, slideDirectionInChoices, slideDirectionOutChoices, animationSpeedSlider, animationInSlider, animationOutSlider]
        ];
        return settingsView.availableFocusItems([categoryButton].concat(controls[settingsView.controller.settingsCategoryIndex] || []));
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
        settingsView.revealSettingsItem(items[nextIndex]);
    }

    // Whether keyboard focus is on a visible item inside the settings.
    function holdsFocus() {
        var item = settingsView.Window.activeFocusItem;
        if (!item || !item.visible)
            return false;
        for (; item; item = item.parent)
            if (item === settingsView)
                return true;
        return false;
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
        if (items.length > 1) {
            settingsView.controller.focusSettingsItem(items[1]);
            settingsView.revealSettingsItem(items[1]);
        }
    }

    function moveFooterConfirmationFocus(forward, wrap) {
        settingsView.moveFocus(settingsView.footerConfirmationFocusItems(), forward, 0, wrap);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: settingsView.controller.closeSettings()
    }

    Ui.BorderSurface {
        id: settingsDialog
        readonly property bool narrow: width < Style.space(760)
        anchors.centerIn: parent
        width: Math.min(Style.space(920), parent.width - Style.space(80))
        height: Math.min(Style.space(narrow ? 720 : 640), parent.height - Style.space(80))
        radius: Style.cornerRadius
        color: Commons.Color.menu.background
        borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.foreground, Style.normalBorderWidth)
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
                        color: Commons.Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !settingsDialog.narrow
                        text: "1–6 section   ↑↓ move   ←→ adjust   Esc close"
                        textFormat: Text.PlainText
                        color: Commons.Color.menu.text
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
                    Layout.preferredHeight: settingsDialog.narrow ? Style.space(52) * settingsView.navigationRows : 0

                    GridLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        columns: settingsView.navigationColumns
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            id: settingsCategoryRepeater
                            model: settingsView.categories

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
                                navigationColumns: settingsView.navigationColumns
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

                    ThemeDivider {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        vertical: !settingsDialog.narrow
                        width: vertical ? implicitWidth : parent.width
                        height: vertical ? parent.height : implicitHeight
                    }
                }

                Item {
                    id: settingsCategoryContent
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    SettingsPage {
                        categoryIndex: 0
                        title: "Backdrop and bottom text"

                        SettingRow {
                            label: "Background"
                            description: "Show the desktop or your current Omarchy wallpaper behind the window cards. Wallpaper covers the original windows."

                            SettingChoices {
                                id: backgroundModeChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.backgroundMode
                                options: SettingsSchema.options("backgroundMode")
                                onChosen: function (value) { settingsView.controller.setSetting("backgroundMode", value); }
                            }
                        }

                        SettingRow {
                            label: "Background blur"
                            description: "Soften the selected background behind the overview. Set to 0 for no blur."

                            SettingSlider {
                                id: backgroundBlurSlider
                                Layout.fillWidth: true
                                from: SettingsSchema.spec("backgroundBlur").min
                                to: SettingsSchema.spec("backgroundBlur").max
                                value: settingsView.controller.effectiveBackgroundBlur
                                suffix: " px"
                                onEdited: function (value) { settingsView.controller.backgroundBlurPreview = value; }
                                onCommitted: function (value) {
                                    settingsView.controller.backgroundBlurPreview = Math.round(value);
                                    settingsView.controller.setSetting("backgroundBlur", value);
                                }
                            }
                        }

                        SettingRow {
                            label: "Background dim"
                            description: "Darken the selected background behind the overview. Higher values make it darker."

                            SettingSlider {
                                id: backgroundDimSlider
                                Layout.fillWidth: true
                                from: SettingsSchema.spec("backgroundDim").min
                                to: SettingsSchema.spec("backgroundDim").max
                                value: settingsView.controller.effectiveBackgroundDim
                                suffix: "%"
                                onEdited: function (value) { settingsView.controller.backgroundDimPreview = value; }
                                onCommitted: function (value) {
                                    settingsView.controller.backgroundDimPreview = Math.round(value);
                                    settingsView.controller.setSetting("backgroundDim", value);
                                }
                            }
                        }

                        SettingRow {
                            label: "Bottom text"
                            description: "Show keyboard hints and the Settings link below the grid. Hiding it requires confirmation."

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: bottomTextToggle
                                checked: settingsView.controller.showFooter
                                onToggled: function (checked) {
                                    if (checked)
                                        settingsView.controller.setSetting("showFooter", true);
                                    else
                                        settingsView.controller.requestFooterHide();
                                }
                            }
                        }
                    }

                    SettingsPage {
                        categoryIndex: 1
                        title: "Quick Look and activation"

                        SettingRow {
                            label: "Selection highlight"
                            description: "Outline borders the selected, hovered, and current windows alike. Lift raises only the window Enter opens and marks the current window with a dot."

                            SettingChoices {
                                id: selectionStyleChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.selectionStyle
                                options: SettingsSchema.options("selectionStyle")
                                onChosen: function (value) { settingsView.controller.setSetting("selectionStyle", value); }
                            }
                        }

                        SettingRow {
                            label: "Quick Look position"
                            description: "When you press Space, enlarge the preview near its card or at the center of the display."

                            SettingChoices {
                                id: previewPlacementChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.previewPlacement
                                options: SettingsSchema.options("previewPlacement")
                                onChosen: function (value) { settingsView.controller.setSetting("previewPlacement", value); }
                            }
                        }

                        SettingRow {
                            label: "Move pointer to window"
                            description: "Move the pointer to the window you activate from the overview."

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: movePointerToggle
                                checked: settingsView.controller.moveCursorToWindow
                                onToggled: function (checked) { settingsView.controller.setSetting("moveCursorToWindow", checked); }
                            }
                        }

                        SettingRow {
                            label: "Close button"
                            description: "Show a ✕ on the window under the pointer that closes it, like middle-click or Shift+Q."

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: closeButtonToggle
                                checked: settingsView.controller.closeButton
                                onToggled: function (checked) { settingsView.controller.setSetting("closeButton", checked); }
                            }
                        }

                        SettingRow {
                            label: "Close button side"
                            description: "Put the ✕ in the window's top left or top right corner."
                            enabled: settingsView.controller.closeButton

                            SettingChoices {
                                id: closeButtonSideChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.closeButtonSide
                                options: SettingsSchema.options("closeButtonSide")
                                onChosen: function (value) { settingsView.controller.setSetting("closeButtonSide", value); }
                            }
                        }
                    }

                    SettingsPage {
                        categoryIndex: 2
                        title: "Titles and workspace names"

                        SettingRow {
                            label: "Window labels"
                            description: "Choose how the app, title, and workspace label sit around each preview."

                            SettingChoices {
                                id: windowFooterChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.windowFooterStyle
                                spacing: Style.spacing.md
                                options: SettingsSchema.options("windowFooterStyle")
                                onChosen: function (value) { settingsView.controller.setSetting("windowFooterStyle", value); }
                            }
                        }

                        SettingRow {
                            label: "Workspace names"
                            description: "Slot only shortens names such as “Monitor:3” to “3”. Other names stay unchanged."

                            SettingChoices {
                                id: workspaceLabelStyleChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.workspaceLabelStyle
                                options: SettingsSchema.options("workspaceLabelStyle")
                                onChosen: function (value) { settingsView.controller.setSetting("workspaceLabelStyle", value); }
                            }
                        }
                    }

                    SettingsPage {
                        categoryIndex: 3
                        title: "Which windows you see"

                        SettingRow {
                            label: "Open with"
                            description: "Choose which workspaces are shown when Exposé opens. Press Tab in the overview to switch."

                            SettingChoices {
                                id: initialWorkspaceScopeChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.initialWorkspaceScope
                                options: SettingsSchema.options("initialWorkspaceScope")
                                onChosen: function (value) { settingsView.controller.setSetting("initialWorkspaceScope", value); }
                            }
                        }

                        SettingRow {
                            label: "Windows to include"
                            description: "Choose one grid on the opening display, or a grid on every display. With Current, each grid uses its display's active workspace."
                            stacked: true

                            DisplayModeChoices {
                                id: displayModeChoicesControl
                                Layout.fillWidth: true
                                value: settingsView.controller.multiMonitorMode
                                onChosen: function (value) { settingsView.controller.setSetting("multiMonitorMode", value); }
                            }
                        }

                        SettingRow {
                            label: "Workspace strip"
                            description: "Show this display's workspaces above the windows. Click one, or press 1–9 and 0 before typing a filter, to switch to it. + adds an empty workspace to the strip."

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: workspaceStripToggle
                                checked: settingsView.controller.workspaceStrip
                                onToggled: function (checked) { settingsView.controller.setSetting("workspaceStrip", checked); }
                            }
                        }

                        SettingRow {
                            label: "Drag windows to workspaces"
                            description: "Drop a window on a workspace in the strip, or on +, to move it there. Exposé stays open; Escape cancels a drag."
                            enabled: settingsView.controller.workspaceStrip

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: workspaceDragToggle
                                checked: settingsView.controller.workspaceDrag
                                onToggled: function (checked) { settingsView.controller.setSetting("workspaceDrag", checked); }
                            }
                        }
                    }

                    SettingsPage {
                        categoryIndex: 4
                        title: "Activate from a corner"

                        SettingRow {
                            label: "Enable hot corners"
                            description: "Move the pointer into a corner to run its action."

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: hotCornerToggle
                                checked: settingsView.controller.hotCornerEnabled
                                onToggled: function (checked) { settingsView.controller.setSetting("hotCornerEnabled", checked); }
                            }
                        }

                        // The four corners form one compact group, with a note while Desktop is used.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: settingsDialog.narrow ? Style.spacing.lg : Style.spacing.sm
                            enabled: settingsView.controller.hotCornerEnabled
                            opacity: enabled ? 1 : 0.45

                            SettingsDivider { Layout.fillWidth: true }

                            CornerRow {
                                Layout.topMargin: Style.spacing.sm
                                label: "Top left"
                                position: "top-left"

                                SettingDropdown {
                                    id: hotCornerTopLeftAction
                                    Layout.fillWidth: settingsDialog.narrow
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    value: settingsView.controller.hotCornerActions["top-left"]
                                    options: SettingsSchema.cornerActionOptions()
                                    onChosen: function (value) { settingsView.controller.setHotCornerAction("top-left", value); }
                                }

                                SettingCommandField {
                                    id: hotCornerTopLeftCommand
                                    Layout.fillWidth: true
                                    position: "top-left"
                                    visible: settingsView.controller.hotCornerActions["top-left"] === "command"
                                }
                            }

                            CornerRow {
                                label: "Top right"
                                position: "top-right"

                                SettingDropdown {
                                    id: hotCornerTopRightAction
                                    Layout.fillWidth: settingsDialog.narrow
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    value: settingsView.controller.hotCornerActions["top-right"]
                                    options: SettingsSchema.cornerActionOptions()
                                    onChosen: function (value) { settingsView.controller.setHotCornerAction("top-right", value); }
                                }

                                SettingCommandField {
                                    id: hotCornerTopRightCommand
                                    Layout.fillWidth: true
                                    position: "top-right"
                                    visible: settingsView.controller.hotCornerActions["top-right"] === "command"
                                }
                            }

                            CornerRow {
                                label: "Bottom left"
                                position: "bottom-left"

                                SettingDropdown {
                                    id: hotCornerBottomLeftAction
                                    Layout.fillWidth: settingsDialog.narrow
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    value: settingsView.controller.hotCornerActions["bottom-left"]
                                    options: SettingsSchema.cornerActionOptions()
                                    onChosen: function (value) { settingsView.controller.setHotCornerAction("bottom-left", value); }
                                }

                                SettingCommandField {
                                    id: hotCornerBottomLeftCommand
                                    Layout.fillWidth: true
                                    position: "bottom-left"
                                    visible: settingsView.controller.hotCornerActions["bottom-left"] === "command"
                                }
                            }

                            CornerRow {
                                label: "Bottom right"
                                position: "bottom-right"

                                SettingDropdown {
                                    id: hotCornerBottomRightAction
                                    Layout.fillWidth: settingsDialog.narrow
                                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                                    value: settingsView.controller.hotCornerActions["bottom-right"]
                                    options: SettingsSchema.cornerActionOptions()
                                    onChosen: function (value) { settingsView.controller.setHotCornerAction("bottom-right", value); }
                                }

                                SettingCommandField {
                                    id: hotCornerBottomRightCommand
                                    Layout.fillWidth: true
                                    position: "bottom-right"
                                    visible: settingsView.controller.hotCornerActions["bottom-right"] === "command"
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: Style.spacing.xs
                                visible: settingsView.desktopCornerUsed
                                text: "Desktop moves windows aside on floating workspaces only. Tiled workspaces stay as they are."
                                textFormat: Text.PlainText
                                color: Commons.Color.menu.text
                                opacity: 0.65
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                            }
                        }

                        SettingRow {
                            label: "Use on all displays"
                            description: "When off, each corner works only on the outermost display on its side."
                            enabled: settingsView.controller.hotCornerEnabled

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: hotCornerAllDisplaysToggle
                                checked: settingsView.controller.hotCornerAllDisplays
                                onToggled: function (checked) { settingsView.controller.setSetting("hotCornerAllDisplays", checked); }
                            }
                        }

                        SettingRow {
                            label: "Ignore fullscreen windows"
                            description: "When on, corners do nothing on a display showing a fullscreen window, such as a video or a game. They still close Exposé and Desktop."
                            enabled: settingsView.controller.hotCornerEnabled

                            Item { Layout.fillWidth: true }

                            SettingToggle {
                                id: hotCornerIgnoreFullscreenToggle
                                checked: settingsView.controller.hotCornerIgnoreFullscreen
                                onToggled: function (checked) { settingsView.controller.setSetting("hotCornerIgnoreFullscreen", checked); }
                            }
                        }

                        SettingRow {
                            label: "Activation delay"
                            description: "How long the pointer must stay in a corner. 0 acts on contact."
                            enabled: settingsView.controller.hotCornerEnabled

                            SettingSlider {
                                id: hotCornerDelaySlider
                                Layout.fillWidth: true
                                from: SettingsSchema.spec("hotCornerDelay").min
                                to: SettingsSchema.spec("hotCornerDelay").max
                                stepSize: 25
                                value: settingsView.controller.effectiveHotCornerDelay
                                suffix: " ms"
                                onEdited: function (value) { settingsView.controller.hotCornerDelayPreview = value; }
                                onCommitted: function (value) {
                                    settingsView.controller.hotCornerDelayPreview = settingsView.controller.setSetting("hotCornerDelay", value);
                                }
                            }
                        }
                    }

                    SettingsPage {
                        categoryIndex: 5
                        title: "Opening and closing"

                        DialogButton {
                            id: motionAnimateButton
                            Layout.alignment: Qt.AlignRight
                            label: "Preview animation"
                            onClicked: settingsView.controller.previewAnimation()
                        }

                        SettingRow {
                            label: "Animation style"
                            description: Style.reduceMotion
                                ? "Omarchy's animations are off, so the overview appears and disappears at once. Turn them on with omarchy toggle animations."
                                : "Choose how the overview opens and closes. Each style remembers its own timing."

                            SettingChoices {
                                id: animationStyleChoices
                                Layout.fillWidth: true
                                value: settingsView.controller.animationStyle
                                options: SettingsSchema.options("animationStyle")
                                onChosen: function (value) {
                                    settingsView.controller.clearAnimationTimingPreview();
                                    settingsView.controller.setSetting("animationStyle", value);
                                }
                            }
                        }

                        SettingRow {
                            label: "Same opening and closing"
                            description: "Use the same duration for both transitions. For Slide, this also links their directions."

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

                        SettingRow {
                            label: "Slide edge"
                            description: "The edge the overview slides in from and out to."
                            visible: settingsView.controller.animationStyle === "slide" && !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

                            SettingChoices {
                                id: slideDirectionChoices
                                Layout.fillWidth: true
                                value: String(settingsView.controller.slideDirection["in"])
                                options: settingsView.slideDirectionOptions
                                onChosen: function (value) { settingsView.controller.setSlideDirection(value); }
                            }
                        }

                        SettingRow {
                            label: "Slide in from"
                            description: "The edge the overview enters from when opening."
                            visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

                            SettingChoices {
                                id: slideDirectionInChoices
                                Layout.fillWidth: true
                                value: String(settingsView.controller.slideDirection["in"])
                                options: settingsView.slideDirectionOptions
                                onChosen: function (value) { settingsView.controller.setSlideDirectionIn(value); }
                            }
                        }

                        SettingRow {
                            label: "Slide out to"
                            description: "The edge the overview leaves through when closing."
                            visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

                            SettingChoices {
                                id: slideDirectionOutChoices
                                Layout.fillWidth: true
                                value: String(settingsView.controller.slideDirection["out"])
                                options: settingsView.slideDirectionOptions
                                onChosen: function (value) { settingsView.controller.setSlideDirectionOut(value); }
                            }
                        }

                        SettingRow {
                            label: "Duration"
                            description: "Time for each transition. Lower values are faster; higher values are slower."
                            visible: !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

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

                        SettingRow {
                            label: "Opening duration"
                            description: "Time taken to open the overview. Lower values are faster."
                            visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

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

                        SettingRow {
                            label: "Closing duration"
                            description: "Time taken to close the overview. Lower values are faster."
                            visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate

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
                        color: Commons.Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !settingsDialog.narrow
                        text: "1–6 category   Tab controls"
                        textFormat: Text.PlainText
                        color: Commons.Color.menu.text
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
            color: Commons.Color.menu.scrim
        }

        Ui.BorderSurface {
            id: footerHideDialog
            anchors.centerIn: parent
            width: Math.min(Style.space(560), parent.width - Style.space(80))
            height: Math.min(parent.height - Style.space(80), footerHideContent.implicitHeight + Style.space(56))
            radius: Style.cornerRadius
            color: Commons.Color.menu.background
            borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.foreground, Style.normalBorderWidth)

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
                    color: Commons.Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "This also hides the Settings link. You can turn it back on while this panel remains open."
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Commons.Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                }

                ThemedControl {
                    Layout.fillWidth: true
                    Layout.preferredHeight: recoveryText.implicitHeight + Style.space(24)

                    Text {
                        id: recoveryText
                        anchors.fill: parent
                        anchors.margins: Style.space(12)
                        text: "After closing Settings, restore it by running: omarchy-shell expose showFooter on"
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Commons.Color.menu.text
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

                        ThemedControl {
                            id: acknowledgementBox
                            Layout.preferredWidth: Style.space(18)
                            Layout.preferredHeight: Style.space(18)
                            selected: settingsView.controller.footerHideAcknowledged
                            focused: footerHideAcknowledgement.activeFocus

                            Text {
                                anchors.centerIn: parent
                                visible: settingsView.controller.footerHideAcknowledged
                                text: "✓"
                                textFormat: Text.PlainText
                                color: acknowledgementBox.stateColor
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                        }

                        Text {
                            id: acknowledgementText
                            Layout.fillWidth: true
                            text: "I understand that restoring it after closing Settings requires running a command."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: Commons.Color.menu.text
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
