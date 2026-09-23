.pragma library

// Fathom's colors, derived from the four every Omarchy theme gives:
// foreground, background, accent and urgent. Nothing that has to be read is
// taken as it comes. A theme's `muted` is a pale border tone on a light theme
// and nearly the background on some dark ones, so the text tiers are mixed
// from foreground and background and held to a contrast floor instead, and
// the accent is deepened (or lifted) until it reads as a line or as text.
//
// A theme is light when its background is lighter than its text. A dark
// theme gets glass sinking into the dark; a light one gets paper cards
// raised above a pale veil, a white light from the surface, and a scene that
// dims as you dive. The same scene either way, lit for the theme.
//
// Colors come back as "#rrggbb", or "#aarrggbb" with an alpha (Qt's order),
// which QML color properties take as they are. The node tests hold every
// theme Omarchy ships to the contrast floors below.

// Contrast floors (WCAG 2 ratios) against the backdrop, and on the lightest
// card of a dark theme, where only a card's age sits.
var SOFT_CONTRAST = 5.5;   // secondary text: the caption's details, counts, ages
var FAINT_CONTRAST = 4.5;  // tertiary text: key hints, gauge marks, placeholders
var CARD_CONTRAST = 4.5;   // secondary text on a card
var MARK_CONTRAST = 3;     // lines and marks: the selection ring, the lead

// Share of the way from foreground to background each tier aims for.
var SOFT_SHARE = 0.34;
var FAINT_SHARE = 0.5;

// Opacity of the veil over the (blurred) desktop, top to bottom.
var DARK_VEIL = [0.8, 0.86, 0.92];
var LIGHT_VEIL = [0.86, 0.9, 0.95];

var WHITE = { r: 1, g: 1, b: 1, a: 1 };
var BLACK = { r: 0, g: 0, b: 0, a: 1 };
var FALLBACK = { foreground: "#cacccc", background: "#101315", accent: "#cacccc", urgent: "#a55555" };

// "#rgb", "#rrggbb" or "#aarrggbb" (a QML color converts to one of these).
function parse(value) {
    var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    var match = text.match(/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/);
    if (!match) return null;
    var digits = match[1];
    if (digits.length === 3)
        digits = digits[0] + digits[0] + digits[1] + digits[1] + digits[2] + digits[2];
    var alpha = 1;
    if (digits.length === 8) {
        alpha = parseInt(digits.substr(0, 2), 16) / 255;
        digits = digits.substr(2);
    }
    return {
        r: parseInt(digits.substr(0, 2), 16) / 255,
        g: parseInt(digits.substr(2, 2), 16) / 255,
        b: parseInt(digits.substr(4, 2), 16) / 255,
        a: alpha
    };
}

function channel(value) {
    var byte = Math.round(Math.max(0, Math.min(1, value)) * 255);
    return (byte < 16 ? "0" : "") + byte.toString(16);
}

// With `alpha` below 1, "#aarrggbb".
function hex(color, alpha) {
    var a = alpha === undefined ? 1 : alpha;
    var rgb = channel(color.r) + channel(color.g) + channel(color.b);
    return a >= 1 ? "#" + rgb : "#" + channel(a) + rgb;
}

// `share` of the way from a to b.
function mix(a, b, share) {
    var t = Math.max(0, Math.min(1, share));
    return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: 1 };
}

// As it will be drawn: whole bytes per channel. Contrast is judged on this.
function rounded(color) {
    return parse(hex(color));
}

function linear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

// Relative luminance, 0 (black) to 1 (white).
function luminance(color) {
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

// Contrast ratio, 1 to 21.
function contrast(a, b) {
    var la = luminance(a);
    var lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// `color` moved toward `toward` until it holds `ratio` against `against`
// (or as far as it can go).
function readable(color, against, ratio, toward) {
    var result = color;
    for (var step = 1; step <= 40 && contrast(result, against) < ratio; step++)
        result = rounded(mix(color, toward, step / 40));
    return result;
}

// A text tier: `share` of the way from foreground to background, pulled
// back toward the foreground until it holds every floor, each a
// [surface, ratio] pair.
function tier(foreground, background, share, floors) {
    for (var s = share; s > 0.001; s -= 0.02) {
        var color = rounded(mix(foreground, background, s));
        var holds = true;
        for (var i = 0; i < floors.length && holds; i++)
            holds = contrast(color, floors[i][0]) >= floors[i][1];
        if (holds) return color;
    }
    return foreground;
}

function isLight(foreground, background) {
    return luminance(background) > luminance(foreground);
}

// Every color the field draws with. `theme` holds foreground, background,
// accent and urgent, as colors or strings.
function derive(theme) {
    var source = theme || {};
    var fg = parse(source.foreground) || parse(FALLBACK.foreground);
    var bg = parse(source.background) || parse(FALLBACK.background);
    var accentIn = parse(source.accent) || fg;
    var urgentIn = parse(source.urgent) || parse(FALLBACK.urgent);
    var light = isLight(fg, bg);
    // Away from the background: deeper on a light theme, brighter on a dark one.
    var away = light ? BLACK : WHITE;
    var veil = light ? LIGHT_VEIL : DARK_VEIL;
    var accent = readable(accentIn, bg, MARK_CONTRAST, away);
    var paper = function (share) { return mix(bg, WHITE, share); };
    // On a dark theme the selected card is lighter than the veil, so text
    // on it has less contrast; on a light theme it has more.
    var cardSelectedTop = light ? paper(0.9) : mix(bg, fg, 0.12);

    return {
        light: light,

        veilTop: hex(bg, veil[0]),
        veilMiddle: hex(bg, veil[1]),
        veilBottom: hex(bg, veil[2]),
        // Light from the surface, strongest at the top of the screen.
        surfaceLight: light ? hex(WHITE, 0.55) : hex(fg, 0.06),
        surfaceLightEnd: light ? hex(WHITE, 0) : hex(fg, 0),
        // What the scene sinks into as the selection goes deeper.
        depthShade: light ? hex(mix(bg, fg, 0.45)) : hex(bg),

        text: hex(fg),
        textSoft: hex(tier(fg, bg, SOFT_SHARE, [[bg, SOFT_CONTRAST], [cardSelectedTop, CARD_CONTRAST]])),
        textFaint: hex(tier(fg, bg, FAINT_SHARE, [[bg, FAINT_CONTRAST]])),
        accent: hex(accent),
        accentText: hex(readable(accentIn, bg, FAINT_CONTRAST, away)),
        urgent: hex(readable(urgentIn, bg, MARK_CONTRAST, away)),
        background: hex(bg),

        // The cards of the Deep.
        cardTop: light ? hex(paper(0.72)) : hex(mix(bg, fg, 0.085)),
        cardBottom: light ? hex(paper(0.5)) : hex(mix(bg, fg, 0.035)),
        cardSelectedTop: hex(cardSelectedTop),
        cardSelectedBottom: light ? hex(paper(0.7)) : hex(mix(bg, fg, 0.06)),
        cardBorder: hex(fg, light ? 0.16 : 0.11),
        cardBorderHover: hex(fg, light ? 0.34 : 0.3),
        shadow: light ? hex(mix(fg, BLACK, 0.5), 0.2) : hex(BLACK, 0.55),
        glow: hex(accentIn, light ? 0.34 : 0.38),
        // Behind a capture until its first frame, and behind the app's face.
        bed: hex(mix(bg, fg, light ? 0.06 : 0.04)),
        // An edge around the capture, so a light window keeps its outline on
        // a light card.
        frameEdge: hex(fg, light ? 0.12 : 0.06),
        // Older windows fade into the backdrop: into the dark on a dark
        // theme, into a haze on a light one, where a dark window fogged as
        // far would turn to milk.
        fog: hex(bg),
        fogStrength: light ? 0.7 : 1,

        // The filter, the key hints and the still-frame badge.
        panel: light ? hex(paper(0.7), 0.94) : hex(bg, 0.85),
        panelBorder: hex(fg, light ? 0.18 : 0.14),
        key: light ? hex(paper(0.8)) : hex(fg, 0.08),
        keyBorder: hex(fg, light ? 0.24 : 0.2),

        // The map of workspaces.
        mapCard: light ? hex(paper(0.6), 0.8) : hex(fg, 0.045),
        mapCardBorder: hex(fg, light ? 0.13 : 0.1),
        mapCardSelected: light ? hex(mix(paper(0.6), accentIn, 0.08), 0.9) : hex(accentIn, 0.08),
        mapCardSelectedBorder: hex(accent, 0.7),
        screen: light ? hex(fg, 0.05) : hex(BLACK, 0.22),
        screenBorder: hex(fg, light ? 0.16 : 0.12),
        screenBorderOn: hex(fg, light ? 0.32 : 0.28),
        tile: light ? hex(paper(0.8)) : hex(mix({ r: 0.12, g: 0.12, b: 0.12, a: 1 }, fg, 0.08), 0.9),
        tileHover: light ? hex(mix(bg, fg, 0.12)) : hex(fg, 0.2),
        tileSelected: light ? hex(mix(paper(0.8), accentIn, 0.24)) : hex(accentIn, 0.36),
        tileBorder: hex(fg, light ? 0.3 : 0.24),
        tileBorderActive: hex(fg, light ? 0.7 : 0.75),

        // The sounding line.
        line: hex(fg, light ? 0.26 : 0.18),
        tick: hex(fg, light ? 0.38 : 0.28),
        mark: hex(fg, light ? 0.55 : 0.6),
        markBorder: hex(fg, 0.5)
    };
}
