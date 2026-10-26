import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Wayland
import "WindowModel.js" as WindowModel
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BorderSurface {
    id: card

    required property var modelData
    required property var controller
    required property var screenToplevels
    required property bool acceptsKeyboard
    required property var windowLayout
    required property real layoutAreaWidth
    required property real layoutAreaHeight
    // Position in the filtered list; -1 hides the card.
    readonly property int slot: card.screenToplevels.indexOf(modelData)
    readonly property bool inLayout: slot >= 0
    property bool hovered: false
    readonly property bool selected: card.acceptsKeyboard && inLayout && modelData === card.controller.selection
    // The window the overview was opened from; the overlay holds focus while open.
    readonly property bool focusedWindow: modelData === card.controller.originToplevel
    readonly property bool previewed: card.acceptsKeyboard && inLayout && modelData === card.controller.previewToplevel
    readonly property bool exitingPreview: card.acceptsKeyboard && inLayout && modelData === card.controller.previewExitToplevel
    readonly property bool floatingFooter: card.controller.windowFooterStyle === "floating"
    readonly property bool integratedFooter: card.controller.windowFooterStyle === "integrated"
    readonly property bool overlayFooter: card.controller.windowFooterStyle === "overlay"
    readonly property bool centeredFooter: card.controller.windowFooterStyle === "centered"
    readonly property string windowTitle: String(modelData.title || WindowModel.appIdFor(modelData) || "Untitled window")
    readonly property string applicationName: WindowModel.appIdFor(modelData) || "Application"
    readonly property string workspaceName: card.controller.workspaceName(modelData)
    readonly property string iconSource: card.controller.iconFor(modelData)
    // Lift marks only the selection, which is what Enter opens; the window the
    // overview was opened from gets a dot instead of sharing the active border.
    readonly property bool liftSelection: card.controller.selectionStyle === "lift"
    readonly property bool lifted: liftSelection && selected && !previewed
    readonly property bool outlined: liftSelection ? selected : (hovered || selected || focusedWindow)
    readonly property var outlineSpec: !outlined
        ? controller.windowBorders.inactiveSpec
        : (liftSelection ? liftRingSpec : controller.windowBorders.activeSpec)
    readonly property var liftRingSpec: {
        var active = controller.windowBorders.activeSpec;
        var ring = Border.flat(active.color, Math.max(3, controller.windowBorders.snapshot.width + 1));
        ring.gradient = active.gradient;
        return ring;
    }
    readonly property color currentColor: Style.selectedStateColor(Commons.Color.menu.text, Commons.Color.accent)
    // An excluded card keeps its last rectangle, so it neither
    // animates toward the origin nor flies back in from it.
    readonly property var packedRectSource: inLayout ? card.windowLayout[slot] : null
    property var packedRect: Qt.rect(0, 0, 1, 1)
    readonly property var previewRect: card.controller.previewRectFor(modelData, packedRect, card.layoutAreaWidth, card.layoutAreaHeight, Style.spacing.sm, card.controller.windowFooterHeight)
    readonly property var layoutRect: previewed ? previewRect : packedRect

    onPackedRectSourceChanged: {
        if (packedRectSource)
            packedRect = packedRectSource;

    }
    Component.onCompleted: {
        if (packedRectSource)
            packedRect = packedRectSource;

    }
    visible: inLayout
    x: layoutRect.x
    y: layoutRect.y
    width: layoutRect.width
    height: layoutRect.height
    z: previewed ? 11 : (exitingPreview ? 10 : (lifted ? 1 : 0))
    scale: lifted ? 1.04 : 1
    radius: integratedFooter ? Style.cornerRadius : 0
    color: integratedFooter ? Commons.Color.menu.background : "transparent"
    borderSpec: integratedFooter ? outlineSpec : Border.none()
    opacity: card.controller.previewToplevel
        ? (previewed ? 1 : 0.28)
        : (liftSelection && !selected ? 0.72 : 1)

    MouseArea {
        anchors.fill: parent
        enabled: !card.controller.settingsOpen && (!card.controller.previewToplevel || card.previewed)
        hoverEnabled: true
        onEnabledChanged: {
            if (!enabled) {
                card.hovered = false;
                if (card.controller.hoveredToplevel === card.modelData)
                    card.controller.hoveredToplevel = null;

            }
        }
        onEntered: {
            card.hovered = true;
            if (card.acceptsKeyboard) {
                card.controller.hoveredToplevel = card.modelData;
                card.controller.selectedToplevel = card.modelData;
            }
        }
        onExited: {
            card.hovered = false;
            if (card.acceptsKeyboard && card.controller.hoveredToplevel === card.modelData)
                card.controller.hoveredToplevel = null;

        }
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton)
                card.controller.requestClose(card.modelData);
            else
                card.controller.activate(card.modelData);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: card.overlayFooter ? 0 : Style.spacing.sm

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Lift's glow behind the selected preview. Its blur layer exists
            // only while it shows.
            Rectangle {
                anchors.fill: previewFrame
                anchors.margins: -Style.space(4)
                radius: previewFrame.radius + Style.space(4)
                color: Commons.Color.accent
                opacity: card.lifted ? 0.85 : 0
                visible: opacity > 0
                layer.enabled: visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    autoPaddingEnabled: true
                }

                Behavior on opacity {
                    enabled: card.controller.motionSettled

                    NumberAnimation {
                        duration: card.controller.previewFadeDuration
                    }

                }

            }

            Rectangle {
                id: previewFrame

                readonly property real windowAspectRatio: card.controller.aspectRatioFor(card.modelData)

                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * windowAspectRatio)
                height: Math.min(parent.height, parent.width / windowAspectRatio)
                radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
                color: Commons.Color.background
                clip: true
                layer.enabled: true

                CardText {
                    anchors.centerIn: parent
                    text: "Live preview unavailable"
                    opacity: 0.45
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
                        captureSource: WindowModel.waylandFor(card.modelData)
                        live: card.controller.opened && card.inLayout
                        paintCursor: false
                    }

                }

                Loader {
                    anchors.fill: parent
                    z: 2
                    active: card.overlayFooter
                    sourceComponent: overlayFooterComponent
                }

                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: previewMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

            }

            Ui.BorderSurface {
                anchors.fill: previewFrame
                visible: !card.integratedFooter
                z: 5
                radius: previewFrame.radius
                color: "transparent"
                borderSpec: card.outlineSpec
            }

            Rectangle {
                anchors.top: previewFrame.top
                anchors.right: previewFrame.right
                anchors.margins: Style.spacing.sm
                z: 6
                visible: card.liftSelection && card.focusedWindow
                width: Style.space(12)
                height: width
                radius: width / 2
                color: card.currentColor
                border.color: Commons.Color.menu.background
                border.width: Style.space(2)
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
                sourceComponent: card.floatingFooter ? floatingFooterComponent : (card.integratedFooter ? integratedFooterComponent : (card.centeredFooter ? centeredFooterComponent : null))
            }

        }

    }

    // Shared footer building blocks; each footer style overrides only what differs.
    component CardText: Text {
        textFormat: Text.PlainText
        color: Commons.Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
    }

    component FooterTitle: CardText {
        text: card.windowTitle
        font.bold: card.selected
        elide: Text.ElideRight
    }

    component FooterIcon: Image {
        property int iconSize: 24
        Layout.preferredWidth: Style.space(iconSize)
        Layout.preferredHeight: Style.space(iconSize)
        source: card.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    component WorkspaceColumn: ColumnLayout {
        spacing: 0

        CardText {
            Layout.alignment: Qt.AlignRight
            text: card.workspaceName
            color: card.focusedWindow ? card.currentColor : Commons.Color.menu.text
            font.pixelSize: Style.font.heading
            font.bold: true
        }

        CardText {
            Layout.alignment: Qt.AlignRight
            text: "Workspace"
            opacity: 0.55
            font.pixelSize: Style.font.caption
        }
    }

    // Only the configured footer style is instantiated per card.
    Component {
        id: overlayFooterComponent

        Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.min(parent.height * 0.45, Style.space(84))

                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop {
                        position: 0
                        color: "transparent"
                    }

                    GradientStop {
                        position: 1
                        color: Commons.Color.menu.background
                    }
                }
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.md
                spacing: Style.spacing.md

                FooterIcon { iconSize: 28 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    FooterTitle { Layout.fillWidth: true }

                    CardText {
                        Layout.fillWidth: true
                        text: card.applicationName
                        opacity: 0.68
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                }

                WorkspaceColumn {}
            }
        }
    }

    Component {
        id: floatingFooterComponent

        RowLayout {
            spacing: Style.spacing.md

            FooterIcon { iconSize: 30 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                FooterTitle { Layout.fillWidth: true }

                CardText {
                    Layout.fillWidth: true
                    text: card.applicationName
                    opacity: 0.62
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }

            WorkspaceColumn {}
        }
    }

    Component {
        id: integratedFooterComponent

        RowLayout {
            spacing: Style.spacing.md

            FooterIcon {}

            FooterTitle { Layout.fillWidth: true }

            CardText {
                text: "WS " + card.workspaceName
                color: card.focusedWindow ? card.currentColor : Commons.Color.menu.text
                opacity: card.focusedWindow ? 1 : 0.68
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }
    }

    Component {
        id: centeredFooterComponent

        ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.spacing.md

                FooterIcon {}

                FooterTitle { Layout.maximumWidth: Math.max(1, card.width - Style.space(80)) }
            }

            CardText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(1, card.width - Style.space(32))
                text: card.applicationName + "  ·  Workspace " + card.workspaceName
                color: card.focusedWindow ? card.currentColor : Commons.Color.menu.text
                opacity: card.focusedWindow ? 1 : 0.62
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }
        }
    }

    Behavior on x {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on y {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on width {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on height {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewAnimationDuration
            easing.type: card.controller.previewAnimationEasing
        }

    }

    Behavior on opacity {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewFadeDuration
        }

    }

    Behavior on scale {
        enabled: card.controller.motionSettled

        NumberAnimation {
            duration: card.controller.previewFadeDuration
            easing.type: Easing.OutCubic
        }

    }

}
