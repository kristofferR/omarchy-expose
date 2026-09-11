import QtQuick
import QtQuick.Layouts
import qs.Commons
import "WorkspaceModel.js" as WorkspaceModel

Rectangle {
    id: card

    required property var modelData
    required property int index
    required property var controller
    required property var windowsSource
    required property bool currentWorkspace

    property bool hovered: false
    property var previewWindows: []

    readonly property bool selected:
        card.index === card.controller.selectedWorkspaceIndex

    readonly property string workspaceLabel:
        WorkspaceModel.labelFor(card.modelData)

    readonly property int windowCount:
        card.previewWindows.length

    readonly property int previewColumns:
        Math.max(
            1,
            Math.ceil(
                Math.sqrt(
                    card.previewWindows.length
                )
            )
        )

    function syncPreviewWindows() {
        var next =
            card.windowsSource || [];

        // A Repeater over a JS array rebuilds its delegates when
        // the array object is reassigned. Keep the existing array
        // when membership and order are unchanged so live captures
        // are not unnecessarily recreated.
        if (!card.controller.toplevelListsEqual(
                card.previewWindows,
                next)) {
            card.previewWindows = next;
        }
    }

    onWindowsSourceChanged:
        card.syncPreviewWindows()

    Component.onCompleted:
        card.syncPreviewWindows()

    radius: Style.cornerRadius
    color: Color.menu.background

    border.color: card.selected
        ? Color.menu.selectedText
        : (card.currentWorkspace
            ? Color.accent
            : (card.hovered
                ? Color.menu.selectedText
                : Color.menu.border))

    border.width: card.selected
        ? Math.max(3, Style.focusBorderWidth)
        : (card.hovered
            ? Math.max(3, Style.hoverBorderWidth)
            : (card.currentWorkspace
                ? Math.max(2, Style.selectedBorderWidth)
                : Math.max(1, Style.normalBorderWidth)))

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            card.hovered = true;
            card.controller.selectedWorkspaceIndex = card.index;
        }

        onExited:
            card.hovered = false

        onClicked:
            card.controller.activateWorkspace(card.modelData)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.xl
        spacing: Style.spacing.md

        Text {
            Layout.fillWidth: true

            text:
                "Workspace "
                + card.workspaceLabel

            textFormat:
                Text.PlainText

            color:
                card.currentWorkspace
                    ? Color.accent
                    : Color.menu.text

            font.family:
                Style.font.menuFamily

            font.pixelSize:
                Style.font.heading

            font.bold: true

            horizontalAlignment:
                Text.AlignHCenter

            elide:
                Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                anchors.fill: parent

                // Avoid even constructing ScreencopyView instances
                // while normal Windows mode is active.
                active:
                    card.controller.opened
                    && card.controller.overviewMode
                        === "workspaces"
                    && card.previewWindows.length > 0

                sourceComponent: Component {
                    GridLayout {
                        anchors.fill: parent

                        columns:
                            card.previewColumns

                        rowSpacing:
                            Style.spacing.sm

                        columnSpacing:
                            Style.spacing.sm

                        Repeater {
                            model:
                                card.previewWindows

                            delegate:
                                WorkspaceWindowPreview {
                                    controller:
                                        card.controller

                                    workspaceIndex:
                                        card.index

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 1
                                }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent

                visible:
                    card.windowCount === 0

                text:
                    "No windows"

                textFormat:
                    Text.PlainText

                color:
                    Color.menu.text

                opacity:
                    0.45

                font.family:
                    Style.font.menuFamily

                font.pixelSize:
                    Style.font.bodySmall
            }
        }

        Text {
            Layout.fillWidth: true

            text:
                (card.currentWorkspace
                    ? "Current  ·  "
                    : "")
                + card.windowCount
                + (card.windowCount === 1
                    ? " window"
                    : " windows")

            textFormat:
                Text.PlainText

            color:
                Color.menu.text

            opacity:
                card.currentWorkspace
                    ? 0.85
                    : 0.58

            font.family:
                Style.font.menuFamily

            font.pixelSize:
                Style.font.bodySmall

            horizontalAlignment:
                Text.AlignHCenter

            elide:
                Text.ElideRight
        }
    }

}
