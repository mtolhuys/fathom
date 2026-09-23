.pragma library

// Depth from time, as docs/SPEC.md defines it. Pure functions only: the
// controller imports this file, and the node tests load the same source, so
// what ships is what is tested. Where a plane sits is Layout.js's business;
// depth decides how much fog it wears and what its age label says.

var TIME_UNIT_SECONDS = 30;
var MAX_DEPTH = 8;
// Fog per unit of depth (the brief's `fog = depth * 0.08 alpha`).
var FOG_PER_DEPTH = 0.08;

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

// fog = depth * 0.08, from 0 (just used) to 0.64 (two hours and more).
// Planes behind the camera wear it, so older windows look further away
// without shrinking out of sight.
function fogForDepth(depth) {
    return clampDepth(depth) * FOG_PER_DEPTH;
}
