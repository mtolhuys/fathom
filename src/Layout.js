.pragma library

// Geometry for the two halves of the field. Pure functions: FieldView binds
// to them, and the node tests load the same file.
//
// The Deep. Every window is a card of the same shape (the monitor's), so the
// stack steps evenly whatever the windows' own shapes are; the window is
// fitted inside its card. The selection's card sits in the front box. Each
// card behind it is scaled by SIZE_Q per step and its top-right corner moves
// up and to the right by a step that itself shrinks by POS_Q, so every card
// shows its header strip above the card in front of it and a band of its
// content to the right. Cards the camera has passed grow and slide out to the
// lower left, fading within PASSED_FADE steps.

var SIZE_Q = 0.82;          // card scale per step behind the camera
var POS_Q = 0.86;           // how much each step's offset shrinks
var RISE = 0.1;             // first step upward, as a share of the card height
var PASSED_FADE = 0.6;      // steps over which a passed card fades out
var PASSED_GROWTH = 0.2;    // extra scale of a card one step past
var VISIBLE_STEPS = 5;      // cards further back fade out; the map shows them

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// The sum of the step offsets up to r steps back (continuous in r).
function stepSum(r) {
    return r <= 0 ? 0 : (1 - Math.pow(POS_Q, r)) / (1 - POS_Q);
}

// Fits a window of `aspect` (width / height) into a box, centered.
function fit(boxWidth, boxHeight, aspect) {
    var a = aspect > 0 && isFinite(aspect) ? aspect : 1.6;
    var width = boxWidth;
    var height = width / a;
    if (height > boxHeight) {
        height = boxHeight;
        width = height * a;
    }
    return {
        x: (boxWidth - width) / 2,
        y: (boxHeight - height) / 2,
        width: Math.max(1, width),
        height: Math.max(1, height)
    };
}

// The front box for a screen of width x height, between `top` and
// `height - bottom`, for cards of `aspect`. The whole stack (front card plus
// the cards behind it) is centered in that area.
function deepStage(width, height, top, bottom, aspect) {
    var a = clamp(Number(aspect) || 1.6, 1.2, 2.4);
    var available = Math.max(1, height - top - bottom);
    var reach = stepSum(VISIBLE_STEPS);
    var frontHeight = available / (1 + RISE * reach);
    var frontWidth = frontHeight * a;
    if (frontWidth > width * 0.5) {
        frontWidth = width * 0.5;
        frontHeight = frontWidth / a;
    }
    var margin = width * 0.03;
    var spread = Math.max(0, Math.min(frontWidth * 0.85, width - margin * 2 - frontWidth));
    var stackHeight = frontHeight * (1 + RISE * reach);
    var stackTop = top + (available - stackHeight) / 2;
    return {
        frontX: (width - frontWidth - spread) / 2 + frontWidth / 2,
        frontY: stackTop + RISE * frontHeight * reach + frontHeight / 2,
        frontWidth: frontWidth,
        frontHeight: frontHeight,
        stepX: reach > 0 ? spread / reach : 0,
        stepY: RISE * frontHeight
    };
}

// stage: from deepStage. r: the card's slot minus the camera slot (real,
// negative once passed). Returns the card's center, size, scale, opacity, z.
function deepPlane(stage, r) {
    if (r < 0) {
        var passed = Math.min(1.5, -r);
        var grow = 1 + PASSED_GROWTH * Math.min(1, passed);
        return {
            x: stage.frontX - passed * stage.frontWidth * 0.5,
            y: stage.frontY + passed * stage.frontHeight * 0.12,
            width: stage.frontWidth * grow,
            height: stage.frontHeight * grow,
            scale: grow,
            opacity: clamp(1 - passed / PASSED_FADE, 0, 1),
            z: 1000 + passed
        };
    }
    var scale = Math.pow(SIZE_Q, r);
    var sum = stepSum(r);
    var width = stage.frontWidth * scale;
    var height = stage.frontHeight * scale;
    var right = stage.frontX + stage.frontWidth / 2 + stage.stepX * sum;
    var top = stage.frontY - stage.frontHeight / 2 - stage.stepY * sum;
    return {
        x: right - width / 2,
        y: top + height / 2,
        width: width,
        height: height,
        scale: scale,
        opacity: clamp(VISIBLE_STEPS + 1 - r, 0, 1),
        z: 1000 - r
    };
}

// ------------------------------------------------------------ the map

// The rectangle a workspace's minimap has to show: its monitor's viewport,
// grown to include every window outside it. A scrolling layout parks windows
// to the left and right of the screen, sometimes several screens away; the
// whole strip is shown, compressed, rather than cropped.
function minimapBounds(viewport, windows) {
    var left = viewport.x;
    var top = viewport.y;
    var right = viewport.x + viewport.width;
    var bottom = viewport.y + viewport.height;
    var list = windows || [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (!w || !(w.width > 0) || !(w.height > 0) || !isFinite(w.x) || !isFinite(w.y)) continue;
        left = Math.min(left, w.x);
        top = Math.min(top, w.y);
        right = Math.max(right, w.x + w.width);
        bottom = Math.max(bottom, w.y + w.height);
    }
    return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) };
}

// Maps a rectangle in compositor coordinates into a box of boxWidth x
// boxHeight showing `bounds`, centered.
function mapRect(rect, bounds, boxWidth, boxHeight) {
    var scale = Math.min(boxWidth / bounds.width, boxHeight / bounds.height);
    var offsetX = (boxWidth - bounds.width * scale) / 2;
    var offsetY = (boxHeight - bounds.height * scale) / 2;
    return {
        x: offsetX + (rect.x - bounds.x) * scale,
        y: offsetY + (rect.y - bounds.y) * scale,
        width: rect.width * scale,
        height: rect.height * scale
    };
}

// Windows without usable geometry are laid out in a grid inside the box.
function gridRect(position, count, boxWidth, boxHeight, gap) {
    var n = Math.max(1, count);
    var columns = Math.ceil(Math.sqrt(n * boxWidth / Math.max(1, boxHeight)));
    columns = clamp(columns, 1, n);
    var rows = Math.ceil(n / columns);
    var g = gap || 2;
    var width = (boxWidth - g * (columns + 1)) / columns;
    var height = (boxHeight - g * (rows + 1)) / rows;
    var column = position % columns;
    var row = Math.floor(position / columns);
    return { x: g + column * (width + g), y: g + row * (height + g), width: Math.max(1, width), height: Math.max(1, height) };
}

// Rectangles for one workspace's windows inside a minimap box. `windows` is a
// list of geometries (null when unknown). Windows sharing a rectangle (the
// tabs of a Hyprland group) split it side by side, so each one can be seen
// and clicked. Unknown geometry puts the whole workspace on a grid.
function minimapItems(viewport, windows, boxWidth, boxHeight) {
    var list = windows || [];
    var known = [];
    var complete = list.length > 0;
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        var ok = w && w.width > 0 && w.height > 0 && isFinite(w.x) && isFinite(w.y);
        if (!ok) complete = false;
        known.push(ok ? w : null);
    }
    var rects = [];
    if (!complete || !viewport || !(viewport.width > 0)) {
        for (var g = 0; g < list.length; g++) rects.push(gridRect(g, list.length, boxWidth, boxHeight, 3));
        return { rects: rects, viewport: null, bounds: null };
    }
    var bounds = minimapBounds(viewport, known);
    for (var j = 0; j < known.length; j++) rects.push(mapRect(known[j], bounds, boxWidth, boxHeight));

    // Split shared rectangles into side-by-side tabs, in list order.
    var done = [];
    for (var a = 0; a < rects.length; a++) {
        if (done[a]) continue;
        var same = [a];
        for (var b = a + 1; b < rects.length; b++) {
            if (!done[b] && Math.abs(known[a].x - known[b].x) < 2 && Math.abs(known[a].y - known[b].y) < 2
                    && Math.abs(known[a].width - known[b].width) < 2 && Math.abs(known[a].height - known[b].height) < 2)
                same.push(b);
        }
        if (same.length > 1) {
            var base = rects[a];
            var part = base.width / same.length;
            for (var k = 0; k < same.length; k++) {
                rects[same[k]] = { x: base.x + k * part, y: base.y, width: part, height: base.height };
                done[same[k]] = true;
            }
        }
        done[a] = true;
    }
    return { rects: rects, viewport: mapRect(viewport, bounds, boxWidth, boxHeight), bounds: bounds };
}

// Card widths for the map. Each card wants its minimap's aspect at
// `height`; when the row does not fit `available`, every card shrinks by the
// same factor, down to `minWidth`. Returns { widths, height, scale }.
function mapCards(aspects, available, height, gap, chrome, minWidth) {
    var list = aspects || [];
    var widths = [];
    var total = 0;
    for (var i = 0; i < list.length; i++) {
        var aspect = clamp(Number(list[i]) || 1.6, 0.8, 3.2);
        var width = height * aspect + chrome;
        widths.push(width);
        total += width;
    }
    total += gap * Math.max(0, list.length - 1);
    var scale = total > available && total > 0 ? (available - gap * Math.max(0, list.length - 1)) / (total - gap * Math.max(0, list.length - 1)) : 1;
    for (var j = 0; j < widths.length; j++) widths[j] = Math.max(minWidth || 0, widths[j] * scale);
    return { widths: widths, height: height * Math.min(1, Math.max(scale, 0.55)), scale: scale };
}
