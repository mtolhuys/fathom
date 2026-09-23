// Renders the field offscreen for design review: the real controller and
// view against the stub Quickshell modules, with a realistic desktop (seven
// workspaces, a scrolling layout that parks windows beside the screen, a
// floating window, a tab group, a scratchpad, an urgent window and one that
// cannot be captured). Run with `bash tests/qml/render.sh`; PNGs land in
// screenshots-local/. Not part of bin/test.

import QtQuick
import QtTest
import FathomTest
import Quickshell.Hyprland
import "../src"

TestCase {
  id: testCase

  name: "Render"
  when: windowShown
  visible: true
  width: 800
  height: 600

  readonly property string outDir: "@OUT@"

  Component {
    id: fathomComponent

    Fathom {}
  }

  // [appId, title, workspace id, workspace name, x, y, width, height, color, extra]
  readonly property var desktop: [
    ["com.anthropic.Claude", "Claude — Fathom redesign", 1, "1", 0, 28, 1596, 970, "#2b2622", {}],
    ["brave-browser", "Omarchy plugin marketplace — Brave", 1, "1", 1604, 28, 794, 970, "#1d2a3a", {}],
    ["dev.zed.Zed", "Fathom.qml — fathom", 2, "2", 2, 28, 1596, 970, "#1f2230", {}],
    ["Alacritty", "~/Projects/plugins/fathom", 2, "2", 980, 520, 560, 420, "#141414", { floating: true }],
    ["chatgpt", "ChatGPT", 1, "1", 2402, 28, 794, 970, "#202123", {}],
    ["obsidian", "Phase 1 notes — Obsidian", 3, "3", 2, 28, 794, 970, "#262335", {}],
    ["Alacritty", "btop", 3, "3", 804, 28, 794, 970, "#0f1a14", {}],
    ["Slack", "#omarchy — Slack", 4, "4", 2, 28, 1596, 970, "#3f0e40", { group: "g1", urgent: true }],
    ["spotify", "Spotify Premium", 4, "4", 2, 28, 1596, 970, "#121212", { group: "g1" }],
    ["steam", "Steam", 7, "7", 420, 180, 1100, 700, "#1b2838", { floating: true }],
    ["org.gnome.Nautilus", "Downloads", 5, "5", 2, 28, 1596, 970, "#242424", { noContent: true }],
    ["Alacritty", "scratch", -98, "special:scratchpad", 250, 150, 1100, 700, "#101010", { floating: true }],
    ["firefox", "MDN Web Docs — Firefox", 5, "5", 804, 28, 794, 970, "#1c1b22", {}],
    ["signal", "Signal", 6, "6", 2, 28, 794, 970, "#1b1c1f", {}],
    ["thunderbird", "Inbox — Thunderbird", 6, "6", 804, 28, 794, 970, "#1f2a36", {}]
  ]

  function toplevel(row, history) {
    const extra = row[9] || {}
    const address = "a" + (history + 1).toString(16) + "0f"
    return {
      address: address,
      title: row[1],
      workspace: { id: row[2], name: row[3] },
      monitor: { name: "eDP-1" },
      urgent: !!extra.urgent,
      wayland: {
        appId: row[0],
        contentReady: !extra.noContent,
        width: row[6] * 1.6,
        height: row[7] * 1.6,
        color: row[8]
      },
      lastIpcObject: {
        mapped: true,
        focusHistoryID: history,
        "class": row[0],
        at: [row[4], row[5]],
        size: [row[6], row[7]],
        floating: !!extra.floating,
        fullscreen: 0,
        grouped: []
      }
    }
  }

  // The layout of the machine this was designed on: the monitor sits at
  // x = 2496, workspace 1 is a scrolling layout with windows parked to both
  // sides, workspace 2 holds a fullscreen game and a floating launcher.
  readonly property var scrolling: [
    ["steam_app_4358690", "Graveyard Keeper 2", 2, "2", 2496, 0, 1600, 1000, "#3a2a1a", {}],
    ["brave-origin", "Netflix - Brave Origin", 1, "1", -698, 28, 1593, 970, "#141414", { noContent: true }],
    ["com.anthropic.Claude", "Claude", 1, "1", 2501, 28, 1590, 970, "#2b2622", {}],
    ["chatgpt", "ChatGPT", 1, "1", 903, 28, 1590, 970, "#202123", { noContent: true }],
    ["steam", "Steam", 2, "2", 2746, 163, 1100, 700, "#1b2838", { floating: true }],
    ["dev.zed.Zed", "fathom \u2014 Fathom.qml", 1, "1", 4099, 28, 1593, 970, "#1f2230", { noContent: true }]
  ]

  function setUpDesktop(count, screenWidth, screenHeight, rows, monitorX) {
    FakeSystem.reset()
    FakeSystem.surfaceWidth = screenWidth
    FakeSystem.surfaceHeight = screenHeight
    const source = rows || testCase.desktop
    const values = []
    for (let i = 0; i < count; i++) values.push(toplevel(source[i % source.length], i))
    // Tab groups list their members' addresses.
    const members = []
    for (let j = 0; j < values.length; j++) {
      const extra = source[j % source.length][9] || {}
      if (extra.group) members.push(values[j].address)
    }
    for (let k = 0; k < values.length; k++) {
      const extra = source[k % source.length][9] || {}
      if (extra.group) values[k].lastIpcObject.grouped = members.slice()
    }
    Hyprland.usingLua = true
    Hyprland.toplevels = { values: values }
    Hyprland.activeToplevel = values[0]
    Hyprland.focusedMonitor = { name: "eDP-1" }
    Hyprland.monitors = { values: [{
      name: "eDP-1", id: 0, x: monitorX || 0, y: 0, width: screenWidth * 1.6, height: screenHeight * 1.6, scale: 1.6,
      focused: true, activeWorkspace: rows ? { id: 2, name: "2" } : { id: 1, name: "1" }, lastIpcObject: {}
    }] }
    Hyprland.dispatches = []
  }

  function render(name, fathom) {
    wait(450)
    const item = fathom.fieldView
    let saved = false
    item.grabToImage(function(result) {
      saved = result.saveToFile(testCase.outDir + "/" + name + ".png")
    })
    tryVerify(function() { return saved }, 3000, "saved " + name)
  }

  function open(count, width, height, mode, rows, monitorX) {
    setUpDesktop(count, width, height, rows, monitorX)
    const fathom = createTemporaryObject(fathomComponent, testCase)
    tryVerify(function() { return JSON.parse(FakeSystem.ipc("fathom").state()).seeded === true }, 2000)
    if (mode === "hold") FakeSystem.press("fathom", "next")
    else FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    return fathom
  }

  function test_1_three_windows() {
    const fathom = open(3, 1600, 1000, "hold")
    render("01-three-windows", fathom)
  }

  function test_2_ten_windows() {
    const fathom = open(10, 1600, 1000, "hold")
    render("02-ten-windows", fathom)
  }

  function test_3_fifteen_windows_deep() {
    const fathom = open(15, 1600, 1000, "hold")
    for (let i = 0; i < 4; i++) FakeSystem.press("fathom", "next")
    render("03-fifteen-deep", fathom)
  }

  function test_4_filter() {
    const fathom = open(15, 1600, 1000, "browse")
    fathom.setFilter("ala")
    render("04-filter", fathom)
  }

  function test_5_no_match() {
    const fathom = open(15, 1600, 1000, "browse")
    fathom.setFilter("xyz")
    render("05-no-match", fathom)
  }

  function test_6_placeholder_selected() {
    const fathom = open(15, 1600, 1000, "hold")
    fathom.jumpTo(10)
    render("06-placeholder", fathom)
  }

  function test_7_small_screen() {
    const fathom = open(15, 1366, 768, "hold")
    FakeSystem.press("fathom", "next")
    render("07-small-screen", fathom)
  }

  function test_9_scrolling_layout() {
    const fathom = open(6, 1600, 1000, "hold", testCase.scrolling, 2496)
    render("09-scrolling-layout", fathom)
  }

  function test_8_forty_windows() {
    const fathom = open(40, 1920, 1080, "hold")
    render("08-forty-windows", fathom)
  }
}
