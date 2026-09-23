.pragma library
.import "Recency.js" as Recency

// The field as the user moves through it: which windows are shown (closed
// windows and filter misses drop out), how the selection steps, how windows
// group into workspaces for the map, and the labels the view prints.
//
// A field is frozen when it opens: entries keep their index for the whole
// switch, and everything here works on lists of entry indices, so the view
// never has to rebuild a plane (and restart its capture) when the order
// changes.

// ------------------------------------------------------------ labels

function titleCase(word) {
    return word ? word.charAt(0).toUpperCase() + word.slice(1) : "";
}

// "com.anthropic.Claude" -> "Claude", "brave-origin" -> "Brave Origin". The
// desktop entry's own name wins when there is one.
function appName(appId, desktopName) {
    var named = String(desktopName || "").trim();
    if (named) return named;
    var id = String(appId || "").trim();
    if (!id) return "";
    var parts = id.split(".");
    var last = parts.length > 2 ? parts[parts.length - 1] : id;
    var words = last.split(/[-_\s]+/);
    var out = [];
    for (var i = 0; i < words.length; i++) if (words[i]) out.push(titleCase(words[i]));
    return out.join(" ");
}

// How long ago a window last had focus, for captions and plane labels. An
// estimated age (seeded from Hyprland's focus order when the shell started)
// is not printed as if it were measured.
function ageLabel(seconds, active, estimated) {
    if (active) return "focused";
    if (estimated) return "earlier";
    var value = Number(seconds);
    if (!isFinite(value)) return "not used yet";
    if (value < 10) return "just now";
    if (value < 60) return Math.floor(value) + " s ago";
    if (value < 3600) return Math.floor(value / 60) + " min ago";
    if (value < 86400) return Math.floor(value / 3600) + " h ago";
    return Math.floor(value / 86400) + " d ago";
}

// The short form for tight labels: "now", "40s", "12m", "3h", "2d".
function ageShort(seconds, active, estimated) {
    if (active) return "now";
    if (estimated) return "";
    var value = Number(seconds);
    if (!isFinite(value)) return "";
    if (value < 10) return "now";
    if (value < 60) return Math.floor(value) + "s";
    if (value < 3600) return Math.floor(value / 60) + "m";
    if (value < 86400) return Math.floor(value / 3600) + "h";
    return Math.floor(value / 86400) + "d";
}

// The gauge's marks: depth d is 30 * (2^d - 1) seconds ago.
function depthMarkLabel(depth) {
    var d = Math.round(Number(depth) || 0);
    if (d <= 0) return "now";
    if (d >= 8) return "2h+";
    return ageShort(30 * (Math.pow(2, d) - 1), false, false);
}

// "2.3 fathoms", "1 fathom". Depth is Fathom's unit for how far back a window
// was used; an estimated age has no reading.
function fathomLabel(depth, active, estimated) {
    if (active || estimated) return "";
    var d = Math.round(Math.max(0, Number(depth) || 0) * 10) / 10;
    if (d === 0) return "at the surface";
    return d + (d === 1 ? " fathom" : " fathoms");
}

function isSpecialName(name) {
    return String(name || "").indexOf("special") === 0;
}

// "special:scratch" -> "scratch", "special" -> "scratchpad", "3" -> "3".
function workspaceLabel(name, id) {
    var text = String(name || "");
    if (isSpecialName(text)) {
        var rest = text.replace(/^special:?/, "");
        return rest || "scratchpad";
    }
    if (text) return text.replace(/^name:/, "");
    return id === null || id === undefined ? "?" : String(id);
}

// ------------------------------------------------------------ filter

function normalizeQuery(query) {
    return String(query || "").toLowerCase().replace(/\s+/g, " ").replace(/^ /, "");
}

// Every space-separated token must appear in the app name, app id, title or
// workspace name. Case-insensitive, in any order.
function matchesQuery(entry, query) {
    var tokens = normalizeQuery(query).split(" ");
    if (!entry) return false;
    var fields = [entry.appName, entry.appId, entry.title, workspaceLabel(entry.workspaceName, entry.workspaceId)];
    var haystack = fields.join(" ").toLowerCase();
    for (var i = 0; i < tokens.length; i++) {
        if (tokens[i] && haystack.indexOf(tokens[i]) === -1) return false;
    }
    return true;
}

// Entry indices shown, front to back: not closed, matching the query.
// `closed` maps an entry address to true.
function visibleOrder(entries, closed, query) {
    var list = entries && entries.length !== undefined ? entries : [];
    var gone = closed || {};
    var order = [];
    for (var i = 0; i < list.length; i++) {
        var entry = list[i];
        if (!entry || gone[entry.address]) continue;
        if (!matchesQuery(entry, query)) continue;
        order.push(i);
    }
    return order;
}

// slots[entryIndex] = position in the visible order, or -1 when hidden.
function slotsFor(order, count) {
    var slots = [];
    for (var i = 0; i < count; i++) slots.push(-1);
    for (var j = 0; j < order.length; j++) {
        if (order[j] >= 0 && order[j] < count) slots[order[j]] = j;
    }
    return slots;
}

// ------------------------------------------------------------ navigation

function slotOf(order, index) {
    for (var i = 0; i < order.length; i++) if (order[i] === index) return i;
    return -1;
}

// The entry `delta` visible windows away. Tab wraps like classic Alt-Tab;
// arrows, paging and the wheel stop at the ends. A selection that is no
// longer visible (filtered out, closed) moves to the front of what is.
function step(order, index, delta, wrap) {
    if (!order || !order.length) return -1;
    var slot = slotOf(order, index);
    if (slot < 0) return order[0];
    var count = order.length;
    var next = slot + Math.round(Number(delta) || 0);
    if (wrap) {
        next = next % count;
        if (next < 0) next += count;
    } else {
        next = Math.max(0, Math.min(count - 1, next));
    }
    return order[next];
}

function first(order) {
    return order && order.length ? order[0] : -1;
}

function last(order) {
    return order && order.length ? order[order.length - 1] : -1;
}

// Keeps the selection on the same window when it is still visible, else the
// nearest visible window behind where it was, else the front.
function reselect(order, index, previousOrder) {
    if (!order || !order.length) return -1;
    if (slotOf(order, index) >= 0) return index;
    var before = previousOrder || [];
    var at = slotOf(before, index);
    for (var i = at + 1; at >= 0 && i < before.length; i++) {
        if (slotOf(order, before[i]) >= 0) return before[i];
    }
    for (var j = at - 1; at >= 0 && j >= 0; j--) {
        if (slotOf(order, before[j]) >= 0) return before[j];
    }
    return order[0];
}

// ------------------------------------------------------------ workspaces

function workspaceKey(entry) {
    if (entry.workspaceId !== null && entry.workspaceId !== undefined && isFinite(entry.workspaceId))
        return "id:" + entry.workspaceId;
    return "name:" + String(entry.workspaceName || "");
}

// Regular workspaces by number, then named ones by name, then scratchpads.
function workspaceRank(group) {
    if (group.special) return 2;
    if (isFinite(group.id) && group.id > 0 && !/^name:/.test(group.name || "")) return 0;
    return 1;
}

function compareGroups(a, b) {
    var ra = workspaceRank(a);
    var rb = workspaceRank(b);
    if (ra !== rb) return ra - rb;
    if (ra === 0 && a.id !== b.id) return a.id - b.id;
    var la = a.label.toLowerCase();
    var lb = b.label.toLowerCase();
    return la < lb ? -1 : (la > lb ? 1 : 0);
}

// Groups entries by workspace for the map. `extra` lists workspaces that must
// appear even when empty (the ones on screen): { id, name, monitor }.
// Each group: { key, id, name, label, special, monitor, onScreen, entries }
// with entries in recency order (the field's order).
function workspaceGroups(entries, extra, onScreenIds) {
    var list = entries && entries.length !== undefined ? entries : [];
    var visible = onScreenIds || [];
    var byKey = {};
    var groups = [];

    function groupFor(id, name, monitor) {
        var probe = { workspaceId: id, workspaceName: name };
        var key = workspaceKey(probe);
        if (!byKey[key]) {
            var numeric = id !== null && id !== undefined && isFinite(id) ? Number(id) : null;
            byKey[key] = {
                key: key,
                id: numeric,
                name: String(name || ""),
                label: workspaceLabel(name, numeric),
                special: isSpecialName(name),
                monitor: String(monitor || ""),
                onScreen: numeric !== null && visible.indexOf(numeric) !== -1,
                entries: []
            };
            groups.push(byKey[key]);
        }
        return byKey[key];
    }

    for (var i = 0; i < list.length; i++) {
        var entry = list[i];
        if (!entry) continue;
        var group = groupFor(entry.workspaceId, entry.workspaceName, entry.monitorName);
        if (!group.monitor && entry.monitorName) group.monitor = String(entry.monitorName);
        group.entries.push(i);
    }
    var more = extra || [];
    for (var j = 0; j < more.length; j++) {
        if (more[j]) groupFor(more[j].id, more[j].name, more[j].monitor);
    }
    groups.sort(compareGroups);
    return groups;
}

function groupOf(groups, index) {
    for (var i = 0; i < groups.length; i++) {
        if (groups[i].entries.indexOf(index) !== -1) return i;
    }
    return -1;
}

// The most recent visible window of a group, or -1.
function groupFront(group, order) {
    if (!group) return -1;
    for (var i = 0; i < group.entries.length; i++) {
        if (slotOf(order, group.entries[i]) >= 0) return group.entries[i];
    }
    return -1;
}

// Left and right: the most recent window of the next workspace (in map
// order) that has a visible window. Stops at the ends.
function neighborWorkspace(groups, order, index, direction) {
    var at = groupOf(groups, index);
    var dir = direction < 0 ? -1 : 1;
    if (at < 0) return first(order);
    for (var i = at + dir; i >= 0 && i < groups.length; i += dir) {
        var front = groupFront(groups[i], order);
        if (front >= 0) return front;
    }
    return index;
}

// Number keys: the most recent visible window on workspace `number`.
function workspaceByNumber(groups, order, number) {
    for (var i = 0; i < groups.length; i++) {
        if (!groups[i].special && groups[i].id === number) return groupFront(groups[i], order);
    }
    return -1;
}

// ------------------------------------------------------------ keys

// The one printable character a key press types, or "". Alt+letter can
// arrive with no text at all; the key code (Qt.Key_A..Z, Qt.Key_0..9, which
// are their ASCII codes) stands in for it.
function typedCharacter(key, shift, text) {
    var typed = String(text || "");
    if (!typed && key >= 0x41 && key <= 0x5a) typed = String.fromCharCode(shift ? key : key + 32);
    if (!typed && key >= 0x30 && key <= 0x39) typed = String.fromCharCode(key);
    if (typed.length !== 1 || typed < " " || typed === "\u007f") return "";
    return typed;
}

// ------------------------------------------------------------ wheel

// Wheel input: mice report 120 per notch (angleDelta), touchpads report
// pixels. Returns { steps, rest }: whole window steps to take now and the
// remainder to carry into the next event, so slow touchpad scrolls add up
// and a notch is always exactly one window.
var PIXELS_PER_STEP = 60;
var ANGLE_PER_STEP = 120;

function wheelSteps(carry, angleDelta, pixelDelta) {
    var pixels = Number(pixelDelta) || 0;
    var unit = pixels !== 0 ? PIXELS_PER_STEP : ANGLE_PER_STEP;
    var total = (Number(carry) || 0) + (pixels !== 0 ? pixels : (Number(angleDelta) || 0));
    // Scrolling down (negative delta) dives deeper.
    var steps = total <= -unit ? Math.ceil(total / unit) : (total >= unit ? Math.floor(total / unit) : 0);
    return { steps: steps === 0 ? 0 : -steps, rest: total - steps * unit };
}
