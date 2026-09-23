.pragma library

// Frame timing summary for the frame probe. Intervals are milliseconds
// between consecutive animation ticks while the field is open.

function round2(value) {
    return Math.round(value * 100) / 100;
}

function percentile(sorted, p) {
    if (!sorted.length) return 0;
    var rank = Math.ceil(p / 100 * sorted.length) - 1;
    return sorted[Math.max(0, Math.min(sorted.length - 1, rank))];
}

// A frame is "late" when it took more than 1.5 times the median interval,
// which works for 60 Hz and high refresh displays alike. "over33ms" counts
// frames that missed at least one 60 Hz vsync outright.
function summarize(intervalsMs, swappedFrames, durationMs) {
    var source = intervalsMs && intervalsMs.length !== undefined ? intervalsMs : [];
    var clean = [];
    for (var i = 0; i < source.length; i++) {
        var value = Number(source[i]);
        if (isFinite(value) && value > 0) clean.push(value);
    }
    var sorted = clean.slice().sort(function(a, b) { return a - b; });
    var total = 0;
    for (var j = 0; j < clean.length; j++) total += clean[j];

    var median = percentile(sorted, 50);
    var late = 0;
    var over33 = 0;
    for (var k = 0; k < clean.length; k++) {
        if (median > 0 && clean[k] > median * 1.5) late++;
        if (clean[k] > 33.4) over33++;
    }

    var seconds = Number(durationMs) > 0 ? Number(durationMs) / 1000 : 0;
    var swapped = Number(swappedFrames) > 0 ? Number(swappedFrames) : 0;
    return {
        frames: clean.length,
        meanMs: clean.length ? round2(total / clean.length) : 0,
        p50Ms: round2(median),
        p95Ms: round2(percentile(sorted, 95)),
        p99Ms: round2(percentile(sorted, 99)),
        maxMs: round2(sorted.length ? sorted[sorted.length - 1] : 0),
        lateFrames: late,
        over33ms: over33,
        swappedFrames: swapped,
        durationMs: Math.round(Number(durationMs) || 0),
        swappedFps: seconds > 0 ? round2(swapped / seconds) : 0
    };
}
