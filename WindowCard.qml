import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "WindowModel.js" as WindowModel
import "GlideMotion.js" as GlideMotion
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
    // The display's workspace strip, which a card can be dragged onto; null
    // when the strip is off.
    property var workspaceStrip: null
    // The display this card is drawn on, which Glide finds the window's place on.
    property string screenName: ""
    // The window's capture, which workspace thumbnails draw from too.
    readonly property alias captureItem: captureLayer
    // Position in the filtered list; -1 hides the card.
    readonly property int slot: card.screenToplevels.indexOf(modelData)
    readonly property bool inLayout: slot >= 0
    // The close button is its own hover target, so the card counts as
    // hovered while the pointer is on it too.
    property bool hovered: cardMouse.enabled && (cardMouse.containsMouse || closeHover.hovered)
    onHoveredChanged: {
        if (card.hovered) {
            if (card.acceptsKeyboard) {
                card.controller.hoveredToplevel = card.modelData;
                card.controller.selectedToplevel = card.modelData;
            }
        } else if (card.controller.hoveredToplevel === card.modelData) {
            card.controller.hoveredToplevel = null;
        }
    }
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
    readonly property bool minimized: WindowModel.isMinimized(modelData)
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
    // Glide flies every preview to its grid slot; Quick Look opened in
    // flight takes over once the previews have landed.
    readonly property var layoutRect: previewed && !glideActive ? previewRect : packedRect

    onPackedRectSourceChanged: {
        if (packedRectSource)
            packedRect = packedRectSource;

    }
    Component.onCompleted: {
        if (packedRectSource)
            packedRect = packedRectSource;
        card.countGlideCapture(card.glideCaptureWaiting);
        card.latchGlideStart();

    }
    // Dragging toward the workspace strip. The card shrinks around the point
    // it was picked up at and follows the pointer through a transform, so its
    // layout is untouched; a cancelled drop slides it back.
    readonly property bool canDrag: card.workspaceStrip !== null && card.controller.dragToWorkspaces
        && card.controller.motionSettled && !card.previewOnThisScreen && !WindowModel.isPinned(modelData)
    property bool dragging: false
    property real dragX: 0
    property real dragY: 0
    property real grabX: 0
    property real grabY: 0
    // About twice a workspace thumbnail, so the strip stays visible around it.
    property real dragScale: card.dragging ? Math.min(0.5, Style.space(240) / Math.max(1, card.width)) : 1
    // Escape lets go of the drag.
    readonly property bool dragHeld: card.controller.draggedToplevel === modelData
    onDragHeldChanged: {
        if (!card.dragHeld && card.dragging)
            card.endDrag(false);
    }

    function endDrag(drop) {
        card.dragging = false;
        // Escape ends a drag while the button is still down; moving on must
        // not start another.
        cardMouse.mayDrag = false;
        if (card.dragHeld)
            card.controller.draggedToplevel = null;
        card.dragX = 0;
        card.dragY = 0;
        if (card.workspaceStrip)
            card.workspaceStrip.endDrag(drop ? card.modelData : null);
    }

    // Glide: while the overview opens or closes, the preview is drawn over the
    // window's real place on screen, moving to its place in the grid. Only a
    // transform changes, so layout, text and textures stay as they are.
    readonly property bool glideActive: card.controller.glideMotion && !card.controller.motionSettled
    readonly property real glideProgress: card.controller.motionProgress
    // Where the window is on screen, taken when a transition starts (and
    // while Glide waits to start), so a capture or Hyprland update arriving
    // in flight cannot make the preview jump. A window whose capture has no
    // frame yet grows in place instead of flying in as a blank card.
    property var glideStart: null
    function glideLandingRect() {
        return capture.hasContent ? card.controller.glideStartRectFor(card.modelData, card.screenName) : null;
    }
    function latchGlideStart() {
        card.glideStart = card.glideActive ? card.glideLandingRect() : null;
    }
    onGlideActiveChanged: card.latchGlideStart()
    Connections {
        target: card.controller
        function onMotionEpochChanged() { card.latchGlideStart(); }
        function onGlideGateActiveChanged() { card.latchGlideStart(); }
    }
    Connections {
        target: capture
        function onHasContentChanged() {
            if (card.controller.glideGateActive || card.controller.motionProgress <= 0)
                card.latchGlideStart();
        }
    }
    // The preview frame within the card.
    readonly property real frameX: Style.spacing.sm + previewFrame.x
    readonly property real frameY: Style.spacing.sm + previewFrame.y
    readonly property var glideFinal: {
        if (!card.glideActive || !card.parent)
            return null;
        // Read every frame, because the layout can still settle while moving.
        // The card layer has no transform of its own in this style, so the
        // mapping is not changed by the card's motion.
        var origin = card.glideProgress >= 0 ? card.parent.mapToItem(null, 0, 0) : Qt.point(0, 0);
        return {
            x: origin.x + card.x + card.frameX,
            y: origin.y + card.y + card.frameY,
            width: Math.max(1, previewFrame.width),
            height: Math.max(1, previewFrame.height)
        };
    }
    readonly property var glideRect: card.glideFinal
        ? GlideMotion.rectAt(card.glideStart, card.glideFinal, card.glideProgress)
        : null
    readonly property real glideChrome: card.glideActive ? GlideMotion.chromeOpacity(card.glideProgress) : 1
    // How much larger than the grid the preview is drawn at most, so its
    // texture is rendered big enough not to look soft on the way.
    readonly property real glideTextureScale: card.glideActive && card.glideStart && card.glideFinal
        ? Math.min(8, Math.max(1, card.glideStart.width / card.glideFinal.width, card.glideStart.height / card.glideFinal.height))
        : 1
    // Counted by the overview, which waits for these before Glide starts.
    readonly property bool glideCaptureWaiting: card.controller.glideGateActive && card.inLayout
        && capture.source !== null && !capture.hasContent
    property bool glideCaptureCounted: false
    onGlideCaptureWaitingChanged: card.countGlideCapture(card.glideCaptureWaiting)
    Component.onDestruction: card.countGlideCapture(false)
    function countGlideCapture(waiting) {
        if (waiting === card.glideCaptureCounted)
            return;
        card.glideCaptureCounted = waiting;
        card.controller.glideCaptureWaiting(waiting);
    }
    readonly property real glideStackZ: GlideMotion.stackZ(WindowModel.ipcFor(card.modelData),
        card.modelData === card.controller.glideLandingTop)
    // On the desktop end the previews are only stand-ins for their windows:
    // hidden before the overview opens and once a closing has landed (the
    // overlay can stay a moment longer, while the windows may change).
    readonly property bool glideHidden: card.controller.glideMotion && !card.controller.opened
        && card.controller.motionProgress <= 0.001

    transform: [
        Scale {
            origin.x: card.frameX
            origin.y: card.frameY
            xScale: card.glideRect ? card.glideRect.width / card.glideFinal.width : 1
            yScale: card.glideRect ? card.glideRect.height / card.glideFinal.height : 1
        },
        Translate {
            x: card.glideRect ? card.glideRect.x - card.glideFinal.x : 0
            y: card.glideRect ? card.glideRect.y - card.glideFinal.y : 0
        },
        Scale {
            origin.x: card.grabX
            origin.y: card.grabY
            xScale: card.dragScale
            yScale: card.dragScale
        },
        Translate {
            x: card.dragX
            y: card.dragY
        }
    ]

    visible: inLayout
    x: layoutRect.x
    y: layoutRect.y
    width: layoutRect.width
    height: layoutRect.height
    // Previews in flight pass over the ones that only grow or fade in place.
    z: glideActive ? glideStackZ + (glideStart ? 2 : 0) + (previewed ? 20 : 0) : (dragging || dragX !== 0 || dragY !== 0 ? 20 : (previewed ? 11 : (exitingPreview ? 10 : (lifted ? 1 : 0))))
    scale: lifted ? 1 + 0.04 * glideChrome : 1
    radius: integratedFooter ? Style.cornerRadius : 0
    readonly property color integratedColor: Commons.Color.menu.background
    color: integratedFooter
        ? Qt.rgba(integratedColor.r, integratedColor.g, integratedColor.b, integratedColor.a * glideChrome)
        : "transparent"
    borderSpec: integratedFooter && glideChrome > 0.5 ? outlineSpec : Border.none()
    // Quick Look dims and locks only the grid it opened on.
    readonly property bool previewOnThisScreen: card.controller.previewToplevel !== null
        && card.screenToplevels.indexOf(card.controller.previewToplevel) !== -1
    opacity: (card.previewOnThisScreen
        ? (previewed ? 1 : 0.28)
        // Glide keeps previews opaque over their windows, dimming the
        // unselected ones only as they land.
        : (liftSelection && !selected ? 1 - 0.28 * glideChrome : 1))
        * (card.glideActive && !card.glideStart ? GlideMotion.growOpacity(card.glideProgress) : 1)
        * (card.glideHidden ? 0 : 1)

    MouseArea {
        id: cardMouse
        // Scene position of the press, and whether moving it may start a drag.
        property point pressPoint: Qt.point(0, 0)
        property bool mayDrag: false
        property bool suppressClick: false
        anchors.fill: parent
        enabled: !card.controller.settingsOpen && (!card.previewOnThisScreen || card.previewed)
        hoverEnabled: true
        preventStealing: true
        onPressed: function(mouse) {
            cardMouse.suppressClick = false;
            cardMouse.mayDrag = mouse.button === Qt.LeftButton && card.canDrag;
            cardMouse.pressPoint = cardMouse.mapToItem(null, mouse.x, mouse.y);
            card.grabX = mouse.x;
            card.grabY = mouse.y;
        }
        onPositionChanged: function(mouse) {
            if (!cardMouse.mayDrag)
                return;
            var point = cardMouse.mapToItem(null, mouse.x, mouse.y);
            var dx = point.x - cardMouse.pressPoint.x;
            var dy = point.y - cardMouse.pressPoint.y;
            if (!card.dragging) {
                if (Math.sqrt(dx * dx + dy * dy) < Style.space(10))
                    return;
                card.dragging = true;
                cardMouse.suppressClick = true;
                card.controller.draggedToplevel = card.modelData;
            }
            card.dragX = dx;
            card.dragY = dy;
            card.workspaceStrip.dragTo(null, point.x, point.y);
        }
        onReleased: {
            cardMouse.mayDrag = false;
            if (card.dragging)
                card.endDrag(true);
        }
        onCanceled: {
            cardMouse.mayDrag = false;
            if (card.dragging)
                card.endDrag(false);
        }
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (cardMouse.suppressClick)
                return;
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
                opacity: card.lifted ? 0.85 * card.glideChrome : 0
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
                // In flight a translucent window stays translucent, as on the
                // desktop; the backing appears as it lands.
                readonly property color backing: Commons.Color.background
                color: Qt.rgba(backing.r, backing.g, backing.b, backing.a * card.glideChrome)
                clip: true
                layer.enabled: true
                layer.textureSize: card.glideTextureScale > 1
                    ? Qt.size(Math.ceil(width * card.glideTextureScale * Screen.devicePixelRatio),
                        Math.ceil(height * card.glideTextureScale * Screen.devicePixelRatio))
                    : Qt.size(0, 0)

                CardText {
                    anchors.centerIn: parent
                    text: "Preview unavailable"
                    opacity: 0.45
                    // Translucent windows would show it through their capture.
                    visible: !capture.hasContent
                }

                Item {
                    id: captureLayer
                    anchors.centerIn: parent
                    // Four displays can exhaust the display GPU when every
                    // screencopy also keeps a double-resolution layer.
                    readonly property bool doubleResolution: card.controller.multiMonitorMode !== "all-monitors"
                    width: parent.width * (doubleResolution ? 2 : 1)
                    height: parent.height * (doubleResolution ? 2 : 1)
                    scale: doubleResolution ? 0.5 : 1
                    layer.enabled: doubleResolution
                    layer.smooth: true
                    layer.textureSize: card.glideTextureScale > 2
                        ? Qt.size(Math.ceil(parent.width * card.glideTextureScale * Screen.devicePixelRatio),
                            Math.ceil(parent.height * card.glideTextureScale * Screen.devicePixelRatio))
                        : Qt.size(0, 0)

                    WindowCapture {
                        id: capture
                        anchors.fill: parent
                        source: card.controller.captureSourceFor(card.modelData)
                        live: card.controller.livePreviews && card.controller.opened && card.inLayout
                    }

                }

                Loader {
                    anchors.fill: parent
                    z: 2
                    opacity: card.glideChrome
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
                opacity: card.glideChrome
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
                // The close button takes this corner while it shows.
                visible: card.liftSelection && card.focusedWindow && !(closeButton.visible && closeButton.onRight)
                opacity: card.glideChrome
                width: Style.space(12)
                height: width
                radius: width / 2
                color: card.currentColor
                border.color: Commons.Color.menu.background
                border.width: Style.space(2)
            }

            // Closes the window under the pointer. Its TapHandler takes the
            // press, so a click here never reaches the card.
            Ui.BorderSurface {
                id: closeButton
                readonly property bool lit: closeHover.hovered
                readonly property bool onRight: card.controller.closeButtonSide !== "left"
                anchors.top: previewFrame.top
                anchors.left: onRight ? undefined : previewFrame.left
                anchors.right: onRight ? previewFrame.right : undefined
                anchors.margins: Style.spacing.sm
                z: 6
                visible: card.controller.closeButton && card.hovered && card.controller.motionSettled
                    && !card.previewOnThisScreen && !card.dragging
                width: Style.space(28)
                height: width
                radius: Math.min(width / 2, previewFrame.radius)
                color: closeButton.lit ? Commons.Color.accent : Commons.Color.menu.background
                borderSpec: closeButton.lit
                    ? card.controller.windowBorders.activeSpec
                    : card.controller.windowBorders.inactiveSpec

                Repeater {
                    model: [45, -45]

                    Rectangle {
                        required property int modelData
                        anchors.centerIn: parent
                        width: closeButton.width * 0.42
                        height: Math.max(1, Style.space(2))
                        radius: height / 2
                        rotation: modelData
                        color: closeButton.lit ? Commons.Color.background : Commons.Color.menu.text
                    }
                }

                HoverHandler {
                    id: closeHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: card.controller.requestClose(card.modelData)
                }
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
            opacity: card.glideChrome

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
        readonly property int pixels: Math.ceil(Style.space(iconSize) * Screen.devicePixelRatio)
        Layout.preferredWidth: Style.space(iconSize)
        Layout.preferredHeight: Style.space(iconSize)
        source: card.iconSource
        // Omarchy's drawn icons are 512 px SVGs; decode them at the size shown.
        sourceSize.width: pixels
        sourceSize.height: pixels
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
            visible: !card.minimized
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
            layer.enabled: true
            layer.effect: BackdropShadow {}

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
                text: card.minimized ? card.workspaceName : "WS " + card.workspaceName
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
            layer.enabled: true
            layer.effect: BackdropShadow {}

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.spacing.md

                FooterIcon {}

                FooterTitle { Layout.maximumWidth: Math.max(1, card.width - Style.space(80)) }
            }

            CardText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(1, card.width - Style.space(32))
                text: card.applicationName + (card.minimized ? "  ·  " : "  ·  Workspace ") + card.workspaceName
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

    Behavior on dragScale {
        NumberAnimation {
            duration: Style.duration(160)
            easing.type: Easing.OutCubic
        }
    }

    Behavior on dragX {
        enabled: !card.dragging
        NumberAnimation {
            duration: Style.duration(220)
            easing.type: Easing.OutCubic
        }
    }

    Behavior on dragY {
        enabled: !card.dragging
        NumberAnimation {
            duration: Style.duration(220)
            easing.type: Easing.OutCubic
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
