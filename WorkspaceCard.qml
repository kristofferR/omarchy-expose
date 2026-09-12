import QtQuick
import QtQuick.Layouts
import qs.Commons
import "WorkspaceModel.js" as WorkspaceModel

Rectangle {
    id: card

    required property var modelData
    required property int index
    required property var controller
    required property int windowCount
    required property bool currentWorkspace

    property bool hovered: false

    readonly property bool selected:
        card.index === card.controller.selectedWorkspaceIndex

    readonly property string workspaceLabel:
        WorkspaceModel.labelFor(card.modelData)

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
        spacing: Style.spacing.sm

        Item {
            Layout.fillHeight: true
        }

        Text {
            Layout.fillWidth: true

            text: "Workspace " + card.workspaceLabel
            textFormat: Text.PlainText

            color: card.currentWorkspace
                ? Color.accent
                : Color.menu.text

            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true

            text: (card.currentWorkspace ? "Current  ·  " : "")
                + card.windowCount
                + (card.windowCount === 1 ? " window" : " windows")

            textFormat: Text.PlainText
            color: Color.menu.text

            opacity:
                card.currentWorkspace ? 0.85 : 0.58

            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
