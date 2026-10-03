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

    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(Math.ceil(root.width * root.pixelRatio), Math.ceil(root.height * root.pixelRatio))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.blur <= 0
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: root.ready && root.blur > 0
        blurEnabled: true
        blurMax: 20
        blur: Math.max(0, Math.min(1, root.blur / 20))
        autoPaddingEnabled: false
    }
}
