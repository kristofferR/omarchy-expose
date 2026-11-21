import QtQuick
import QtTest
import ".."

TestCase {
    id: testCase
    name: "WallpaperBackdrop"
    when: windowShown
    visible: true
    width: 100
    height: 60

    WallpaperBackdrop {
        id: backdrop
        width: 100
        height: 60
        color: "#102030"
    }

    function svg(contents, width, height) {
        return "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="' + width
            + '" height="' + height + '">' + contents + '</svg>');
    }

    function init() {
        backdrop.blur = 0;
        backdrop.source = "";
    }

    function test_missingWallpaperIsOpaque() {
        verify(!backdrop.ready);
        var image = grabImage(backdrop);
        compare(image.pixel(50, 30), Qt.color("#102030"));
        compare(image.alpha(50, 30), 255);
    }

    function test_transparentWallpaperKeepsOpaqueBase() {
        backdrop.source = svg('<rect width="50" height="60" fill="red"/>', 100, 60);
        tryCompare(backdrop, "ready", true);
        var image = grabImage(backdrop);
        compare(image.pixel(25, 30), Qt.color("red"));
        compare(image.pixel(75, 30), Qt.color("#102030"));
        compare(image.alpha(75, 30), 255);
    }

    function test_wallpaperCropsInsteadOfStretching() {
        backdrop.source = svg('<rect width="300" height="60" fill="blue"/>'
            + '<rect x="100" width="100" height="60" fill="red"/>', 300, 60);
        tryCompare(backdrop, "ready", true);
        var image = grabImage(backdrop);
        compare(image.pixel(10, 30), Qt.color("red"));
        compare(image.pixel(90, 30), Qt.color("red"));
    }

    function test_blurCanBeEnabledAndRemoved() {
        backdrop.source = svg('<rect width="100" height="60" fill="white"/>'
            + '<rect width="50" height="60" fill="black"/>', 100, 60);
        tryCompare(backdrop, "ready", true);
        var sharp = grabImage(backdrop);
        backdrop.blur = 20;
        var blurred = grabImage(backdrop);
        verify(blurred.red(45, 30) > sharp.red(45, 30), "blur softens the black/white boundary");
        compare(blurred.alpha(50, 30), 255);
        backdrop.blur = 0;
        verify(grabImage(backdrop).equals(sharp), "turning blur off restores the wallpaper");
    }

    // The offscreen test platform draws no MultiEffect blur, so these
    // checks run only where Qt renders on a GPU.
    function grabBlurred() {
        waitForRendering(backdrop);
        var image = grabImage(backdrop);
        if (Qt.colorEqual(image.pixel(60, 30), backdrop.color))
            skip("blur is not rendered on this platform");
        return image;
    }

    function test_blurKeepsTheDesktopCropAndScale() {
        // The desktop shows this wallpaper unscaled, with its edge at x = 25.
        backdrop.source = svg('<rect width="100" height="60" fill="white"/>'
            + '<rect width="25" height="60" fill="black"/>', 100, 60);
        tryCompare(backdrop, "ready", true);
        backdrop.blur = 4;
        var blurred = grabBlurred();
        verify(blurred.red(4, 30) < 60, "the black part stays at the left edge");
        verify(blurred.red(25, 30) > 70 && blurred.red(25, 30) < 185, "the edge stays at x = 25");
        verify(blurred.red(60, 30) > 220, "the white part keeps its place");
    }

    function test_blurredEdgesStayWallpaper() {
        backdrop.source = svg('<rect width="100" height="60" fill="white"/>', 100, 60);
        tryCompare(backdrop, "ready", true);
        backdrop.blur = 20;
        var blurred = grabBlurred();
        verify(blurred.red(0, 0) > 245, "a corner does not blur into the base colour");
        verify(blurred.red(50, 59) > 245, "an edge does not blur into the base colour");
    }
}
