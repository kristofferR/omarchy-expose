import QtQuick
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
    id: preview

    required property var modelData
    required property var controller
    required property int workspaceIndex

    property bool hovered: false

    readonly property real windowAspectRatio: {
        var ratio = Number(
            preview.controller.aspectRatioFor(
                preview.modelData
            )
        );

        return isFinite(ratio) && ratio > 0
            ? ratio
            : 1;
    }

    readonly property string windowTitle:
        String(
            preview.modelData.title
            || WindowModel.appIdFor(
                preview.modelData
            )
            || "Untitled window"
        )

    Rectangle {
        id: previewFrame

        anchors.centerIn: parent

        width: Math.max(
            1,
            Math.min(
                parent.width,
                parent.height
                    * preview.windowAspectRatio
            )
        )

        height: Math.max(
            1,
            Math.min(
                parent.height,
                parent.width
                    / preview.windowAspectRatio
            )
        )

        radius:
            Math.max(
                0,
                Style.cornerRadius
                    - Style.spacing.xs
            )

        color:
            Color.background

        clip: true

        Text {
            anchors.centerIn: parent

            width:
                Math.max(
                    1,
                    parent.width
                        - Style.spacing.md * 2
                )

            visible:
                !capture.hasContent

            text:
                preview.windowTitle

            textFormat:
                Text.PlainText

            color:
                Color.menu.text

            opacity:
                0.45

            font.family:
                Style.font.menuFamily

            font.pixelSize:
                Style.font.caption

            horizontalAlignment:
                Text.AlignHCenter

            elide:
                Text.ElideRight
        }

        Item {
            anchors.centerIn: parent

            width:
                parent.width * 2

            height:
                parent.height * 2

            scale: 0.5

            layer.enabled: true
            layer.smooth: true

            ScreencopyView {
                id: capture

                anchors.fill: parent

                captureSource:
                    WindowModel.waylandFor(
                        preview.modelData
                    )

                live:
                    preview.controller.opened
                    && preview.controller.overviewMode
                        === "workspaces"

                paintCursor: false
            }
        }

        Rectangle {
            anchors.fill: parent

            z: 2
            radius: parent.radius
            color: "transparent"

            border.color:
                preview.hovered
                    ? Color.menu.selectedText
                    : Color.menu.border

            border.width:
                preview.hovered
                    ? Math.max(
                        2,
                        Style.hoverBorderWidth
                    )
                    : Math.max(
                        1,
                        Style.normalBorderWidth
                    )
        }
    }

    MouseArea {
        anchors.fill: parent

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        onEntered: {
            preview.hovered = true;

            preview.controller.selectedWorkspaceIndex =
                preview.workspaceIndex;
        }

        onExited:
            preview.hovered = false

        onClicked:
            preview.controller.activate(
                preview.modelData
            )
    }
}
