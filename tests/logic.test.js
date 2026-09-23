'use strict';

// Unit tests for the pure logic behind Fathom: depth and fog, focus recency,
// the field (filter, navigation, workspaces, wheel, labels), the geometry of
// the Deep and the map, focus dispatch strings and frame statistics.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { load } = require('./lib/qml-js');

const src = (name) => path.join(__dirname, '..', 'src', name);
const Depth = load(src('Depth.js'));
const Recency = load(src('Recency.js'));
const Focus = load(src('Focus.js'));
const Stats = load(src('Stats.js'));
const Field = load(src('Field.js'));
const Layout = load(src('Layout.js'));

const close = (actual, expected, epsilon = 1e-9) =>
  assert.ok(Math.abs(actual - expected) <= epsilon, `${actual} is not within ${epsilon} of ${expected}`);

test('depth follows log2(1 + seconds / 30), clamped to [0, 8]', () => {
  close(Depth.depthForSeconds(0), 0);
  close(Depth.depthForSeconds(30), 1);
  close(Depth.depthForSeconds(90), 2);
  close(Depth.depthForSeconds(210), 3);
  close(Depth.depthForSeconds(7650), 8);
  close(Depth.depthForSeconds(86400), 8);
  close(Depth.depthForSeconds(-5), 0);
  close(Depth.depthForSeconds(Infinity), 8);
  close(Depth.depthForSeconds(NaN), 8);
  close(Depth.depthForSeconds(15), Math.log2(1.5));
});

test('fog follows depth * 0.08, clamped with depth', () => {
  close(Depth.fogForDepth(0), 0);
  close(Depth.fogForDepth(1), 0.08);
  close(Depth.fogForDepth(8), 0.64);
  close(Depth.fogForDepth(20), 0.64);
  close(Depth.fogForDepth(-2), 0);
  close(Depth.fogForDepth(NaN), 0.64);
});

test('addresses normalize to lowercase hex without prefix', () => {
  assert.equal(Recency.normalizeAddress('0x55D1A2b3'), '55d1a2b3');
  assert.equal(Recency.normalizeAddress('55d1a2b3'), '55d1a2b3');
  assert.equal(Recency.normalizeAddress(' 0xabc '), 'abc');
  assert.equal(Recency.normalizeAddress(''), '');
  assert.equal(Recency.normalizeAddress('0x0'), '');
  assert.equal(Recency.normalizeAddress('0x12"; rm -rf'), '');
  assert.equal(Recency.normalizeAddress(null), '');
  assert.equal(Recency.normalizeAddress(undefined), '');
});

test('focus events stamp the window that loses focus', () => {
  const state = Recency.createState();
  assert.equal(Recency.recordFocus(state, 'a1', 1000), true);
  assert.equal(Recency.recordFocus(state, 'b2', 61000), true);
  assert.equal(state.active, 'b2');
  // a1 held focus until b2 took it at t=61s
  close(Recency.secondsSince(state, 'a1', 91000), 30);
  close(Recency.secondsSince(state, 'b2', 91000), 0);
  // an empty activewindowv2 (a layer surface took focus) changes nothing
  assert.equal(Recency.recordFocus(state, '', 95000), false);
  assert.equal(state.active, 'b2');
});

test('open and close events maintain the map', () => {
  const state = Recency.createState();
  Recency.recordFocus(state, 'a1', 0);
  assert.equal(Recency.recordOpen(state, 'c3,1,foot,a title, with commas', 5000), true);
  close(Recency.secondsSince(state, 'c3', 35000), 30);
  // a later openwindow for a known address does not reset it
  Recency.recordOpen(state, 'c3,1,foot,x', 30000);
  close(Recency.secondsSince(state, 'c3', 35000), 30);
  assert.equal(Recency.recordClose(state, 'c3'), true);
  assert.equal(Recency.secondsSince(state, 'c3', 35000), Infinity);
  Recency.recordClose(state, 'a1');
  assert.equal(state.active, '');
  assert.equal(Recency.recordClose(state, 'nothex'), false);
});

test('seeding from the client list uses focusHistoryID steps and never overrides events', () => {
  const state = Recency.createState();
  Recency.recordFocus(state, 'e5', 100000); // arrived before the seed
  const seeded = Recency.seedFromClients(state, [
    { address: '0xa1', focusHistoryID: 0 },
    { address: '0xb2', focusHistoryID: 1 },
    { address: '0xc3', focusHistoryID: 3 },
    { address: '0xd4', focusHistoryID: -1 },
    { address: '0xe5', focusHistoryID: 2 },
    { address: 'bogus', focusHistoryID: 1 },
  ], 100000);
  assert.equal(seeded, 3);
  assert.equal(state.active, 'e5');
  close(Recency.secondsSince(state, 'b2', 100000), 30);
  close(Recency.secondsSince(state, 'c3', 100000), 90);
  assert.equal(Recency.secondsSince(state, 'd4', 100000), Infinity);
  close(Recency.secondsSince(state, 'e5', 100000), 0);
});

test('seeding marks the focusHistoryID 0 window active when nothing else is', () => {
  const state = Recency.createState();
  Recency.seedFromClients(state, [{ address: '0xa1', focusHistoryID: 0 }, { address: '0xb2', focusHistoryID: 1 }], 50000, 10);
  assert.equal(state.active, 'a1');
  close(Recency.secondsSince(state, 'b2', 50000), 10);
});

test('the field is ordered front to back, keeps scratchpads and drops unusable windows', () => {
  const state = Recency.createState();
  Recency.recordFocus(state, 'a1', 0);
  Recency.recordFocus(state, 'b2', 60000);
  Recency.recordFocus(state, 'c3', 90000);
  const field = Recency.buildField([
    { address: '0xa1', title: 'oldest', focusHistoryID: 2 },
    { address: '0xc3', title: 'front', focusHistoryID: 0 },
    { address: '0xb2', title: 'middle', focusHistoryID: 1 },
    { address: '0xf6', title: 'never focused', focusHistoryID: -1 },
    { address: '0xd4', title: 'scratchpad', special: true, focusHistoryID: 3 },
    { address: '0xe5', title: 'unmapped', mapped: false },
    { address: '0xa9', title: 'no handle', hasHandle: false },
    { address: '', title: 'no address' },
  ], state, 120000);
  assert.deepEqual(Array.from(field, (e) => e.title), ['front', 'middle', 'oldest', 'scratchpad', 'never focused']);
  assert.deepEqual(Array.from(field, (e) => e.index), [0, 1, 2, 3, 4]);
  close(field[0].depth, 0);
  close(field[1].seconds, 30);
  close(field[1].depth, 1);
  close(field[2].seconds, 60);
  close(field[4].depth, 8);
  assert.equal(field[0].address, 'c3');
});

test('ties sort by focus history, then address', () => {
  const state = Recency.createState();
  const field = Recency.buildField([
    { address: '0xb', focusHistoryID: -1 },
    { address: '0xa', focusHistoryID: -1 },
    { address: '0xc', focusHistoryID: 4 },
  ], state, 0);
  assert.deepEqual(Array.from(field, (e) => e.address), ['c', 'a', 'b']);
});

test('the fallback active window is at the front before any focus event', () => {
  const state = Recency.createState();
  const field = Recency.buildField([{ address: '0xa1' }, { address: '0xb2' }], state, 0, '0xb2');
  assert.equal(field[0].address, 'b2');
  close(field[0].seconds, 0);
});

test('selection opens one step deep and wraps both ways', () => {
  assert.equal(Recency.initialSelection(0, 1), -1);
  assert.equal(Recency.initialSelection(1, 1), 0);
  assert.equal(Recency.initialSelection(5, 1), 1);
  assert.equal(Recency.initialSelection(5, -1), 4);
  assert.equal(Recency.initialSelection(5, 0), 0);
  assert.equal(Recency.stepSelection(1, 1, 5), 2);
  assert.equal(Recency.stepSelection(4, 1, 5), 0);
  assert.equal(Recency.stepSelection(0, -1, 5), 4);
  assert.equal(Recency.stepSelection(0, 1, 0), -1);
  assert.equal(Recency.stepSelection(9, 1, 3), 0);
});

test('focus requests use hl.dsp under Lua and focuswindow under hyprlang', () => {
  assert.equal(Focus.focusRequest('55d1a2', true), 'hl.dsp.focus({ window = "address:0x55d1a2" })');
  assert.equal(Focus.focusRequest('0x55D1A2', false), 'focuswindow address:0x55d1a2');
  assert.equal(Focus.focusRequest('"); os.execute("x', true), '');
  assert.equal(Focus.focusRequest('', true), '');
});

test('grouped windows activate their tab before focusing', () => {
  assert.equal(Focus.groupIndexFor('0xb2', ['0xa1', '0xb2']), 2);
  assert.equal(Focus.groupIndexFor('b2', []), 0);
  assert.equal(Focus.groupIndexFor('b2', undefined), 0);
  assert.equal(Focus.groupActivateRequest('b2', 2, true), 'hl.dsp.group.active({ window = "address:0xb2", index = 2 })');
  assert.equal(Focus.groupActivateRequest('b2', 0, true), '');
  assert.equal(Focus.groupActivateRequest('b2', 2, false), '');
});

test('frame statistics summarize intervals', () => {
  const intervals = [];
  for (let i = 0; i < 95; i++) intervals.push(16.7);
  for (let i = 0; i < 5; i++) intervals.push(40);
  const summary = Stats.summarize(intervals, 90, 2000);
  assert.equal(summary.frames, 100);
  close(summary.p50Ms, 16.7);
  close(summary.p95Ms, 16.7);
  close(summary.p99Ms, 40);
  close(summary.maxMs, 40);
  assert.equal(summary.lateFrames, 5);
  assert.equal(summary.over33ms, 5);
  close(summary.swappedFps, 45);
  const empty = Stats.summarize([], 0, 0);
  assert.equal(empty.frames, 0);
  assert.equal(empty.p95Ms, 0);
  assert.equal(empty.swappedFps, 0);
  assert.equal(Stats.summarize([NaN, -1, 10], 0, 0).frames, 1);
});

test('the focused window stays in front of the one that just lost focus', () => {
  const state = Recency.createState();
  Recency.seedFromClients(state, [
    { address: '0xa1', focusHistoryID: 0 },
    { address: '0xc3', focusHistoryID: 2 },
  ], 1000);
  Recency.recordFocus(state, 'c3', 5000);
  const field = Recency.buildField([
    { address: '0xa1', focusHistoryID: 0 },
    { address: '0xc3', focusHistoryID: 2 },
  ], state, 5000);
  assert.deepEqual(Array.from(field, (e) => e.address), ['c3', 'a1']);
  assert.equal(field[0].active, true);
  assert.equal(field[1].active, false);
  close(field[1].seconds, 0);
});

// ------------------------------------------------------------ Field.js

const entry = (address, extra = {}) => Object.assign({
  address, appId: 'foot', appName: 'Foot', title: `Window ${address}`,
  workspaceId: 1, workspaceName: '1', seconds: 10, active: false,
}, extra);

test('app names come from the desktop entry, else from the app id', () => {
  assert.equal(Field.appName('com.anthropic.Claude', ''), 'Claude');
  assert.equal(Field.appName('dev.zed.Zed'), 'Zed');
  assert.equal(Field.appName('brave-origin'), 'Brave Origin');
  assert.equal(Field.appName('org.gnome.Nautilus', 'Files'), 'Files');
  assert.equal(Field.appName('', ''), '');
  assert.equal(Field.appName('steam'), 'Steam');
});

test('ages read naturally, long and short', () => {
  assert.equal(Field.ageLabel(0, true), 'focused');
  assert.equal(Field.ageLabel(4), 'just now');
  assert.equal(Field.ageLabel(42), '42 s ago');
  assert.equal(Field.ageLabel(185), '3 min ago');
  assert.equal(Field.ageLabel(7300), '2 h ago');
  assert.equal(Field.ageLabel(200000), '2 d ago');
  assert.equal(Field.ageLabel(Infinity), 'not used yet');
  assert.equal(Field.ageShort(0, true), 'now');
  assert.equal(Field.ageShort(42), '42s');
  assert.equal(Field.ageShort(185), '3m');
  assert.equal(Field.ageShort(Infinity), '');
  assert.equal(Field.ageLabel(60, false, true), 'earlier');
  assert.equal(Field.ageShort(60, false, true), '');
});

test('seeded ages are estimates until Fathom sees focus move', () => {
  const state = Recency.createState();
  Recency.seedFromClients(state, [
    { address: '0xa1', focusHistoryID: 0 },
    { address: '0xb2', focusHistoryID: 1 },
    { address: '0xc3', focusHistoryID: 2 },
  ], 100000);
  let field = Recency.buildField([{ address: 'a1' }, { address: 'b2' }, { address: 'c3' }], state, 100000);
  assert.deepEqual(Array.from(field, (e) => e.estimated), [false, true, true]);
  // Focus moves to c3: a1 lost focus now, c3 is focused; b2 is still a guess.
  Recency.recordFocus(state, 'c3', 110000);
  field = Recency.buildField([{ address: 'a1' }, { address: 'b2' }, { address: 'c3' }], state, 110000);
  assert.deepEqual(Array.from(field, (e) => [e.address, e.estimated]), [['c3', false], ['a1', false], ['b2', true]]);
  Recency.recordClose(state, 'b2');
  assert.equal(state.estimated.b2, undefined);
});

test('workspace labels name scratchpads and named workspaces', () => {
  assert.equal(Field.workspaceLabel('3', 3), '3');
  assert.equal(Field.workspaceLabel('special:term', -98), 'term');
  assert.equal(Field.workspaceLabel('special', -99), 'scratchpad');
  assert.equal(Field.workspaceLabel('name:web', -1337), 'web');
  assert.equal(Field.workspaceLabel('', 4), '4');
  assert.equal(Field.isSpecialName('special:x'), true);
  assert.equal(Field.isSpecialName('named'), false);
});

test('the filter matches every token in app, title or workspace', () => {
  const brave = entry('a1', { appName: 'Brave', appId: 'brave-browser', title: 'Omarchy plugins' });
  assert.equal(Field.matchesQuery(brave, ''), true);
  assert.equal(Field.matchesQuery(brave, 'BRA'), true);
  assert.equal(Field.matchesQuery(brave, 'brave omarchy'), true);
  assert.equal(Field.matchesQuery(brave, 'omarchy brave'), true);
  assert.equal(Field.matchesQuery(brave, 'brave zed'), false);
  assert.equal(Field.matchesQuery(entry('b2', { workspaceName: 'special:term' }), 'term'), true);
});

test('the visible order drops closed windows and filter misses', () => {
  const entries = [entry('a1', { title: 'alpha' }), entry('b2', { title: 'beta' }), entry('c3', { title: 'alpine' })];
  assert.deepEqual(Array.from(Field.visibleOrder(entries, {}, '')), [0, 1, 2]);
  assert.deepEqual(Array.from(Field.visibleOrder(entries, { b2: true }, '')), [0, 2]);
  assert.deepEqual(Array.from(Field.visibleOrder(entries, {}, 'alp')), [0, 2]);
  assert.deepEqual(Array.from(Field.slotsFor([0, 2], 3)), [0, -1, 1]);
});

test('Tab wraps, arrows and the wheel stop at the ends', () => {
  const order = [0, 2, 5];
  assert.equal(Field.step(order, 0, 1, true), 2);
  assert.equal(Field.step(order, 5, 1, true), 0);
  assert.equal(Field.step(order, 0, -1, true), 5);
  assert.equal(Field.step(order, 5, 1, false), 5);
  assert.equal(Field.step(order, 0, -3, false), 0);
  assert.equal(Field.step(order, 0, 5, false), 5);
  // A selection that is not visible restarts at the front.
  assert.equal(Field.step(order, 1, 1, true), 0);
  assert.equal(Field.step([], 0, 1, true), -1);
  assert.equal(Field.first(order), 0);
  assert.equal(Field.last(order), 5);
});

test('a hidden selection moves to the nearest window behind it', () => {
  assert.equal(Field.reselect([0, 2, 3], 2, [0, 1, 2, 3]), 2);
  assert.equal(Field.reselect([0, 3], 2, [0, 1, 2, 3]), 3);
  assert.equal(Field.reselect([0, 1], 3, [0, 1, 2, 3]), 1);
  assert.equal(Field.reselect([4], 9, []), 4);
  assert.equal(Field.reselect([], 1, [0, 1]), -1);
});

test('workspaces group in map order with scratchpads last and empty screens kept', () => {
  const entries = [
    entry('a1', { workspaceId: 3, workspaceName: '3' }),
    entry('b2', { workspaceId: -98, workspaceName: 'special:term' }),
    entry('c3', { workspaceId: 1, workspaceName: '1' }),
    entry('d4', { workspaceId: 3, workspaceName: '3' }),
    entry('e5', { workspaceId: -1337, workspaceName: 'name:web' }),
  ];
  const groups = Field.workspaceGroups(entries, [{ id: 2, name: '2', monitor: 'DP-1' }], [2]);
  assert.deepEqual(Array.from(groups, (g) => g.label), ['1', '2', '3', 'web', 'term']);
  assert.deepEqual(Array.from(groups[2].entries), [0, 3]);
  assert.equal(groups[1].entries.length, 0);
  assert.equal(groups[1].onScreen, true);
  assert.equal(groups[4].special, true);
});

test('left and right step between workspaces, digits jump to one', () => {
  const entries = [
    entry('a1', { workspaceId: 2, workspaceName: '2' }),
    entry('b2', { workspaceId: 1, workspaceName: '1' }),
    entry('c3', { workspaceId: 4, workspaceName: '4' }),
    entry('d4', { workspaceId: 1, workspaceName: '1' }),
  ];
  const groups = Field.workspaceGroups(entries, [], []);
  const order = [0, 1, 2, 3];
  assert.equal(Field.neighborWorkspace(groups, order, 0, 1), 2);
  assert.equal(Field.neighborWorkspace(groups, order, 0, -1), 1);
  assert.equal(Field.neighborWorkspace(groups, order, 1, -1), 1);
  assert.equal(Field.neighborWorkspace(groups, order, 2, 1), 2);
  // A workspace whose windows are all filtered out is skipped.
  assert.equal(Field.neighborWorkspace(groups, [1, 2, 3], 1, 1), 2);
  assert.equal(Field.workspaceByNumber(groups, order, 1), 1);
  assert.equal(Field.workspaceByNumber(groups, order, 4), 2);
  assert.equal(Field.workspaceByNumber(groups, order, 9), -1);
});

test('a wheel notch is one window, touchpad pixels add up', () => {
  assert.deepEqual(Object.assign({}, Field.wheelSteps(0, -120, 0)), { steps: 1, rest: 0 });
  assert.deepEqual(Object.assign({}, Field.wheelSteps(0, 240, 0)), { steps: -2, rest: 0 });
  assert.deepEqual(Object.assign({}, Field.wheelSteps(0, -60, 0)), { steps: 0, rest: -60 });
  assert.deepEqual(Object.assign({}, Field.wheelSteps(-60, -60, 0)), { steps: 1, rest: 0 });
  const slow = Field.wheelSteps(0, 0, -25);
  assert.equal(slow.steps, 0);
  const more = Field.wheelSteps(slow.rest, 0, -40);
  assert.equal(more.steps, 1);
  close(more.rest, -5);
  assert.equal(Field.wheelSteps(0, 0, 0).steps, 0);
});

// ------------------------------------------------------------ Layout.js

const stage = Layout.deepStage(1600, 1000, 70, 320, 1.6);

test('the stage fits the front card and the stack behind it into the Deep', () => {
  close(stage.frontWidth / stage.frontHeight, 1.6, 1e-6);
  const back = Layout.deepPlane(stage, Layout.VISIBLE_STEPS);
  assert.ok(back.y - back.height / 2 >= 70 - 1e-6, 'the last card stays below the top');
  assert.ok(stage.frontY + stage.frontHeight / 2 <= 1000 - 320 + 1e-6, 'the front card stays above the caption');
  assert.ok(back.x + back.width / 2 <= 1600, 'the last card stays on screen');
  const left = stage.frontX - stage.frontWidth / 2;
  const right = back.x + back.width / 2;
  close(left, 1600 - right, 1e-6);
  // Very wide screens do not blow the front card up past half the width.
  const wide = Layout.deepStage(3440, 1440, 70, 400, 3440 / 1440);
  assert.ok(wide.frontWidth <= 3440 * 0.5 + 1e-6);
});

test('cards recede up and to the right, each showing its header above the one in front', () => {
  const front = Layout.deepPlane(stage, 0);
  close(front.x, stage.frontX);
  close(front.y, stage.frontY);
  close(front.width, stage.frontWidth);
  assert.equal(front.opacity, 1);
  let previous = front;
  for (let r = 1; r <= Layout.VISIBLE_STEPS; r++) {
    const card = Layout.deepPlane(stage, r);
    const top = card.y - card.height / 2;
    const previousTop = previous.y - previous.height / 2;
    assert.ok(previousTop - top >= 24, `card ${r} shows at least a 24 px header strip (${previousTop - top})`);
    assert.ok(card.x + card.width / 2 > previous.x + previous.width / 2, `card ${r} shows a band on the right`);
    assert.ok(card.width < previous.width && card.z < previous.z);
    previous = card;
  }
  assert.equal(Layout.deepPlane(stage, Layout.VISIBLE_STEPS + 1).opacity, 0);
});

test('the camera moves continuously and passed cards fade out', () => {
  const at = Layout.deepPlane(stage, 0);
  const before = Layout.deepPlane(stage, -1e-6);
  const after = Layout.deepPlane(stage, 1e-6);
  close(before.x, at.x, 1e-3);
  close(after.x, at.x, 1e-3);
  close(before.width, at.width, 1e-3);
  close(after.y, at.y, 1e-3);
  const passed = Layout.deepPlane(stage, -0.3);
  assert.ok(passed.x < at.x && passed.width > at.width && passed.opacity < 1 && passed.z > at.z);
  assert.equal(Layout.deepPlane(stage, -Layout.PASSED_FADE).opacity, 0);
});

test('windows fit their card without distortion', () => {
  const portrait = Layout.fit(800, 500, 0.8);
  close(portrait.height, 500);
  close(portrait.width, 400);
  close(portrait.x, 200);
  const wide = Layout.fit(800, 500, 3.2);
  close(wide.width, 800);
  close(wide.height, 250);
  close(wide.y, 125);
});

test('minimaps show the screen and the windows parked beside it', () => {
  const viewport = { x: 0, y: 0, width: 1600, height: 1000 };
  const bounds = Layout.minimapBounds(viewport, [{ x: 0, y: 0, width: 1600, height: 1000 }, { x: 1600, y: 0, width: 800, height: 1000 }]);
  assert.deepEqual(Object.assign({}, bounds), { x: 0, y: 0, width: 2400, height: 1000 });
  // Windows parked far away (a scrolling layout) are shown, not cropped.
  const far = Layout.minimapBounds(viewport, [{ x: -700, y: 28, width: 1600, height: 970 }, { x: 9000, y: 0, width: 800, height: 1000 }]);
  close(far.x, -700);
  close(far.width, 10500);
  const strip = Layout.minimapItems(viewport, [{ x: -700, y: 0, width: 1600, height: 1000 }, { x: 9000, y: 0, width: 800, height: 1000 }], 300, 100);
  for (const rect of strip.rects) assert.ok(rect.x >= -1e-6 && rect.x + rect.width <= 300 + 1e-6, 'every window stays inside the minimap');
  const items = Layout.minimapItems(viewport, [{ x: 0, y: 0, width: 800, height: 1000 }, { x: 800, y: 0, width: 800, height: 1000 }], 160, 100);
  close(items.rects[0].width, 80);
  close(items.rects[1].x, 80);
  close(items.viewport.width, 160);
});

test('tabs of a group split their rectangle, unknown geometry falls back to a grid', () => {
  const viewport = { x: 0, y: 0, width: 1600, height: 1000 };
  const same = { x: 0, y: 0, width: 1600, height: 1000 };
  const grouped = Layout.minimapItems(viewport, [same, Object.assign({}, same), Object.assign({}, same)], 160, 100);
  close(grouped.rects[0].width, 160 / 3);
  close(grouped.rects[2].x, 320 / 3);
  const grid = Layout.minimapItems(viewport, [same, null, same, same], 160, 100);
  assert.equal(grid.viewport, null);
  assert.equal(grid.rects.length, 4);
  for (const rect of grid.rects) assert.ok(rect.x >= 0 && rect.x + rect.width <= 160 + 1e-6 && rect.y + rect.height <= 100 + 1e-6);
});

test('map cards follow their aspect and shrink together when the row is full', () => {
  const roomy = Layout.mapCards([1.6, 2.4], 2000, 100, 10, 16, 80);
  close(roomy.widths[0], 176);
  close(roomy.widths[1], 256);
  assert.equal(roomy.scale, 1);
  const full = Layout.mapCards([1.6, 1.6, 1.6, 1.6], 500, 100, 10, 16, 80);
  const total = full.widths.reduce((a, b) => a + b, 0) + 30;
  assert.ok(total <= 500 + 1e-6);
  assert.ok(full.height < 100);
});
