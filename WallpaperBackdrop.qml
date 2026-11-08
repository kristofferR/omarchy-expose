import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    property url source: ""
    property real blur: 0
    property real pixelRatio: 1
    readonly property bool ready: wallpaper.status === Image.Ready
    // An opaque base also hides desktop windows while loading, for images
    // with transparency, and when the wallpaper is missing or unreadable.
    color: "#101315"
    clip: true

    // With blur, the wallpaper is drawn a blur radius past every edge, so the
    // blur samples wallpaper there rather than fading into the base colour.
    // The clip hides the overhang.
    readonly property real bleed: root.blur > 0 ? effect.blurMax : 0

    Image {
        id: wallpaper
        anchors.fill: parent
        anchors.margins: -root.bleed
        source: root.source
        sourceSize: Qt.size(Math.ceil(wallpaper.width * root.pixelRatio), Math.ceil(wallpaper.height * root.pixelRatio))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.blur <= 0
    }

    MultiEffect {
        id: effect
        anchors.fill: wallpaper
        source: wallpaper
        visible: root.ready && root.blur > 0
        blurEnabled: true
        // Close to Hyprland's blur of the desktop at the same setting.
        blurMax: 64
        blur: Math.max(0, Math.min(1, root.blur / 20))
        autoPaddingEnabled: false
    }
}
