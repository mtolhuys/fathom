.pragma library
.import "Recency.js" as Recency

// Hyprland dispatch requests for focusing the selection. Fathom never moves,
// resizes or closes a window; these two requests are the only compositor
// writes it makes.
//
// Omarchy Quattro runs Hyprland with a Lua config, where dispatchers are Lua
// expressions (hl.dsp.*). Under a hyprlang config the classic dispatcher
// string is used instead. Addresses are sanitized to plain hex first, so no
// window title or class can ever reach a dispatch string.

function dispatchAddress(value) {
    var key = Recency.normalizeAddress(value);
    return key ? "0x" + key : "";
}

// Focusing a window on another workspace switches to that workspace.
function focusRequest(address, usingLua) {
    var target = dispatchAddress(address);
    if (!target) return "";
    return usingLua
        ? 'hl.dsp.focus({ window = "address:' + target + '" })'
        : "focuswindow address:" + target;
}

// 1-based position of the window in its Hyprland group, 0 when ungrouped.
function groupIndexFor(address, grouped) {
    var key = Recency.normalizeAddress(address);
    if (!key || !grouped || grouped.length === undefined) return 0;
    for (var i = 0; i < grouped.length; i++) {
        if (Recency.normalizeAddress(grouped[i]) === key) return i + 1;
    }
    return 0;
}

// hl.dsp.focus ignores a hidden group tab, so a grouped window has its tab
// activated first (same approach as the hyprland-alttab plugin).
function groupActivateRequest(address, groupIndex, usingLua) {
    var target = dispatchAddress(address);
    var index = Math.round(Number(groupIndex) || 0);
    if (!target || !usingLua || index <= 0) return "";
    return 'hl.dsp.group.active({ window = "address:' + target + '", index = ' + index + ' })';
}
