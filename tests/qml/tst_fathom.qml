// Offscreen tests for the real Fathom controller, field view, planes, frame
// probe and recency tracker, against stub Quickshell modules (tests/qml/stubs).
// tests/qml/run.sh copies src/ next to this file with FieldSurface.qml swapped
// for the plain-item host, then runs qmltestrunner.

import QtQuick
import QtTest
import FathomTest
import Quickshell.Hyprland
import qs.Commons
import "../src"
import "../src/Depth.js" as Depth
import "../src/Layout.js" as Layout

TestCase {
  id: testCase

  name: "Fathom"
  when: windowShown
  // TestCase is invisible by default, and invisible items get no pointer
  // events.
  visible: true
  width: 800
  height: 600

  Component {
    id: fathomComponent

    Fathom {}
  }

  function toplevel(address, workspaceId, history, options) {
    const extra = options || {}
    return {
      address: address,
      title: "Window " + address,
      workspace: { id: workspaceId, name: String(workspaceId) },
      wayland: extra.noHandle ? null : {
        appId: "foot",
        contentReady: extra.contentReady !== false,
        width: 1600,
        height: 1000
      },
      lastIpcObject: {
        mapped: extra.mapped !== false,
        focusHistoryID: history,
        size: [1600, 1000],
        grouped: extra.grouped || []
      }
    }
  }

  // Three windows, a1 focused now, b2 before it, c3 before that. Workspace 1
  // is on screen, workspace 2 is not.
  function setUpDesktop(list) {
    FakeSystem.reset()
    const values = list || [toplevel("a1", 1, 0), toplevel("b2", 1, 1), toplevel("c3", 2, 2)]
    Hyprland.usingLua = true
    Hyprland.toplevels = { values: values }
    Hyprland.activeToplevel = values[0]
    Hyprland.focusedMonitor = { name: "eDP-1" }
    Hyprland.monitors = { values: [{ name: "eDP-1", activeWorkspace: { id: 1 } }] }
    Hyprland.dispatches = []
    Hyprland.refreshCount = 0
  }

  function createFathom() {
    const fathom = createTemporaryObject(fathomComponent, testCase)
    verify(fathom !== null, "Fathom instantiates")
    const ipc = FakeSystem.ipc("fathom")
    verify(ipc !== null, "registers the fathom IPC target")
    tryVerify(function() { return JSON.parse(ipc.state()).seeded === true }, 2000, "seeds from the toplevels' focusHistoryID")
    return fathom
  }

  function lastDispatches() {
    return Hyprland.dispatches
  }

  function init() {
    setUpDesktop()
  }

  function test_seed_orders_field_front_to_back() {
    createFathom()
    const rows = JSON.parse(FakeSystem.ipc("fathom").field())
    compare(rows.length, 3)
    compare(rows[0].address, "0xa1")
    compare(rows[1].address, "0xb2")
    compare(rows[2].address, "0xc3")
    fuzzyCompare(rows[1].depth, 1, 0.01)
    fuzzyCompare(rows[2].depth, Math.log(3) / Math.LN2, 0.01)
    compare(rows[0].fog, 0)
    fuzzyCompare(rows[1].fog, Depth.fogForDepth(1), 0.01)
    compare(rows[0].age, "focused")
    compare(rows[1].age, "earlier", "a seeded age is not printed as measured")
    compare(rows[1].app, "Foot")
  }

  function test_seed_waits_for_the_client_list() {
    // Before Quickshell's j/clients reply lands, lastIpcObject is empty.
    const bare = [toplevel("a1", 1, 0), toplevel("b2", 1, 1)]
    for (let i = 0; i < bare.length; i++) bare[i].lastIpcObject = {}
    setUpDesktop(bare)
    const fathom = createTemporaryObject(fathomComponent, testCase)
    const ipc = FakeSystem.ipc("fathom")
    wait(100)
    compare(JSON.parse(ipc.state()).seeded, false)
    verify(Hyprland.refreshCount >= 1, "asks Quickshell to refresh the client list")
    Hyprland.toplevels = { values: [toplevel("a1", 1, 0), toplevel("b2", 1, 1)] }
    tryVerify(function() { return JSON.parse(ipc.state()).seeded === true }, 2000, "seeds once the data is there")
    const rows = JSON.parse(ipc.field())
    compare(rows[0].address, "0xa1")
    fuzzyCompare(rows[1].depth, 1, 0.01)
    verify(fathom !== null)
  }

  function test_alt_tab_opens_on_previous_window_and_release_focuses() {
    const fathom = createFathom()
    verify(FakeSystem.press("fathom", "next"))
    verify(fathom.opened)
    compare(fathom.mode, "hold")
    compare(fathom.selectedIndex, 1)
    FakeSystem.press("fathom", "next")
    compare(fathom.selectedIndex, 2)
    FakeSystem.press("fathom", "release")
    verify(!fathom.opened)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_keys_step_and_alt_release_commits() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return fathom.fieldView.activeFocus || testCase.Window.activeFocusItem !== null })
    wait(0)
    keyPress(Qt.Key_Tab)
    compare(fathom.selectedIndex, 2)
    keyPress(Qt.Key_Backtab)
    compare(fathom.selectedIndex, 1)
    keyPress(Qt.Key_Tab, Qt.ShiftModifier)
    compare(fathom.selectedIndex, 0)
    keyPress(Qt.Key_Tab)
    keyRelease(Qt.Key_Alt)
    verify(!fathom.opened)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xb2" })'], 1000)
  }

  function test_escape_closes_without_focusing() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    wait(0)
    keyPress(Qt.Key_Escape)
    verify(!fathom.opened)
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_release_twice_focuses_once() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    wait(0)
    keyRelease(Qt.Key_Alt)
    FakeSystem.press("fathom", "release")
    wait(250)
    compare(Hyprland.dispatches.length, 1)
  }

  function test_hold_needs_two_windows() {
    setUpDesktop([toplevel("a1", 1, 0)])
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    verify(!fathom.opened)
    compare(FakeSystem.ipc("fathom").open(), "ok")
    verify(fathom.opened)
    compare(fathom.mode, "browse")
  }

  function test_browse_ignores_alt_release_and_enter_commits() {
    const fathom = createFathom()
    compare(FakeSystem.ipc("fathom").open(), "ok")
    compare(fathom.selectedIndex, 0)
    FakeSystem.press("fathom", "release")
    verify(fathom.opened)
    wait(0)
    keyPress(Qt.Key_Tab)
    keyPress(Qt.Key_Return)
    verify(!fathom.opened)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xb2" })'], 1000)
  }

  function test_chord_step_arms_browse_mode() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    FakeSystem.press("fathom", "next")
    compare(fathom.mode, "hold")
    compare(fathom.selectedIndex, 1)
    FakeSystem.press("fathom", "release")
    verify(!fathom.opened)
  }

  function test_shell_summon_with_step_behaves_like_the_chord() {
    const fathom = createFathom()
    fathom.open('{"step":-1}')
    verify(fathom.opened)
    compare(fathom.mode, "hold")
    compare(fathom.selectedIndex, 2)
    fathom.close()
    verify(!fathom.opened)
    fathom.open("not json")
    compare(fathom.mode, "browse")
    fathom.close()
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_hyprlang_config_uses_focuswindow() {
    const fathom = createFathom()
    Hyprland.usingLua = false
    FakeSystem.press("fathom", "next")
    FakeSystem.press("fathom", "release")
    tryCompare(Hyprland, "dispatches", ["focuswindow address:0xb2"], 1000)
  }

  function test_grouped_window_activates_its_tab_first() {
    setUpDesktop([toplevel("a1", 1, 0), toplevel("b2", 1, 1, { grouped: ["0xa9", "0xb2"] })])
    createFathom()
    FakeSystem.press("fathom", "next")
    FakeSystem.press("fathom", "release")
    tryCompare(Hyprland, "dispatches", [
      'hl.dsp.group.active({ window = "address:0xb2", index = 2 })',
      'hl.dsp.focus({ window = "address:0xb2" })'
    ], 1000)
  }

  function test_focus_events_reorder_the_field() {
    const fathom = createFathom()
    Hyprland.rawEvent({ name: "activewindowv2", data: "c3" })
    Hyprland.rawEvent({ name: "activewindow", data: "foot,title" })
    Hyprland.rawEvent({ name: "activewindowv2", data: "" })
    const rows = JSON.parse(FakeSystem.ipc("fathom").field())
    compare(rows[0].address, "0xc3")
    compare(rows[1].address, "0xa1")
    verify(rows[1].seconds < 1, "the window that just lost focus is right behind the front")
    Hyprland.rawEvent({ name: "closewindow", data: "a1" })
    compare(JSON.parse(FakeSystem.ipc("fathom").state()).trackedWindows, 2)
  }

  function test_unusable_windows_are_left_out_and_scratchpads_kept() {
    const scratch = toplevel("b2", -98, 1)
    scratch.workspace = { id: -98, name: "special:term" }
    setUpDesktop([
      toplevel("a1", 1, 0),
      scratch,
      toplevel("c3", 1, 2, { mapped: false }),
      toplevel("d4", 1, 3, { noHandle: true }),
      toplevel("e5", 3, 4)
    ])
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    compare(fathom.field.length, 3)
    compare(fathom.field[1].address, "b2")
    compare(fathom.field[2].address, "e5")
    const labels = fathom.groups.map(group => group.label)
    compare(labels, ["1", "3", "term"])
  }

  function test_cards_recede_and_the_camera_follows() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const front = fathom.fieldView.planeAt(0)
    const middle = fathom.fieldView.planeAt(1)
    const back = fathom.fieldView.planeAt(2)
    const stage = fathom.fieldView.stage
    fuzzyCompare(front.width, stage.frontWidth, 1e-3)
    fuzzyCompare(front.opacity, 1, 1e-6)
    fuzzyCompare(middle.width, stage.frontWidth * Layout.SIZE_Q, 1e-3)
    verify(back.z < middle.z && middle.z < front.z, "front cards draw on top")
    verify(middle.x + middle.width > front.x + front.width && back.x + back.width > middle.x + middle.width,
      "every deeper card shows a band past the one in front")
    verify(middle.y < front.y && back.y < middle.y, "every deeper card shows its header above the one in front")
    verify(middle.fog > 0 && front.fog === 0, "cards behind the camera wear fog")

    // Diving to the middle window: it reaches the front, the front card flies past.
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return Math.abs(middle.width - stage.frontWidth) < 1e-3 }, 1000)
    tryVerify(function() { return front.opacity < 1e-3 }, 1000)
    verify(!front.visible, "a passed card stops drawing")
    verify(middle.selected)
    compare(middle.fog, 0)
  }

  function test_click_on_a_plane_focuses_it() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const back = fathom.fieldView.planeAt(2)
    tryVerify(function() { return back.width > 1 })
    // The sliver of the back plane that shows past the planes in front of it.
    mouseClick(back, back.width * 0.97, back.height / 2)
    tryVerify(function() { return !fathom.opened }, 1000)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_click_on_empty_space_cancels() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    mouseClick(fathom.fieldView, 10, fathom.fieldView.height - 10)
    verify(!fathom.opened)
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_captures_report_off_screen_workspaces() {
    setUpDesktop([toplevel("a1", 1, 0), toplevel("b2", 2, 1, { contentReady: false })])
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 2)
    const rows = JSON.parse(FakeSystem.ipc("fathom").captures())
    compare(rows.length, 2)
    compare(rows[0].workspaceVisible, true)
    compare(rows[0].hasContent, true)
    compare(rows[0].sourceSize, "1600x1000")
    compare(rows[1].workspaceVisible, false)
    compare(rows[1].hasContent, false)
    verify(fathom.firstContentMs >= 0, "records time to first frame")
  }

  function test_bench_measures_frames_and_closes() {
    const fathom = createFathom()
    compare(FakeSystem.ipc("fathom").bench(2), "ok")
    verify(fathom.opened)
    verify(fathom.fieldView.probe.running)
    tryVerify(function() { return !fathom.opened }, 4000, "bench closes the field")
    const stats = JSON.parse(FakeSystem.ipc("fathom").stats())
    compare(stats.windows, 3)
    verify(stats.frames !== null)
    verify(stats.frames.frames > 10, "collected frame intervals: " + JSON.stringify(stats.frames))
    compare(JSON.parse(FakeSystem.ipc("fathom").captures()).length, 3)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_probe_is_off_during_normal_use() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    verify(!fathom.fieldView.probe.running)
  }

  function test_ipc_state_reports_build_identity() {
    createFathom()
    const state = JSON.parse(FakeSystem.ipc("fathom").state())
    compare(state.buildIdentity, "0.2.0-deep")
    compare(state.opened, false)
    compare(state.usingLua, true)
    compare(state.trackedWindows, 3)
  }

  // ------------------------------------------------------------ 0.2 input

  function openHeld(fathom) {
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return fathom.fieldView.activeFocus || testCase.Window.activeFocusItem !== null })
    wait(0)
  }

  function test_arrows_dive_and_stop_at_the_ends() {
    const fathom = createFathom()
    openHeld(fathom)
    compare(fathom.selectedIndex, 1)
    keyPress(Qt.Key_Down)
    compare(fathom.selectedIndex, 2)
    keyPress(Qt.Key_Down)
    compare(fathom.selectedIndex, 2, "arrows stop at the far end")
    keyPress(Qt.Key_Up, Qt.AltModifier)
    compare(fathom.selectedIndex, 1, "with Alt held too")
    keyPress(Qt.Key_Home)
    compare(fathom.selectedIndex, 0)
    keyPress(Qt.Key_Up)
    compare(fathom.selectedIndex, 0, "and at the front")
    keyPress(Qt.Key_End)
    compare(fathom.selectedIndex, 2)
    keyPress(Qt.Key_Tab)
    compare(fathom.selectedIndex, 0, "Tab still wraps")
    keyPress(Qt.Key_PageDown)
    compare(fathom.selectedIndex, 2)
    keyRelease(Qt.Key_Alt)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_left_right_and_digits_move_between_workspaces() {
    const fathom = createFathom()
    openHeld(fathom)
    compare(fathom.selectedIndex, 1)
    keyPress(Qt.Key_Right, Qt.AltModifier)
    compare(fathom.selectedIndex, 2, "workspace 2's most recent window")
    keyPress(Qt.Key_Right)
    compare(fathom.selectedIndex, 2, "no workspace further right")
    keyPress(Qt.Key_Left)
    compare(fathom.selectedIndex, 0, "workspace 1's most recent window")
    // keyPress, not keyClick: keyClick would also release Alt, which commits.
    keyPress(Qt.Key_2, Qt.AltModifier)
    compare(fathom.selectedIndex, 2)
    keyClick(Qt.Key_1)
    compare(fathom.selectedIndex, 0)
    keyClick(Qt.Key_7)
    compare(fathom.selectedIndex, 0, "an empty workspace number changes nothing")
    verify(fathom.opened)
  }

  function test_typing_filters_and_escape_clears_first() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    wait(0)
    keyClick(Qt.Key_C)
    compare(fathom.filterText, "c")
    compare(fathom.order, [2], "only Window c3 matches")
    compare(fathom.selectedIndex, 2, "the best match is selected")
    keyClick(Qt.Key_3)
    compare(fathom.filterText, "c3", "digits join a filter being typed")
    keyClick(Qt.Key_Z)
    compare(fathom.order.length, 0)
    compare(fathom.selectedIndex, -1)
    keyPress(Qt.Key_Return)
    verify(fathom.opened, "Enter with nothing shown does nothing")
    keyPress(Qt.Key_Backspace)
    compare(fathom.filterText, "c3")
    compare(fathom.selectedIndex, 2)
    keyPress(Qt.Key_Escape)
    compare(fathom.filterText, "")
    verify(fathom.opened, "the first Escape clears the filter")
    compare(fathom.order.length, 3)
    keyPress(Qt.Key_Escape)
    verify(!fathom.opened)
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_alt_letters_filter_while_holding() {
    const fathom = createFathom()
    openHeld(fathom)
    // Alt+letter can arrive without text; the key code stands in for it.
    fathom.handleKey(Qt.Key_B, Qt.AltModifier, "")
    compare(fathom.filterText, "b")
    compare(fathom.selectedIndex, 1)
    FakeSystem.press("fathom", "release")
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xb2" })'], 1000)
  }

  function test_release_with_nothing_matching_cancels() {
    const fathom = createFathom()
    openHeld(fathom)
    fathom.setFilter("nothing like this")
    FakeSystem.press("fathom", "release")
    verify(!fathom.opened)
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_space_keeps_the_field_open_after_alt() {
    const fathom = createFathom()
    openHeld(fathom)
    keyPress(Qt.Key_Space, Qt.AltModifier)
    verify(fathom.pinned)
    compare(fathom.mode, "browse")
    FakeSystem.press("fathom", "release")
    keyRelease(Qt.Key_Alt)
    verify(fathom.opened, "releasing Alt no longer commits")
    FakeSystem.press("fathom", "next")
    compare(fathom.mode, "browse", "a chord step keeps a pinned field pinned")
    compare(fathom.selectedIndex, 2)
    keyPress(Qt.Key_Return)
    verify(!fathom.opened)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_wheel_and_touchpad_dive() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    mouseWheel(fathom.fieldView, 20, 20, 0, -120)
    compare(fathom.selectedIndex, 1, "a notch down dives one window")
    mouseWheel(fathom.fieldView, 20, 20, 0, 120)
    compare(fathom.selectedIndex, 0, "a notch up rises one")
    // Touchpad pixels add up before they step.
    fathom.wheel(0, -30, 0, 0)
    compare(fathom.selectedIndex, 0)
    fathom.wheel(0, -40, 0, 0)
    compare(fathom.selectedIndex, 1)
    // Sideways moves between workspaces.
    fathom.wheel(0, 0, -120, 0)
    compare(fathom.selectedIndex, 2)
  }

  function test_a_window_that_closes_leaves_the_field() {
    const fathom = createFathom()
    openHeld(fathom)
    compare(fathom.selectedIndex, 1)
    Hyprland.rawEvent({ name: "closewindow", data: "b2" })
    compare(fathom.order, [0, 2])
    compare(fathom.selectedIndex, 2, "the selection moves to the window behind")
    // The same when the toplevel list changes without an event.
    Hyprland.toplevels = { values: [Hyprland.toplevels.values[0], Hyprland.toplevels.values[2]] }
    verify(fathom.opened)
    FakeSystem.press("fathom", "release")
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_no_focus_request_for_a_window_gone_before_it() {
    const fathom = createFathom()
    openHeld(fathom)
    FakeSystem.press("fathom", "release")
    verify(!fathom.opened)
    // b2 closes during the short wait for the overlay to go.
    Hyprland.toplevels = { values: [Hyprland.toplevels.values[0], Hyprland.toplevels.values[2]] }
    wait(250)
    compare(Hyprland.dispatches.length, 0)
  }

  function test_quick_alt_tab_never_reveals_the_field() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    verify(fathom.opened)
    verify(!fathom.revealed, "hold mode waits before drawing")
    compare(fathom.fieldView.opacity, 0)
    FakeSystem.press("fathom", "release")
    verify(!fathom.revealed)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xb2" })'], 1000)
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return fathom.revealed }, 1000, "a held switch draws after the delay")
    FakeSystem.ipc("fathom").cancel()
    FakeSystem.ipc("fathom").open()
    verify(fathom.revealed, "browsing draws at once")
  }

  function test_map_hover_selects_only_after_the_pointer_moves() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const tile = fathom.fieldView.map.tileFor(2)
    verify(tile !== null, "workspace 2 shows window c3")
    tryVerify(function() { return tile.width > 4 })
    // The first pointer event only primes: a pointer resting there when the
    // field opened selects nothing.
    mouseMove(tile, tile.width / 2, tile.height / 2)
    compare(fathom.selectedIndex, 0)
    mouseMove(tile, tile.width / 2 + 4, tile.height / 2 + 1)
    compare(fathom.selectedIndex, 2)
    mouseClick(tile, tile.width / 2, tile.height / 2)
    tryVerify(function() { return !fathom.opened }, 1000)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xc3" })'], 1000)
  }

  function test_map_shows_every_workspace() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    compare(fathom.groups.length, 2)
    compare(fathom.groups[0].label, "1")
    compare(fathom.groups[0].entries, [0, 1])
    compare(fathom.groups[0].onScreen, true)
    compare(fathom.groups[1].entries, [2])
    compare(fathom.groups[1].onScreen, false)
    const state = JSON.parse(FakeSystem.ipc("fathom").state())
    compare(state.workspaces, 2)
    compare(state.shown, 3)
  }

  function test_focus_goes_out_as_soon_as_hyprland_restores_focus() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    FakeSystem.press("fathom", "release")
    compare(Hyprland.dispatches.length, 0, "not while the grab may still be in place")
    // An empty address (a layer took focus) is not the restore.
    Hyprland.rawEvent({ name: "activewindowv2", data: "" })
    compare(Hyprland.dispatches.length, 0)
    Hyprland.rawEvent({ name: "activewindowv2", data: "a1" })
    compare(Hyprland.dispatches, ['hl.dsp.focus({ window = "address:0xb2" })'], "right on the restore")
    wait(250)
    compare(Hyprland.dispatches.length, 1, "and only once")
  }

  function test_caption_click_focuses_and_the_filter_pill_is_not_empty_space() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    keyClick(Qt.Key_B)
    compare(fathom.selectedIndex, 1)
    const view = fathom.fieldView
    // The filter pill sits at the top left.
    mouseClick(view, view.margin + 10, view.margin + 10)
    verify(fathom.opened, "a click on the filter pill keeps the field open")
    // The caption sits just above the map, at the front card's left edge.
    const captionY = view.height - view.margin - view.mapHeight - view.captionHeight / 2 - 14 * view.unit
    mouseClick(view, view.stage.frontX - view.stage.frontWidth / 2 + 60, captionY)
    tryVerify(function() { return !fathom.opened }, 1000)
    tryCompare(Hyprland, "dispatches", ['hl.dsp.focus({ window = "address:0xb2" })'], 1000)
  }

  function test_a_window_that_stops_delivering_frames_shows_its_last_snapshot() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    tryVerify(function() { return JSON.parse(FakeSystem.ipc("fathom").state()).snapshots === 3 }, 3000,
      "every card with a frame keeps a snapshot")
    FakeSystem.ipc("fathom").cancel()

    // b2 is now parked beside the screen: no frames any more.
    const parked = toplevel("b2", 1, 1, { contentReady: false })
    parked.lastIpcObject.at = [5000, 0]
    Hyprland.toplevels = { values: [Hyprland.toplevels.values[0], parked, Hyprland.toplevels.values[2]] }
    Hyprland.monitors = { values: [{ name: "eDP-1", x: 0, y: 0, width: 1600, height: 1000, scale: 1, activeWorkspace: { id: 1 } }] }
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const card = fathom.fieldView.planeAt(1)
    verify(!card.hasContent)
    verify(card.parked, "the card knows why no frame comes")
    verify(card.showsSnapshot, "it shows the last frame seen instead")
    const rows = JSON.parse(FakeSystem.ipc("fathom").captures())
    compare(rows[1].snapshot, true)
    compare(rows[1].parked, true)
    FakeSystem.ipc("fathom").cancel()

    // A snapshot leaves with its window.
    Hyprland.rawEvent({ name: "closewindow", data: "b2" })
    compare(JSON.parse(FakeSystem.ipc("fathom").state()).snapshots, 2)
  }

  function test_the_sounding_line_picks_by_depth_and_the_lead_follows() {
    FakeSystem.surfaceWidth = 1200
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const gauge = fathom.fieldView.gauge
    verify(gauge.visible, "shown on a screen wide enough")
    compare(gauge.marks.length, 3)
    // c3 sits log2(3) fathoms down (seeded two steps back).
    const y = Layout.soundingY(Math.log(3) / Math.LN2, gauge.lineTop, gauge.lineBottom)
    mouseClick(gauge, gauge.lineX + 12, y)
    compare(fathom.selectedIndex, 2)
    tryVerify(function() { return Math.abs(gauge.leadDepth - fathom.field[2].depth) < 1e-3 }, 1000,
      "the lead goes down to the selection")
    // Dragging back up to the surface.
    mousePress(gauge, gauge.lineX + 12, y)
    mouseMove(gauge, gauge.lineX + 12, gauge.lineTop)
    mouseRelease(gauge, gauge.lineX + 12, gauge.lineTop)
    compare(fathom.selectedIndex, 0)
    verify(fathom.opened)
  }

  function test_space_separates_filter_words_while_holding() {
    const fathom = createFathom()
    openHeld(fathom)
    fathom.handleKey(Qt.Key_W, Qt.AltModifier, "")
    keyPress(Qt.Key_Space, Qt.AltModifier)
    compare(fathom.filterText, "w ", "a space between words, not a pin")
    verify(!fathom.pinned)
    fathom.handleKey(Qt.Key_C, Qt.AltModifier, "")
    compare(fathom.order, [2], "both words must match: Window c3")
    fathom.setFilter("")
    keyPress(Qt.Key_Space, Qt.AltModifier)
    verify(fathom.pinned, "with no filter, Space keeps the field open")
  }

  function test_clicks_before_the_field_is_drawn_do_nothing() {
    const fathom = createFathom()
    FakeSystem.press("fathom", "next")
    verify(!fathom.revealed)
    mouseClick(fathom.fieldView, 10, fathom.fieldView.height - 10)
    verify(fathom.opened, "an invisible dismiss area does not cancel")
    tryVerify(function() { return fathom.revealed }, 1000)
    mouseClick(fathom.fieldView, 10, fathom.fieldView.height - 10)
    verify(!fathom.opened, "once drawn, it does")
  }

  function test_fresh_snapshots_are_kept_and_gone_windows_lose_theirs() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return Object.keys(fathom.snapshots).length === 3 }, 3000)
    const first = fathom.snapshots["b2"].takenAt
    FakeSystem.ipc("fathom").cancel()
    FakeSystem.ipc("fathom").open()
    wait(700)
    compare(fathom.snapshots["b2"].takenAt, first, "a fresh snapshot is not taken again")
    FakeSystem.ipc("fathom").cancel()
    // b2 goes without a closewindow event.
    Hyprland.toplevels = { values: [Hyprland.toplevels.values[0], Hyprland.toplevels.values[2]] }
    verify(!("b2" in fathom.snapshots))
    compare(Object.keys(fathom.snapshots).length, 2)
  }

  // The map shows the frame a card kept, at no capture of its own; a window
  // never seen keeps its icon.
  function test_map_tiles_show_the_last_frame_seen() {
    setUpDesktop([toplevel("a1", 1, 0), toplevel("b2", 1, 1), toplevel("c3", 2, 2), toplevel("d4", 2, 3, { contentReady: false })])
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return Object.keys(fathom.snapshots).length === 3 }, 3000)
    const seen = fathom.fieldView.map.tileFor(1)
    tryVerify(function() { return seen.showsFrame }, 1000, "a seen window shows its last frame")
    compare(seen.snapshot.url, fathom.snapshots["b2"].url, "the frame its card kept")
    const unseen = fathom.fieldView.map.tileFor(3)
    verify(unseen.snapshot === null)
    verify(!unseen.showsFrame, "a window never seen shows its icon")
  }

  // Omarchy switches themes live: the open field re-colors, down to every
  // card, the gauge and the map.
  function test_the_field_follows_a_light_theme() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    const view = fathom.fieldView
    verify(!view.theme.light, "the stub palette is dark")
    try {
      Color.foreground = "#575279"
      Color.background = "#faf4ed"
      Color.accent = "#56949f"
      Color.urgent = "#b4637a"
      verify(view.theme.light, "rose-pine is light")
      compare(view.theme.text, "#575279")
      verify(view.theme.textSoft !== "#cecacd", "its pale muted color is not text")
      verify(view.planeAt(0).theme.light, "the cards follow")
      verify(view.gauge.theme.light, "the gauge follows")
      verify(view.map.theme.light, "the map follows")
    } finally {
      Color.foreground = "#ccd0cf"
      Color.background = "#171717"
      Color.accent = "#f25623"
      Color.urgent = "#e0463a"
    }
    verify(!view.theme.light)
  }
}
