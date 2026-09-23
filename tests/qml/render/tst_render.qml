// Renders the field offscreen for design review: the real controller and
// view against the stub Quickshell modules, with a realistic desktop (seven
// workspaces, a scrolling layout that parks windows beside the screen, a
// floating window, a tab group, a scratchpad, an urgent window and one that
// cannot be captured), over a blurred stand-in desktop, in dark and light
// Omarchy themes (and each over the other's desktop). Run with
// `bash tests/qml/render.sh`; PNGs land in screenshots-local/. Not part of
// bin/test.

import QtQuick
import QtTest
import FathomTest
import Quickshell.Hyprland
import qs.Commons
import "../src"

TestCase {
  id: testCase

  name: "Render"
  when: windowShown
  visible: true
  width: 800
  height: 600

  readonly property string outDir: "@OUT@"

  // Omarchy themes as the shell reads them (colors.toml): the stub's own
  // dark palette, two shipped dark themes and the four shipped light ones.
  readonly property var themes: ({
    "default": ["#ccd0cf", "#171717", "#f25623", "#e0463a"],
    "solitude": ["#cacccc", "#101315", "#798186", "#565d60"],
    "tokyo-night": ["#a9b1d6", "#1a1b26", "#7aa2f7", "#f7768e"],
    "rose-pine": ["#575279", "#faf4ed", "#56949f", "#b4637a"],
    "catppuccin-latte": ["#4c4f69", "#eff1f5", "#1e66f5", "#d20f39"],
    "flexoki-light": ["#100f0f", "#fffcf0", "#205ea6", "#d14d41"],
    "white": ["#000000", "#ffffff", "#6e6e6e", "#2a2a2a"],
    // A catppuccin variant on pure black, as used on the machine this was
    // designed on.
    "catppuccin-black": ["#cdd6f4", "#010101", "#89b4fa", "#f38ba8"]
  })
  // What sits behind the field, and whether apps that follow the theme are
  // light: set by useTheme for the next desktop.
  property string backdrop: "dark"
  property bool lightApps: false

  function useTheme(name, backdrop) {
    const colors = testCase.themes[name]
    Color.foreground = colors[0]
    Color.background = colors[1]
    Color.accent = colors[2]
    Color.urgent = colors[3]
    const light = name !== "default" && ["rose-pine", "catppuccin-latte", "flexoki-light", "white"].indexOf(name) !== -1
    testCase.lightApps = light
    testCase.backdrop = backdrop || (light ? "light" : "dark")
  }

  Component {
    id: fathomComponent

    Fathom {}
  }

  // [appId, title, workspace id, workspace name, x, y, width, height, color, extra]
  // `extra.light` is the app's color under a light theme; apps without one
  // (games, Spotify, Steam) stay dark either way.
  readonly property var desktop: [
    ["com.anthropic.Claude", "Claude — Fathom redesign", 1, "1", 0, 28, 1596, 970, "#2b2622", { light: "#f7f4ee" }],
    ["brave-browser", "Omarchy plugin marketplace — Brave", 1, "1", 1604, 28, 794, 970, "#1d2a3a", { light: "#ffffff" }],
    ["dev.zed.Zed", "Fathom.qml — fathom", 2, "2", 2, 28, 1596, 970, "#1f2230", { light: "#fafafa" }],
    ["Alacritty", "~/Projects/plugins/fathom", 2, "2", 980, 520, 560, 420, "#141414", { floating: true, light: "#f4f1ec" }],
    ["chatgpt", "ChatGPT", 1, "1", 2402, 28, 794, 970, "#202123", { light: "#ffffff" }],
    ["obsidian", "Phase 1 notes — Obsidian", 3, "3", 2, 28, 794, 970, "#262335", { light: "#f6f5fb" }],
    ["Alacritty", "btop", 3, "3", 804, 28, 794, 970, "#0f1a14", { light: "#f4f1ec" }],
    ["Slack", "#omarchy — Slack", 4, "4", 2, 28, 1596, 970, "#3f0e40", { group: "g1", urgent: true, light: "#fbf8fb" }],
    ["spotify", "Spotify Premium", 4, "4", 2, 28, 1596, 970, "#121212", { group: "g1" }],
    ["steam", "Steam", 7, "7", 420, 180, 1100, 700, "#1b2838", { floating: true }],
    ["org.gnome.Nautilus", "Downloads", 5, "5", 2, 28, 1596, 970, "#242424", { noContent: true, light: "#fafafa" }],
    ["Alacritty", "scratch", -98, "special:scratchpad", 250, 150, 1100, 700, "#101010", { floating: true, light: "#f4f1ec" }],
    ["firefox", "MDN Web Docs — Firefox", 5, "5", 804, 28, 794, 970, "#1c1b22", { light: "#ffffff" }],
    ["signal", "Signal", 6, "6", 2, 28, 794, 970, "#1b1c1f", { light: "#f9f9f9" }],
    ["thunderbird", "Inbox — Thunderbird", 6, "6", 804, 28, 794, 970, "#1f2a36", { light: "#fbfbfd" }]
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
        color: testCase.lightApps && extra.light ? extra.light : row[8]
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
    ["com.anthropic.Claude", "Claude", 1, "1", 2501, 28, 1590, 970, "#2b2622", { light: "#f7f4ee" }],
    ["chatgpt", "ChatGPT", 1, "1", 903, 28, 1590, 970, "#202123", { noContent: true, light: "#ffffff" }],
    ["steam", "Steam", 2, "2", 2746, 163, 1100, 700, "#1b2838", { floating: true }],
    ["dev.zed.Zed", "fathom \u2014 Fathom.qml", 1, "1", 4099, 28, 1593, 970, "#1f2230", { noContent: true, light: "#fafafa" }]
  ]

  function setUpDesktop(count, screenWidth, screenHeight, rows, monitorX) {
    FakeSystem.reset()
    FakeSystem.surfaceWidth = screenWidth
    FakeSystem.surfaceHeight = screenHeight
    FakeSystem.backdrop = testCase.backdrop
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

  function render(name, fathom, settleMs) {
    wait(settleMs === undefined ? 450 : settleMs)
    // The surface: the field and the desktop behind it.
    const item = fathom.fieldView.parent
    let saved = false
    item.grabToImage(function(result) {
      saved = result.saveToFile(testCase.outDir + "/" + name + ".png")
    })
    tryVerify(function() { return saved }, 3000, "saved " + name)
  }

  function init() {
    useTheme("default")
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

  // ChatGPT was on screen at an earlier switch, then the scrolling layout
  // parked it: its card shows the frame it kept, marked as such. Brave was
  // never seen: its card says why there is no preview.
  function test_10_snapshot() {
    const live = testCase.scrolling.map(row => [row[0], row[1], row[2], row[3], 2496, 28, row[6], row[7], row[8],
      row[0] === "brave-origin" ? { noContent: true } : {}])
    let fathom = open(6, 1600, 1000, "browse", live, 2496)
    wait(700)
    FakeSystem.ipc("fathom").cancel()
    const parked = []
    for (let i = 0; i < 6; i++) parked.push(toplevel(testCase.scrolling[i], i))
    Hyprland.toplevels = { values: parked }
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    fathom.jumpTo(3)
    render("10-snapshot", fathom)
    fathom.jumpTo(1)
    render("11-never-seen", fathom)
  }

  function test_8_forty_windows() {
    const fathom = open(40, 1920, 1080, "hold")
    render("08-forty-windows", fathom)
  }

  // Every theme on the layout of the machine this was designed on, one step
  // into the Deep, and fifteen windows five steps down.
  function test_theme_data() {
    return Object.keys(testCase.themes).filter(name => name !== "default").map(name => ({ tag: name, theme: name }))
  }

  function test_theme(data) {
    useTheme(data.theme)
    let fathom = open(6, 1600, 1000, "hold", testCase.scrolling, 2496)
    FakeSystem.press("fathom", "next")
    render("theme-" + data.theme + "-scrolling", fathom)
    FakeSystem.ipc("fathom").cancel()
    fathom = open(15, 1600, 1000, "hold")
    for (let i = 0; i < 4; i++) FakeSystem.press("fathom", "next")
    render("theme-" + data.theme + "-deep", fathom)
  }

  // A theme over the other kind of desktop: a dark theme over bright pages,
  // a light theme over a dark game.
  function test_theme_crossed_data() {
    return [{ tag: "solitude", theme: "solitude", backdrop: "light" }, { tag: "rose-pine", theme: "rose-pine", backdrop: "dark" }]
  }

  function test_theme_crossed(data) {
    useTheme(data.theme, data.backdrop)
    const fathom = open(15, 1600, 1000, "browse")
    fathom.setFilter("ala")
    render("crossed-" + data.theme + "-on-" + data.backdrop, fathom)
  }

  // The still frame and the never-seen card under a light theme.
  function test_theme_snapshot() {
    useTheme("rose-pine")
    const live = testCase.scrolling.map(row => [row[0], row[1], row[2], row[3], 2496, 28, row[6], row[7], row[8],
      row[0] === "brave-origin" ? { noContent: true } : { light: row[9].light }])
    let fathom = open(6, 1600, 1000, "browse", live, 2496)
    wait(700)
    FakeSystem.ipc("fathom").cancel()
    const parked = []
    for (let i = 0; i < 6; i++) parked.push(toplevel(testCase.scrolling[i], i))
    Hyprland.toplevels = { values: parked }
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    fathom.jumpTo(3)
    render("theme-rose-pine-snapshot", fathom)
  }

  // After a while in use: the map shows the frames the cards kept, with
  // titles where the tiles have room. Two workspaces, as on the machine
  // this was designed on, and ten windows over seven.
  function test_map_frames_data() {
    return [
      { tag: "default-two", theme: "default", count: 3, rows: "pair" },
      { tag: "rose-pine-two", theme: "rose-pine", count: 3, rows: "pair" },
      { tag: "default-ten", theme: "default", count: 10 },
      { tag: "rose-pine-ten", theme: "rose-pine", count: 10 }
    ]
  }

  function test_map_frames(data) {
    useTheme(data.theme)
    const pair = [
      ["com.anthropic.Claude", "Claude — Fathom light theme", 1, "1", 0, 28, 1596, 970, "#2b2622", { light: "#f7f4ee" }],
      ["brave-origin", "Startpagina / X - Brave Origin", 2, "2", 0, 28, 1596, 970, "#101010", {}],
      ["dev.zed.Zed", "Palette.js — fathom", 1, "1", 0, 28, 1596, 970, "#1f2230", { light: "#fafafa" }]
    ]
    const fathom = open(data.count, 1600, 1000, "browse", data.rows === "pair" ? pair : undefined)
    for (let i = 1; i < data.count; i++) {
      fathom.jumpTo(i)
      wait(450)
    }
    FakeSystem.ipc("fathom").cancel()
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    fathom.jumpTo(1)
    render("12-map-frames-" + data.tag, fathom)
  }

  // Two windows on two workspaces, opened to browse: the first look (before
  // any frame is kept) and every look after it.
  function test_two_windows_data() {
    return [{ tag: "catppuccin-latte", theme: "catppuccin-latte" }, { tag: "catppuccin-black", theme: "catppuccin-black" }]
  }

  function test_two_windows(data) {
    useTheme(data.theme)
    const rows = [
      ["brave-origin", "tcballard/omarchy-task-manager - Brave Origin", 2, "2", 0, 28, 1596, 970, "#0d1117", {}],
      ["com.anthropic.Claude", "Claude", 1, "1", 0, 28, 1596, 970, "#2b2622", { light: "#f7f4ee" }]
    ]
    let fathom = open(2, 1600, 1000, "browse", rows)
    render("13-two-windows-" + data.theme + "-first", fathom, 150)
    wait(600)
    FakeSystem.ipc("fathom").cancel()
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    render("13-two-windows-" + data.theme + "-after", fathom)
  }
}
