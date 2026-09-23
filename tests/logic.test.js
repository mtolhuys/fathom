'use strict';

// Unit tests for the pure logic behind Fathom: depth rules, focus recency,
// focus dispatch strings and frame statistics.

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { load } = require('./lib/qml-js');

const src = (name) => path.join(__dirname, '..', 'src', name);
const Depth = load(src('Depth.js'));
const Recency = load(src('Recency.js'));
const Focus = load(src('Focus.js'));
const Stats = load(src('Stats.js'));

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

test('scale and opacity follow the spec formulas', () => {
  close(Depth.scaleForDepth(0), 1);
  close(Depth.scaleForDepth(1), 1 / 1.45);
  close(Depth.scaleForDepth(8), 1 / 4.6);
  close(Depth.scaleForDepth(12), 1 / 4.6);
  close(Depth.opacityForDepth(0), 1);
  close(Depth.opacityForDepth(4), 0.64);
  close(Depth.opacityForDepth(8), 0.28);
  close(Depth.opacityForDepth(-3), 1);
});

test('planes at or behind the camera use depth relative to the camera', () => {
  close(Depth.planeScale(0, 0), 1);
  close(Depth.planeOpacity(0, 0), 1);
  close(Depth.planeScale(2, 3), 1 / 1.9);
  close(Depth.planeOpacity(2, 3), 0.82);
  // a transient negative relative depth never enlarges a plane behind the camera
  close(Depth.planeScale(-0.4, 1), 1);
});

test('passed planes fade out within half a step and grow a little', () => {
  close(Depth.planeOpacity(0, -0.25), 0.5);
  close(Depth.planeOpacity(0, -0.5), 0);
  close(Depth.planeOpacity(0, -2), 0);
  close(Depth.planeScale(0, -0.5), 1.15);
  close(Depth.planeScale(0, -3), 1.3);
});

test('plane visuals are continuous where the camera meets a plane', () => {
  close(Depth.planeScale(0, -1e-9), Depth.planeScale(0, 0), 1e-6);
  close(Depth.planeOpacity(0, -1e-9), Depth.planeOpacity(0, 0), 1e-6);
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

test('the field is ordered front to back and filters unusable windows', () => {
  const state = Recency.createState();
  Recency.recordFocus(state, 'a1', 0);
  Recency.recordFocus(state, 'b2', 60000);
  Recency.recordFocus(state, 'c3', 90000);
  const field = Recency.buildField([
    { address: '0xa1', title: 'oldest', focusHistoryID: 2 },
    { address: '0xc3', title: 'front', focusHistoryID: 0 },
    { address: '0xb2', title: 'middle', focusHistoryID: 1 },
    { address: '0xf6', title: 'never focused', focusHistoryID: -1 },
    { address: '0xd4', title: 'special', special: true },
    { address: '0xe5', title: 'unmapped', mapped: false },
    { address: '0xa9', title: 'no handle', hasHandle: false },
    { address: '', title: 'no address' },
  ], state, 120000);
  assert.deepEqual(Array.from(field, (e) => e.title), ['front', 'middle', 'oldest', 'never focused']);
  assert.deepEqual(Array.from(field, (e) => e.index), [0, 1, 2, 3]);
  close(field[0].depth, 0);
  close(field[1].seconds, 30);
  close(field[1].depth, 1);
  close(field[2].seconds, 60);
  close(field[3].depth, 8);
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

test('planes recede toward the vanishing point and peek past the front plane', () => {
  const front = Depth.planeCenter(400, 300, 736, 60, 1, 0, 6, 4);
  close(front.x, 400);
  close(front.y, 300);
  const deep = Depth.planeCenter(400, 300, 736, 60, 0.5, 2, 6, 4);
  close(deep.x, 400 + 0.5 * 336 + 12);
  close(deep.y, 300 - 0.5 * 240 - 8);
  // Right edge of a plane of width 448 at scale 0.5 passes the front plane's right edge.
  assert.ok(deep.x + 0.5 * 448 / 2 > front.x + 448 / 2);
  const passed = Depth.planeCenter(400, 300, 736, 60, 1.2, -1, 6, 4);
  assert.ok(passed.x < 400 && passed.y > 300);
});
