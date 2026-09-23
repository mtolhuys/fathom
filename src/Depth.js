.pragma library

// Depth rules from docs/SPEC.md. Pure functions only: Fathom.qml imports this
// file, and the node tests load the same source, so what ships is what is
// tested.

var TIME_UNIT_SECONDS = 30;
var MAX_DEPTH = 8;
var SCALE_PER_DEPTH = 0.45;
var OPACITY_PER_DEPTH = 0.09;

// Planes in front of the selection (the camera already passed them) fade out
// over half a window step and grow a little, so they read as flying past.
var PASSED_FADE_STEPS = 0.5;
var PASSED_GROWTH = 0.3;

function clampDepth(depth) {
    var value = Number(depth);
    if (isNaN(value)) return MAX_DEPTH;
    return Math.max(0, Math.min(MAX_DEPTH, value));
}

// depth = log2(1 + secondsSinceFocus / 30), clamped to [0, 8].
// A window whose last focus is unknown sits at the far end of the field.
function depthForSeconds(seconds) {
    var value = Number(seconds);
    if (isNaN(value) || !isFinite(value)) return MAX_DEPTH;
    if (value <= 0) return 0;
    return clampDepth(Math.log(1 + value / TIME_UNIT_SECONDS) / Math.LN2);
}

// scale = 1 / (1 + depth * 0.45)
function scaleForDepth(depth) {
    return 1 / (1 + clampDepth(depth) * SCALE_PER_DEPTH);
}

// opacity = 1 - depth * 0.09
function opacityForDepth(depth) {
    return 1 - clampDepth(depth) * OPACITY_PER_DEPTH;
}

// Scale of one plane as seen from the camera. relativeIndex is the plane's
// position in the field minus the camera position (both in window steps);
// relativeDepth is its depth minus the camera depth.
function planeScale(relativeDepth, relativeIndex) {
    if (relativeIndex < 0)
        return 1 + Math.min(1, -relativeIndex) * PASSED_GROWTH;
    return scaleForDepth(Math.max(0, relativeDepth));
}

function planeOpacity(relativeDepth, relativeIndex) {
    if (relativeIndex < 0)
        return Math.max(0, 1 + relativeIndex / PASSED_FADE_STEPS);
    return opacityForDepth(Math.max(0, relativeDepth));
}

// Phase 0 placement. Planes recede toward a vanishing point placed outside
// the front plane, up and to the right: a plane at scale s sits (1 - s) of the
// way from the screen center to that point. Because the point lies beyond the
// front plane's edge, every smaller plane shows a sliver past the plane in
// front of it. Planes at the same depth are told apart by a small nudge per
// window step. Planes the camera passed (scale above 1) move the other way.
function planeCenter(centerX, centerY, vanishX, vanishY, scale, relativeIndex, nudgeX, nudgeY) {
    var pull = 1 - scale;
    return {
        x: centerX + pull * (vanishX - centerX) + relativeIndex * nudgeX,
        y: centerY + pull * (vanishY - centerY) - relativeIndex * nudgeY
    };
}
