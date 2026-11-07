import QtQuick
import QtQuick.Effects
import "WindowModel.js" as WindowModel
import "WorkspaceModel.js" as WorkspaceModel
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// One thumbnail per workspace on this display, and a tile for a new one.
// Click a thumbnail to switch to it; drop a dragged card on one to move the
// window there.
Item {
    id: strip

    required property var controller
    required property string screenName
    // The display's logical size and position, which window geometry is in.
    required property real screenWidth
    required property real screenHeight
    required property real screenX
    required property real screenY
    required property url wallpaper
    // The card capture for a window; thumbnails draw from it.
    required property var captureItemFor
    // Where a dragged card would land: a workspace id, "new", or null.
    property var dropTarget: null

    // Reassigned only when the workspaces change, so thumbnails and their
    // captures survive other updates.
    readonly property var workspacesSource: strip.controller.stripWorkspacesForScreen(strip.screenName)
    property var workspaces: []
    onWorkspacesSourceChanged: {
        if (!strip.controller.toplevelListsEqual(strip.workspaces, strip.workspacesSource))
            strip.workspaces = strip.workspacesSource;
    }
    Component.onCompleted: strip.workspaces = strip.workspacesSource

    readonly property bool canAdd: strip.controller.newWorkspaceIdForScreen(strip.screenName) > 0
    readonly property real aspect: strip.screenWidth > 0 && strip.screenHeight > 0
        ? strip.screenWidth / strip.screenHeight
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
    implicitHeight: strip.thumbHeight + strip.labelHeight

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

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: strip.gap

        Repeater {
            id: thumbs
            model: strip.workspaces

            delegate: Item {
                id: thumb
                required property var modelData
                readonly property int workspaceId: Number(modelData.id)
                readonly property bool current: strip.controller.activeWorkspaceIdForScreen(strip.screenName) === thumb.workspaceId
                readonly property bool targeted: strip.dropTarget === thumb.workspaceId
                readonly property alias frame: frame
                width: strip.thumbWidth
                height: strip.implicitHeight

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
                                readonly property real ratio: strip.thumbWidth / Math.max(1, strip.screenWidth)
                                // The window's card already captures it, so the
                                // thumbnail scales that down instead of capturing
                                // again. A window without a card in the grid,
                                // such as one outside the current scope, is
                                // captured here instead.
                                readonly property var shared: strip.captureItemFor(modelData)
                                x: ((ipc.at || [0, 0])[0] - strip.screenX) * ratio
                                y: ((ipc.at || [0, 0])[1] - strip.screenY) * ratio
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
                                        source: WindowModel.waylandFor(thumbWindow.modelData)
                                        live: strip.controller.opened
                                    }
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
                        onClicked: strip.controller.switchToWorkspace(thumb.workspaceId, strip.screenName)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: strip.controller.formatWorkspaceLabel(String(thumb.modelData.name || thumb.workspaceId))
                    textFormat: Text.PlainText
                    color: thumb.current ? Commons.Color.accent : Commons.Color.menu.text
                    opacity: thumb.current ? 1 : 0.7
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

            Ui.BorderSurface {
                anchors.fill: parent
                radius: strip.radius
                color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 0.6)
                borderSpec: addTile.raised
                    ? strip.controller.windowBorders.activeSpec
                    : strip.controller.windowBorders.inactiveSpec
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
                onClicked: strip.controller.addWorkspace(strip.screenName)
            }
        }
    }
}
