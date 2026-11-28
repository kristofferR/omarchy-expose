.pragma library

// Window grid geometry: lays cards out in rows in list order, places Quick
// Look, and finds the card under a point or beside a card for arrow keys.
// Pure: callers pass aspect ratios.

function naturalWidth(entry) {
    return Math.sqrt(entry.weight * entry.ratio);
}

// For every row count up to maxRows, the cards split, in order, into rows
// whose widest row is as narrow as it can be: rowsByCount[r] holds r rows.
// Rows keep the list order, so the grid reads left to right and top to bottom
// in the order the windows are listed. Ties fill the upper rows first.
function orderedRows(entries, maxRows) {
    var count = entries.length;
    var prefix = [0];
    for (var index = 0; index < count; index++)
        prefix.push(prefix[index] + naturalWidth(entries[index]));

    // widest[r][i]: the narrowest widest row splitting the first i cards into
    // r rows, the last of which starts at split[r][i].
    var widest = [[0]];
    var split = [[]];
    for (var row = 1; row <= maxRows; row++) {
        widest.push([]);
        split.push([]);
        for (var last = row; last <= count; last++) {
            widest[row][last] = Number.MAX_VALUE;
            for (var start = row - 1; start < last; start++) {
                var candidate = Math.max(widest[row - 1][start], prefix[last] - prefix[start]);
                // Widths summed in a different order differ in the last bits.
                if (candidate <= widest[row][last] + 1e-9) {
                    widest[row][last] = candidate;
                    split[row][last] = start;
                }
            }
        }
    }

    var rowsByCount = [];
    for (var rowCount = 1; rowCount <= maxRows; rowCount++) {
        var rows = [];
        var stop = count;
        for (var back = rowCount; back >= 1; back--) {
            var begin = split[back][stop];
            rows.unshift({ entries: entries.slice(begin, stop) });
            stop = begin;
        }
        rowsByCount[rowCount] = rows;
    }
    return rowsByCount;
}

function composeRows(rows, scale, width, height, gap, padding, footerHeight) {
    var measuredRows = [];
    var totalHeight = 0;
    var footerSpacing = footerHeight > 0 ? padding : 0;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        var entries = rows[rowIndex].entries;
        var cards = [];
        var totalWidth = Math.max(0, entries.length - 1) * gap;
        var rowHeight = 0;
        for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
            var entry = entries[entryIndex];
            var previewWidth = scale * naturalWidth(entry);
            var previewHeight = scale * Math.sqrt(entry.weight / entry.ratio);
            var card = {
                index: entry.index,
                width: previewWidth + padding * 2,
                height: previewHeight + footerHeight + padding * 2 + footerSpacing
            };
            cards.push(card);
            totalWidth += card.width;
            rowHeight = Math.max(rowHeight, card.height);
        }
        if (totalWidth > width || rowHeight > height)
            return null;
        measuredRows.push({ cards: cards, width: totalWidth, height: rowHeight });
        totalHeight += rowHeight;
    }
    totalHeight += Math.max(0, measuredRows.length - 1) * gap;
    if (totalHeight > height)
        return null;

    var verticalGap = measuredRows.length > 1 ? gap : 0;
    var y = (height - totalHeight) / 2;
    var result = [];
    for (var outputRow = 0; outputRow < measuredRows.length; outputRow++) {
        var row = measuredRows[outputRow];
        var horizontalGap = row.cards.length > 1 ? gap : 0;
        var x = (width - row.width) / 2;
        for (var cardIndex = 0; cardIndex < row.cards.length; cardIndex++) {
            var placed = row.cards[cardIndex];
            var align = ((placed.index + outputRow) % 3) / 2;
            result[placed.index] = {
                x: x,
                y: y + (row.height - placed.height) * align,
                width: placed.width,
                height: placed.height
            };
            x += placed.width + horizontalGap;
        }
        y += row.height + verticalGap;
    }
    return result;
}

// Card rectangles for windows of the given aspect ratios, indexed like ratios
// and placed in that order. Every row count that fits is tried and the largest
// cards win: a card's title band and padding make it taller than its preview,
// so no estimate from the previews' shapes alone can rule a row count out.
function computeLayout(ratios, width, height, gap, padding, footerHeight) {
    var count = ratios.length;
    if (!count || width <= 0 || height <= 0)
        return [];

    var edgeInset = gap / 2;
    var availableWidth = Math.max(1, width - edgeInset * 2);
    var availableHeight = Math.max(1, height - edgeInset * 2);
    var entries = [];
    for (var index = 0; index < count; index++) {
        var ratio = ratios[index];
        var adaptiveWeight = Math.max(0.72, Math.min(1.28, Math.sqrt(ratio / 1.6)));
        entries.push({ index: index, ratio: ratio, weight: adaptiveWeight });
    }

    var high = Math.min(availableWidth, availableHeight);
    var footerSpacing = footerHeight > 0 ? padding : 0;
    for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        var entry = entries[entryIndex];
        high = Math.min(high,
            (availableWidth - padding * 2) / naturalWidth(entry),
            (availableHeight - footerHeight - padding * 2 - footerSpacing) / Math.sqrt(entry.weight / entry.ratio));
    }
    high = Math.max(1, high);

    var best = null;
    var bestScale = -1;
    var minimumCardHeight = footerHeight + padding * 2 + footerSpacing;
    var maxRows = Math.max(1, Math.min(count, Math.floor((availableHeight + gap) / (minimumCardHeight + gap))));
    var rowsByCount = orderedRows(entries, maxRows);
    for (var rowCount = 1; rowCount <= maxRows; rowCount++) {
        var rows = rowsByCount[rowCount];
        var low = 0;
        var rowHigh = high;
        var rowBest = null;
        for (var iteration = 0; iteration < 12; iteration++) {
            var scale = (low + rowHigh) / 2;
            var composed = composeRows(rows, scale, availableWidth, availableHeight, gap, padding, footerHeight);
            if (composed) {
                rowBest = composed;
                low = scale;
            } else {
                rowHigh = scale;
            }
        }
        if (rowBest && low > bestScale) {
            best = rowBest;
            bestScale = low;
        }
    }
    if (!best)
        best = composeRows(rowsByCount[1], 1, availableWidth, availableHeight, gap, padding, footerHeight) || [];
    for (var resultIndex = 0; resultIndex < best.length; resultIndex++) {
        if (!best[resultIndex])
            continue;
        best[resultIndex].x += edgeInset;
        best[resultIndex].y += edgeInset;
    }
    return best;
}

// The enlarged Quick Look card within bounds, the display in the grid's
// coordinates: centred on the display, or on sourceRect in place. It floats
// over the search bar and strip too, so a window can grow when the grid
// already fills the display's height, as on an ultrawide.
function previewRect(ratio, centered, sourceRect, bounds, padding, footerHeight) {
    var maxWidth = bounds.width * 0.9;
    var maxHeight = bounds.height * 0.9;
    var footerSpacing = footerHeight > 0 ? padding : 0;
    var previewWidth = Math.max(1, Math.min(maxWidth - padding * 2, (maxHeight - footerHeight - padding * 2 - footerSpacing) * ratio));
    var previewHeight = Math.max(1, previewWidth / ratio);
    var cardWidth = previewWidth + padding * 2;
    var cardHeight = previewHeight + footerHeight + padding * 2 + footerSpacing;
    var centerX = bounds.x + bounds.width / 2;
    var centerY = bounds.y + bounds.height / 2;
    if (!centered && sourceRect) {
        centerX = sourceRect.x + sourceRect.width / 2;
        centerY = sourceRect.y + sourceRect.height / 2;
    }
    return {
        x: Math.max(bounds.x + padding, Math.min(bounds.x + bounds.width - cardWidth - padding, centerX - cardWidth / 2)),
        y: Math.max(bounds.y + padding, Math.min(bounds.y + bounds.height - cardHeight - padding, centerY - cardHeight / 2)),
        width: cardWidth,
        height: cardHeight
    };
}

// Index of the card containing the point, or -1.
function indexAt(layout, x, y) {
    for (var index = 0; index < (layout || []).length; index++) {
        var rect = layout[index];
        if (rect && x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height)
            return index;
    }
    return -1;
}

// Whether b's centre lies within a's vertical span.
function centredBeside(a, b) {
    var centreY = b.y + b.height / 2;
    return centreY >= a.y && centreY <= a.y + a.height;
}

// Index of the nearest card from currentIndex in direction (dx, dy), or -1.
// Rows align cards of different heights to the top, middle, or bottom, so Up
// and Down skip a card that shares the current card's row (either centre
// inside the other's vertical span) even when its centre is higher or lower.
function neighbourIndex(layout, currentIndex, dx, dy) {
    if (!layout || !layout[currentIndex])
        return -1;
    var current = layout[currentIndex];
    var currentX = current.x + current.width / 2;
    var currentY = current.y + current.height / 2;
    var bestIndex = -1;
    var bestScore = Number.MAX_VALUE;
    for (var index = 0; index < layout.length; index++) {
        if (index === currentIndex || !layout[index])
            continue;
        var candidate = layout[index];
        var deltaX = candidate.x + candidate.width / 2 - currentX;
        var deltaY = candidate.y + candidate.height / 2 - currentY;
        var primary = dx !== 0 ? deltaX * dx : deltaY * dy;
        if (primary <= 0 || (dy !== 0 && (centredBeside(current, candidate) || centredBeside(candidate, current))))
            continue;
        var cross = dx !== 0 ? Math.abs(deltaY) : Math.abs(deltaX);
        var score = primary + cross * cross / Math.max(1, primary) * 2;
        if (score < bestScore) {
            bestScore = score;
            bestIndex = index;
        }
    }
    return bestIndex;
}
