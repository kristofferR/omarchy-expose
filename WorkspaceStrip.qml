import QtQuick
import QtQuick.Effects
import "ScreenLayout.js" as ScreenLayout
import "WindowModel.js" as WindowModel
import "WorkspaceModel.js" as WorkspaceModel
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// One thumbnail per workspace of a display, and a tile for a new one. Click a
// thumbnail to switch to it; drop a dragged card on one to move the window
// there. With more than one display, a row of display tiles above the
// thumbnails chooses whose workspaces they show.
Item {
    id: strip

    required property var controller
    // The display this strip is on, whose workspaces it shows at first.
    required property string screenName
    required property url wallpaper
    // The card capture for a window; thumbnails draw from it.
    required property var captureItemFor

    // The display chosen in the display row, shown while it stays connected.
    property string pickedScreenName: ""
    // The shown display's logical size and position, which window geometry is in.
    readonly property var display: ScreenLayout.named(strip.controller.displays, strip.pickedScreenName)
        || ScreenLayout.named(strip.controller.displays, strip.screenName)
        || { name: strip.screenName, x: 0, y: 0, width: 0, height: 0 }
    readonly property string shownScreenName: strip.display.name

    // Where a dragged card would land: a workspace id or "new" in dropTarget,
    // or in dropDisplay the name of a display, which stands for that display's
    // active workspace.
    property var dropTarget: null
    property string dropDisplay: ""
    // Holding a card over a display's tile shows that display's workspaces, so
    // the card can go on to any of them.
    onDropDisplayChanged: {
        if (strip.dropDisplay && strip.dropDisplay !== strip.shownScreenName)
            displayHold.restart();
        else
            displayHold.stop();
    }

    Timer {
        id: displayHold
        interval: 400
        onTriggered: strip.pickedScreenName = strip.dropDisplay
    }

    // Reassigned only when the workspaces change, so thumbnails and their
    // captures survive other updates.
    readonly property var workspacesSource: strip.controller.stripWorkspacesForScreen(strip.shownScreenName)
    property var workspaces: []
    onWorkspacesSourceChanged: {
        if (!strip.controller.toplevelListsEqual(strip.workspaces, strip.workspacesSource))
            strip.workspaces = strip.workspacesSource;
    }
    Component.onCompleted: strip.workspaces = strip.workspacesSource

    readonly property bool canAdd: strip.controller.newWorkspaceIdForScreen(strip.shownScreenName) > 0
    readonly property real aspect: strip.display.width > 0 && strip.display.height > 0
        ? strip.display.width / strip.display.height
        : 16 / 9
    readonly property real gap: Style.spacing.md
    readonly property real labelHeight: Style.space(22)
    // Thumbnails shrink to fit the row, up to a fixed height.
    readonly property real thumbHeight: {
        var count = strip.workspaces.length;
        var gaps = strip.gap * Math.max(0, count + (strip.canAdd ? 1 : 0) - 1);
        var units = count * strip.aspect + (strip.canAdd ? 1 : 0);
        var fit = units > 0 ? (strip.width - gaps) / units : Style.space(84);
        return Math.max(Style.space(24), Math.min(Style.space(84), fit));
    }
    readonly property real thumbWidth: strip.thumbHeight * strip.aspect
    readonly property real radius: Math.max(0, Style.cornerRadius - Style.spacing.xs)
    readonly property real displayRowHeight: displayTiles.count > 0 ? Style.space(28) + strip.gap : 0
    implicitHeight: strip.displayRowHeight + strip.thumbHeight + strip.labelHeight

    // The drop target under a point in `item` coordinates.
    function targetAt(item, x, y) {
        for (var index = 0; index < thumbs.count; index++) {
            var thumb = thumbs.itemAt(index);
            if (thumb && thumb.frame.contains(thumb.frame.mapFromItem(item, x, y))) // qmllint disable missing-property
                return thumb.workspaceId; // qmllint disable missing-property
        }
        if (addTile.visible && addTile.contains(addTile.mapFromItem(item, x, y)))
            return "new";
        return null;
    }

    // The display whose tile is under a point in `item` coordinates, or "".
    function displayAt(item, x, y) {
        for (var index = 0; index < displayTiles.count; index++) {
            var tile = displayTiles.itemAt(index);
            if (tile && tile.contains(tile.mapFromItem(item, x, y)))
                return tile.modelData.name; // qmllint disable missing-property
        }
        return "";
    }

    // Aims a dragged card at whatever is under a point in `item` coordinates.
    function dragTo(item, x, y) {
        strip.dropDisplay = strip.displayAt(item, x, y);
        strip.dropTarget = strip.dropDisplay ? null : strip.targetAt(item, x, y);
    }

    // Ends a drag. Given the dragged window, moves it to where it was dropped.
    function endDrag(top) {
        var display = strip.dropDisplay;
        var target = strip.dropTarget;
        strip.dropDisplay = "";
        strip.dropTarget = null;
        if (!top)
            return;
        if (display)
            strip.controller.moveToWorkspace(top, strip.controller.activeWorkspaceIdForScreen(display), display);
        else if (target !== null)
            strip.controller.moveToWorkspace(top, target, strip.shownScreenName);
    }

    // A one-off grow on hover or as a drop target.
    component Lift: Item {
        property bool raised: false
        scale: raised ? 1.05 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Style.duration(140)
                easing.type: Easing.OutCubic
            }
        }
    }

    // The translucent tile behind + and each display's name.
    component TileSurface: Ui.BorderSurface {
        property bool active: false
        anchors.fill: parent
        radius: strip.radius
        color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 0.6)
        borderSpec: active
            ? strip.controller.windowBorders.activeSpec
            : strip.controller.windowBorders.inactiveSpec
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.sm

        Repeater {
            id: displayTiles
            model: strip.controller.displays.length > 1 ? strip.controller.displays : []

            delegate: Lift {
                id: displayTile
                required property var modelData
                readonly property bool shown: modelData.name === strip.shownScreenName
                width: Math.min(Style.space(128), (strip.width - Style.spacing.sm * (displayTiles.count - 1)) / displayTiles.count)
                height: Style.space(28)
                raised: displayMouse.containsMouse || modelData.name === strip.dropDisplay

                TileSurface {
                    active: displayTile.shown || displayTile.raised
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.sm
                    anchors.rightMargin: Style.spacing.sm
                    text: displayTile.modelData.name
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: displayTile.shown ? Commons.Color.accent : Commons.Color.menu.text
                    opacity: displayTile.shown ? 1 : 0.7
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: displayTile.shown
                }

                MouseArea {
                    id: displayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.pickedScreenName = displayTile.modelData.name
                }
            }
        }
    }

    Row {
        y: strip.displayRowHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: strip.gap

        Repeater {
            id: thumbs
            model: strip.workspaces

            delegate: Item {
                id: thumb
                required property var modelData
                readonly property int workspaceId: Number(modelData.id)
                readonly property bool current: strip.controller.activeWorkspaceIdForScreen(strip.shownScreenName) === thumb.workspaceId
                readonly property bool targeted: strip.dropTarget === thumb.workspaceId
                readonly property alias frame: frame
                width: strip.thumbWidth
                height: strip.thumbHeight + strip.labelHeight

                readonly property var windowsSource: {
                    var revision = strip.controller.modelRevision;
                    return WorkspaceModel.windowsOn(strip.controller.allToplevels, thumb.workspaceId);
                }
                property var windows: []
                onWindowsSourceChanged: {
                    if (!strip.controller.toplevelListsEqual(thumb.windows, thumb.windowsSource))
                        thumb.windows = thumb.windowsSource;
                }
                Component.onCompleted: thumb.windows = thumb.windowsSource

                Lift {
                    id: frame
                    width: strip.thumbWidth
                    height: strip.thumbHeight
                    raised: thumbMouse.containsMouse || thumb.targeted

                    Item {
                        id: content
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: thumbMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Commons.Color.background
                        }

                        Image {
                            anchors.fill: parent
                            source: strip.wallpaper
                            sourceSize.width: Math.ceil(strip.thumbWidth * 2)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Repeater {
                            model: thumb.windows

                            delegate: Item {
                                id: thumbWindow
                                required property var modelData
                                readonly property var ipc: WindowModel.ipcFor(modelData)
                                readonly property real ratio: strip.thumbWidth / Math.max(1, strip.display.width)
                                // The window's card already captures it, so the
                                // thumbnail scales that down instead of capturing
                                // again. A window without a card in the grid,
                                // such as one outside the current scope, is
                                // captured here instead.
                                readonly property var shared: strip.captureItemFor(modelData)
                                x: ((ipc.at || [0, 0])[0] - strip.display.x) * ratio
                                y: ((ipc.at || [0, 0])[1] - strip.display.y) * ratio
                                width: (ipc.size || [0, 0])[0] * ratio
                                height: (ipc.size || [0, 0])[1] * ratio
                                z: WorkspaceModel.stackLevel(ipc)

                                Loader {
                                    anchors.fill: parent
                                    sourceComponent: thumbWindow.shared ? sharedCapture : ownCapture
                                }

                                Component {
                                    id: sharedCapture
                                    ShaderEffectSource {
                                        sourceItem: thumbWindow.shared
                                        hideSource: false
                                        live: true
                                        textureSize: Qt.size(Math.max(1, Math.ceil(thumbWindow.width * 2)), Math.max(1, Math.ceil(thumbWindow.height * 2)))
                                    }
                                }

                                Component {
                                    id: ownCapture
                                    WindowCapture {
                                        source: strip.controller.captureSourceFor(thumbWindow.modelData)
                                        live: strip.controller.livePreviews && strip.controller.opened
                                    }
                                }

                                // Tells the windows apart at thumbnail size.
                                Image {
                                    readonly property real size: Math.min(Style.space(24), Math.min(thumbWindow.width, thumbWindow.height) * 0.6)
                                    anchors.centerIn: parent
                                    width: size
                                    height: size
                                    visible: strip.controller.workspaceStripIcons && size >= Style.space(8)
                                    source: visible ? strip.controller.iconFor(thumbWindow.modelData) : ""
                                    sourceSize: Qt.size(Math.ceil(size * 2), Math.ceil(size * 2))
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: thumbMask
                        anchors.fill: parent
                        radius: strip.radius
                        color: "black"
                        visible: false
                        layer.enabled: true
                        layer.smooth: true
                    }

                    Ui.BorderSurface {
                        anchors.fill: parent
                        radius: strip.radius
                        color: "transparent"
                        borderSpec: thumb.current || thumb.targeted || thumbMouse.containsMouse
                            ? strip.controller.windowBorders.activeSpec
                            : strip.controller.windowBorders.inactiveSpec
                    }

                    MouseArea {
                        id: thumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: strip.controller.switchToWorkspace(thumb.workspaceId, strip.shownScreenName)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: strip.controller.formatWorkspaceLabel(String(thumb.modelData.name || thumb.workspaceId))
                    textFormat: Text.PlainText
                    color: thumb.current ? Commons.Color.accent : Commons.Color.menu.text
                    opacity: thumb.current ? 1 : 0.7
                    layer.enabled: true
                    layer.effect: BackdropShadow {}
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: thumb.current
                }
            }
        }

        Lift {
            id: addTile
            visible: strip.canAdd
            width: strip.thumbHeight
            height: strip.thumbHeight
            raised: addMouse.containsMouse || strip.dropTarget === "new"

            TileSurface {
                active: addTile.raised
            }

            Text {
                anchors.centerIn: parent
                text: "+"
                textFormat: Text.PlainText
                color: Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.display
            }

            MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.controller.addWorkspace(strip.shownScreenName)
            }
        }
    }
}
