import QtQuick
import QtTest
import "../GridLayout.js" as GridLayout

TestCase {
    name: "GridLayout"

    readonly property int areaWidth: 1600
    readonly property int areaHeight: 900
    readonly property int gap: 64
    readonly property int padding: 8
    readonly property int footer: 40

    function layoutFor(ratios) {
        return GridLayout.computeLayout(ratios, areaWidth, areaHeight, gap, padding, footer);
    }

    function inside(rect) {
        return rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= areaWidth + 0.001 && rect.y + rect.height <= areaHeight + 0.001;
    }

    function overlaps(a, b) {
        return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
    }

    // The preview area left after padding and footer keeps the window's shape.
    function previewRatio(rect) {
        return (rect.width - padding * 2) / (rect.height - footer - padding * 3);
    }

    function test_noWindowsOrNoSpaceLaysOutNothing() {
        compare(layoutFor([]).length, 0);
        compare(GridLayout.computeLayout([1.6], 0, areaHeight, gap, padding, footer).length, 0);
        compare(GridLayout.computeLayout([1.6], areaWidth, -5, gap, padding, footer).length, 0);
    }

    function test_oneWindowFitsAndKeepsItsShape() {
        var rects = layoutFor([1.6]);
        compare(rects.length, 1);
        verify(inside(rects[0]));
        fuzzyCompare(previewRatio(rects[0]), 1.6, 0.01);
    }

    function test_manyWindowsFitWithoutOverlapAndKeepTheirShapes() {
        var ratios = [1.6, 0.6, 2.4, 1.0, 1.33];
        var rects = layoutFor(ratios);
        compare(rects.length, ratios.length);
        for (var i = 0; i < rects.length; i++) {
            verify(inside(rects[i]), "card " + i + " inside the area");
            fuzzyCompare(previewRatio(rects[i]), ratios[i], 0.01);
            for (var j = i + 1; j < rects.length; j++)
                verify(!overlaps(rects[i], rects[j]), "cards " + i + " and " + j + " overlap");
        }
    }

    // A wide, short area allows few rows, so each row holds several cards and
    // its width is the binding limit.
    function test_crowdedRowsStayInsideAndKeepTheirGap() {
        var ratios = [1, 1, 1, 1, 1, 1];
        var rects = GridLayout.computeLayout(ratios, areaWidth, 300, gap, padding, footer);
        compare(rects.length, ratios.length);
        for (var i = 0; i < rects.length; i++) {
            verify(rects[i].x >= 0 && rects[i].x + rects[i].width <= areaWidth + 0.001, "card " + i + " within the width");
            for (var j = 0; j < rects.length; j++) {
                var a = rects[i], b = rects[j];
                var sameRow = a.y < b.y + b.height && b.y < a.y + a.height;
                if (i !== j && sameRow && a.x < b.x)
                    verify(b.x - (a.x + a.width) >= gap - 0.001, "cards " + i + " and " + j + " keep the gap");
            }
        }
    }

    function rowCount(rects) {
        var tops = {};
        rects.forEach(function (rect) { tops[Math.round(rect.y)] = true; });
        return Object.keys(tops).length;
    }

    // Each card's title band and padding make it taller than its preview, so
    // fewer rows than the previews alone suggest can hold larger cards.
    function test_fewerLargerRowsWinWhenTheyFit() {
        var rects = layoutFor([1.6, 1.6, 1.6, 1.6, 1.6, 1.6, 1.6, 1.6]);
        compare(rowCount(rects), 2);
        verify(rects[0].width > 330, "cards " + rects[0].width + " wide");
    }

    // The most rows the area allows can be the best: one card per row.
    function test_narrowTallAreaStacksOneColumn() {
        compare(rowCount(GridLayout.computeLayout([1, 1, 1, 1, 1, 1], 400, 3000, gap, padding, footer)), 6);
    }

    function test_twoWideWindowsSitSideBySide() {
        compare(rowCount(layoutFor([2, 2])), 1);
    }

    // A tall, narrow area favours one column; the cards must still fit its width.
    function test_tallAreaStillFitsTheWidth() {
        var rects = GridLayout.computeLayout([1, 1, 1, 1, 1, 1], areaWidth, 3000, gap, padding, footer);
        compare(rects.length, 6);
        for (var i = 0; i < rects.length; i++)
            verify(rects[i].x >= 0 && rects[i].x + rects[i].width <= areaWidth + 0.001, "card " + i + " within the width");
    }

    function test_quickLookCentersOrStaysOnItsCard() {
        var source = { x: 100, y: 100, width: 300, height: 200 };
        var centered = GridLayout.previewRect(1.6, true, source, areaWidth, areaHeight, padding, footer);
        fuzzyCompare(centered.x + centered.width / 2, areaWidth / 2, 0.5);
        fuzzyCompare(centered.y + centered.height / 2, areaHeight / 2, 0.5);
        var inPlace = GridLayout.previewRect(1.6, false, source, areaWidth, areaHeight, padding, footer);
        verify(inPlace.x + inPlace.width / 2 < areaWidth / 2, "in place stays toward its card");
        verify(inPlace.x >= padding && inPlace.y >= padding, "in place stays on screen");
    }

    // Two by two: 0 1 / 2 3.
    readonly property var grid: [
        { x: 0, y: 0, width: 100, height: 100 }, { x: 200, y: 0, width: 100, height: 100 },
        { x: 0, y: 200, width: 100, height: 100 }, { x: 200, y: 200, width: 100, height: 100 }
    ]

    function test_neighbourFollowsArrowDirection() {
        compare(GridLayout.neighbourIndex(grid, 0, 1, 0), 1);
        compare(GridLayout.neighbourIndex(grid, 0, 0, 1), 2);
        compare(GridLayout.neighbourIndex(grid, 3, -1, 0), 2);
        compare(GridLayout.neighbourIndex(grid, 3, 0, -1), 1);
    }

    function test_noNeighbourBeyondTheEdge() {
        compare(GridLayout.neighbourIndex(grid, 0, -1, 0), -1);
        compare(GridLayout.neighbourIndex(grid, 0, 0, -1), -1);
        compare(GridLayout.neighbourIndex([], 0, 1, 0), -1);
    }
}
