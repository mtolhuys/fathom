.pragma library
.import "Depth.js" as Depth

// Focus recency for Fathom.
//
// Hyprland keeps a focus order (focusHistoryID) but no timestamps, so Fathom
// keeps its own map of window address -> the last moment that window held
// focus. The focused window itself is always zero seconds away.
//
// All functions work on a plain state object and never touch Quickshell, so
// the same file runs inside the shell and under node.

// Seeding: the k-th most recently focused window at startup is assumed to
// have lost focus k * 30 seconds ago (one depth unit per step, roughly).
var SEED_STEP_SECONDS = 30;

function createState() {
    return { lastActive: {}, active: "" };
}

// Hyprland prints addresses as "0x55d1…" (hyprctl) or "55d1…" (socket2 and
// Quickshell). Keys are stored lowercase without the prefix. Anything that is
// not a plain non-zero hex handle is rejected.
function normalizeAddress(value) {
    if (value === undefined || value === null) return "";
    var text = String(value).trim().toLowerCase().replace(/^0x/, "");
    return /^[0-9a-f]+$/.test(text) && !/^0+$/.test(text) ? text : "";
}

function firstField(eventData) {
    return String(eventData === undefined || eventData === null ? "" : eventData).split(",")[0];
}

// socket2 activewindowv2>>ADDRESS. An empty address (a layer surface took
// focus) changes nothing.
function recordFocus(state, address, nowMs) {
    var key = normalizeAddress(address);
    if (!key) return false;
    if (state.active && state.active !== key)
        state.lastActive[state.active] = nowMs;
    state.active = key;
    state.lastActive[key] = nowMs;
    return true;
}

// socket2 openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE. A new window counts as
// recent from the moment it opens, even if it never takes focus.
function recordOpen(state, eventData, nowMs) {
    var key = normalizeAddress(firstField(eventData));
    if (!key) return false;
    if (!(key in state.lastActive))
        state.lastActive[key] = nowMs;
    return true;
}

// socket2 closewindow>>ADDRESS
function recordClose(state, eventData) {
    var key = normalizeAddress(firstField(eventData));
    if (!key) return false;
    delete state.lastActive[key];
    if (state.active === key) state.active = "";
    return true;
}

// Seed from Hyprland's client list (the JSON of `hyprctl clients -j`, which
// Quickshell fetches itself). Events that already arrived are newer than
// the snapshot, so a window the map already knows is left alone. Windows that
// never had focus (focusHistoryID < 0) stay unknown: maximum depth.
function seedFromClients(state, clients, nowMs, stepSeconds) {
    var step = (Number(stepSeconds) > 0 ? Number(stepSeconds) : SEED_STEP_SECONDS) * 1000;
    var list = clients && clients.length !== undefined ? clients : [];
    var seeded = 0;
    for (var i = 0; i < list.length; i++) {
        var client = list[i] || {};
        var key = normalizeAddress(client.address);
        if (!key || key in state.lastActive) continue;
        var history = Number(client.focusHistoryID);
        if (!isFinite(history) || history < 0) continue;
        state.lastActive[key] = nowMs - history * step;
        if (history === 0 && !state.active) state.active = key;
        seeded++;
    }
    return seeded;
}

function secondsSince(state, address, nowMs, fallbackActive) {
    var key = normalizeAddress(address);
    if (!key) return Infinity;
    var active = state.active || normalizeAddress(fallbackActive);
    if (key === active) return 0;
    var at = state.lastActive[key];
    if (at === undefined) return Infinity;
    return Math.max(0, (nowMs - at) / 1000);
}

function historyRank(value) {
    var number = Number(value);
    return isFinite(number) && number >= 0 ? number : Infinity;
}

// Turn window candidates into the ordered field, front (most recent) first.
// A candidate is { address, hasHandle, mapped, focusHistoryID, ... };
// every other key is carried through untouched.
function buildField(candidates, state, nowMs, fallbackActive) {
    var list = candidates && candidates.length !== undefined ? candidates : [];
    var activeKey = state.active || normalizeAddress(fallbackActive);
    var entries = [];
    for (var i = 0; i < list.length; i++) {
        var candidate = list[i];
        if (!candidate) continue;
        var key = normalizeAddress(candidate.address);
        if (!key) continue;
        if (candidate.hasHandle === false) continue;
        if (candidate.mapped === false) continue;

        var entry = {};
        for (var name in candidate) entry[name] = candidate[name];
        entry.address = key;
        entry.active = key === activeKey;
        entry.seconds = secondsSince(state, key, nowMs, fallbackActive);
        entry.depth = Depth.depthForSeconds(entry.seconds);
        entries.push(entry);
    }

    // The focused window is always in front. The window that just lost focus
    // is also zero seconds away, so seconds alone cannot order the two.
    entries.sort(function(a, b) {
        if (a.active !== b.active) return a.active ? -1 : 1;
        if (a.seconds !== b.seconds) return a.seconds < b.seconds ? -1 : 1;
        var ha = historyRank(a.focusHistoryID);
        var hb = historyRank(b.focusHistoryID);
        if (ha !== hb) return ha < hb ? -1 : 1;
        return a.address < b.address ? -1 : (a.address > b.address ? 1 : 0);
    });

    for (var j = 0; j < entries.length; j++) entries[j].index = j;
    return entries;
}

// Opening chord: Tab lands on the previously used window, Shift+Tab wraps to
// the oldest. Opening without a step starts at the front.
function initialSelection(count, step) {
    if (count <= 0) return -1;
    if (step > 0) return count > 1 ? 1 : 0;
    if (step < 0) return count - 1;
    return 0;
}

function stepSelection(index, delta, count) {
    if (count <= 0) return -1;
    var current = Math.max(0, Math.min(count - 1, Number(index) || 0));
    var next = (current + Math.round(Number(delta) || 0)) % count;
    return next < 0 ? next + count : next;
}
