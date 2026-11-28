import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    property url source: ""
    property real blur: 0
    property real pixelRatio: 1
    // Ready once everything drawn is loaded: the wallpaper, and with blur also
    // every copy the blur is drawn from (they load separately, even though
    // they share one decoded image).
    readonly property bool ready: wallpaper.status === Image.Ready
        && (root.blur <= 0 || root.tilesReady === mirrors.count && mirrors.count > 0)
    property int tilesReady: 0
    function countTiles() {
        var ready = 0;
        for (var index = 0; index < mirrors.count; index++) {
            var tile = mirrors.itemAt(index) as Image;
            if (tile && tile.status === Image.Ready)
                ready++;
        }
        root.tilesReady = ready;
    }
    // An opaque base also hides desktop windows while loading, for images
    // with transparency, and when the wallpaper is missing or unreadable.
    color: "#101315"
    clip: true

    // With blur, the blur samples a blur radius past every edge. Mirrored
    // copies of the wallpaper fill that margin, so the edges blur into
    // wallpaper rather than the base colour, while the wallpaper itself keeps
    // the desktop's crop and scale. The clip hides the margin.
    readonly property real bleed: root.blur > 0 ? effect.blurMax : 0
    // Loaded only once laid out: an empty sourceSize would decode the
    // wallpaper at full resolution first, and opening would wait on that.
    // At a fixed size the decoded image is also cached across openings, and
    // every copy below shares it.
    readonly property url loadSource: root.width > 0 && root.height > 0 ? root.source : ""
    readonly property size decodeSize: Qt.size(Math.ceil(root.width * root.pixelRatio), Math.ceil(root.height * root.pixelRatio))
    // The blur is drawn from copies half as large each way: it hides the
    // difference, and every opening uploads them to the GPU anew, which at a
    // large display's full size held up the first frames of the opening.
    readonly property size blurDecodeSize: Qt.size(Math.ceil(root.decodeSize.width / 2), Math.ceil(root.decodeSize.height / 2))

    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.loadSource
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.blur <= 0
    }

    // Keeps the blur's smaller image decoded while there is no blur, as the
    // sharp one above stays loaded under a blur: Qt drops an unreferenced image
    // from its cache, and turning the blur on or off would wait on a decode.
    Image {
        source: root.loadSource
        sourceSize: root.blurDecodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    Item {
        id: padded
        x: -root.bleed
        y: -root.bleed
        width: root.width + 2 * root.bleed
        height: root.height + 2 * root.bleed
        visible: false

        // The wallpaper in the middle, and a copy mirrored across each edge
        // and corner.
        Repeater {
            id: mirrors
            model: root.blur > 0 ? 9 : 0
            onItemAdded: root.countTiles()
            onItemRemoved: root.countTiles()

            Image {
                required property int index
                readonly property int column: index % 3 - 1
                readonly property int row: Math.floor(index / 3) - 1
                x: root.bleed + column * root.width
                y: root.bleed + row * root.height
                width: root.width
                height: root.height
                source: root.loadSource
                sourceSize: root.blurDecodeSize
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
                onStatusChanged: root.countTiles()
                transform: Scale {
                    origin.x: root.width / 2
                    origin.y: root.height / 2
                    xScale: column === 0 ? 1 : -1
                    yScale: row === 0 ? 1 : -1
                }
            }
        }
    }

    MultiEffect {
        id: effect
        anchors.fill: padded
        source: padded
        visible: root.ready && root.blur > 0
        blurEnabled: true
        // Close to Hyprland's blur of the desktop at the same setting.
        blurMax: 64
        blur: Math.max(0, Math.min(1, root.blur / 20))
        autoPaddingEnabled: false
    }
}
