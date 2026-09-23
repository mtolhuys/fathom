// Offscreen tests for the real Fathom controller, field view, planes, frame
// probe and recency tracker, against stub Quickshell modules (tests/qml/stubs).
// tests/qml/run.sh copies src/ next to this file with FieldSurface.qml swapped
// for the plain-item host, then runs qmltestrunner.

import QtQuick
import QtTest
import FathomTest
import Quickshell.Hyprland
import "../src"
import "../src/Depth.js" as Depth

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
    compare(rows[0].scale, 1)
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

  function test_unusable_windows_are_left_out() {
    setUpDesktop([
      toplevel("a1", 1, 0),
      toplevel("b2", -98, 1),
      toplevel("c3", 1, 2, { mapped: false }),
      toplevel("d4", 1, 3, { noHandle: true }),
      toplevel("e5", 3, 4)
    ])
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    compare(fathom.field.length, 2)
    compare(fathom.field[1].address, "e5")
  }

  function test_planes_apply_depth_to_scale_and_opacity() {
    const fathom = createFathom()
    FakeSystem.ipc("fathom").open()
    tryCompare(fathom.fieldView, "planeCount", 3)
    const front = fathom.fieldView.planeAt(0)
    const middle = fathom.fieldView.planeAt(1)
    const back = fathom.fieldView.planeAt(2)
    fuzzyCompare(front.scale, 1, 1e-6)
    fuzzyCompare(front.opacity, 1, 1e-6)
    fuzzyCompare(middle.scale, Depth.scaleForDepth(1), 1e-3)
    fuzzyCompare(middle.opacity, Depth.opacityForDepth(1), 1e-3)
    fuzzyCompare(back.scale, Depth.scaleForDepth(Math.log(3) / Math.LN2), 1e-3)
    verify(back.z < middle.z && middle.z < front.z, "front planes draw on top")
    verify(middle.x + middle.width / 2 > front.x + front.width / 2, "deeper planes recede to the right")
    verify(middle.y + middle.height / 2 < front.y + front.height / 2, "deeper planes recede upward")
    const frontRight = front.x + front.width / 2 + front.width * front.scale / 2
    const middleRight = middle.x + middle.width / 2 + middle.width * middle.scale / 2
    const backRight = back.x + back.width / 2 + back.width * back.scale / 2
    verify(middleRight > frontRight && backRight > middleRight, "every deeper plane shows past the one in front")

    // Diving to the middle window: it reaches full size, the front one fades out.
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return Math.abs(middle.scale - 1) < 1e-3 }, 1000)
    tryVerify(function() { return front.opacity < 1e-3 }, 1000)
    verify(!front.visible, "a passed plane stops drawing")
    fuzzyCompare(back.scale, Depth.scaleForDepth(Math.log(3) / Math.LN2 - 1), 1e-3)
    verify(middle.selected)
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
    compare(state.buildIdentity, "0.1.0-phase0")
    compare(state.opened, false)
    compare(state.usingLua, true)
    compare(state.trackedWindows, 3)
  }
}
