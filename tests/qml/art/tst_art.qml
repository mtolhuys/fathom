// The artwork's raw material, rendered offscreen from the real controller
// and view (bin/make-art composes it): a sharp stand-in desktop per theme,
// the field over a transparent background for the marketplace preview and
// the banner, and the frames of the demo GIF. Twelve illustrated apps on
// seven workspaces and a scratchpad, with real focus ages. Frame names carry
// how much of the desktop behind is blurred (`b000` sharp to `b100`) and
// which desktop it is. Not part of bin/test.

import QtQuick
import QtTest
import FathomTest
import Quickshell.Hyprland
import qs.Commons
import "../src"

TestCase {
  id: art

  name: "Art"
  when: windowShown
  visible: true
  width: 800
  height: 600

  readonly property string outDir: "@OUT@"
  readonly property string icons: "/usr/share/icons/Yaru/256x256"
  readonly property int screenWidth: 1920
  readonly property int screenHeight: 1080

  // Omarchy's default theme and a light one, for the field (Color) and for
  // the apps that follow the theme (MockApp).
  readonly property var themes: ({
    "tokyo-night": {
      colors: ["#a9b1d6", "#1a1b26", "#7aa2f7", "#f7768e"],
      apps: { dark: true, bg: "#1a1b26", surface: "#16161e", raised: "#24283b", fg: "#c0caf5", dim: "#565f89", faint: "#2f3549",
        accent: "#7aa2f7", colors: ["#7aa2f7", "#bb9af7", "#9ece6a", "#7dcfff", "#ff9e64", "#f7768e", "#e0af68"] },
      wallpaper: ["#1f2335", "#11121a"], glow: "#7aa2f7", border: "#7aa2f7", inactive: "#3b4261"
    },
    "rose-pine": {
      colors: ["#575279", "#faf4ed", "#56949f", "#b4637a"],
      apps: { dark: false, bg: "#faf4ed", surface: "#f2e9e1", raised: "#fffaf3", fg: "#575279", dim: "#9893a5", faint: "#dfdad9",
        accent: "#286983", colors: ["#286983", "#907aa9", "#56949f", "#d7827e", "#ea9d34", "#b4637a", "#ea9d34"] },
      wallpaper: ["#f4ede8", "#e8dcd3"], glow: "#d7827e", border: "#56949f", inactive: "#dfdad9"
    },
    "gruvbox": {
      colors: ["#d4be98", "#282828", "#7daea3", "#ea6962"],
      apps: { dark: true, bg: "#282828", surface: "#1d2021", raised: "#32302f", fg: "#d4be98", dim: "#7c6f64", faint: "#45403d",
        accent: "#7daea3", colors: ["#7daea3", "#d3869b", "#a9b665", "#89b482", "#e78a4e", "#ea6962", "#d8a657"] },
      wallpaper: ["#32302f", "#1d2021"], glow: "#d8a657", border: "#7daea3", inactive: "#45403d"
    },
    "catppuccin-latte": {
      colors: ["#4c4f69", "#eff1f5", "#1e66f5", "#d20f39"],
      apps: { dark: false, bg: "#eff1f5", surface: "#e6e9ef", raised: "#ffffff", fg: "#4c4f69", dim: "#8c8fa1", faint: "#ccd0da",
        accent: "#1e66f5", colors: ["#1e66f5", "#8839ef", "#40a02b", "#179299", "#fe640b", "#d20f39", "#df8e1d"] },
      wallpaper: ["#eff1f5", "#dce0e8"], glow: "#8839ef", border: "#1e66f5", inactive: "#ccd0da"
    }
  })
  property string theme: "tokyo-night"

  // [appId, app name, icon, kind]
  readonly property var apps: ({
    editor: ["dev.fathom.Editor", "Editor", "apps/org.gnome.Builder.png", "code"],
    browser: ["dev.fathom.Browser", "Browser", "apps/web-browser.png", "browser"],
    terminal: ["dev.fathom.Terminal", "Terminal", "apps/utilities-terminal.png", "terminal"],
    music: ["dev.fathom.Music", "Music", "apps/org.gnome.Music.png", "music"],
    chat: ["dev.fathom.Chat", "Chat", "apps/internet-chat.png", "chat"],
    notes: ["dev.fathom.Notes", "Notes", "apps/text-editor.png", "notes"],
    monitor: ["dev.fathom.Monitor", "System Monitor", "apps/utilities-system-monitor.png", "monitor"],
    photos: ["dev.fathom.Photos", "Photos", "apps/org.gnome.Photos.png", "photos"],
    mail: ["dev.fathom.Mail", "Mail", "apps/internet-mail.png", "mail"],
    game: ["dev.fathom.Game", "Starfall", "categories/applications-games.png", "game"],
    files: ["dev.fathom.Files", "Files", "apps/org.gnome.Nautilus.png", "files"],
    calendar: ["dev.fathom.Calendar", "Calendar", "apps/org.gnome.Calendar.png", "calendar"]
  })

  // Most recent first: [app, title, workspace id, workspace name, x, y, width, height, seconds ago, extra]
  readonly property var windows: [
    ["editor", "Palette.js — fathom", 1, "1", 10, 38, 1130, 1032, 0, {}],
    ["browser", "Omarchy — The Manual", 2, "2", 10, 38, 1130, 1032, 40, {}],
    ["terminal", "~/Projects/fathom", 1, "1", 1150, 38, 760, 1032, 150, {}],
    ["music", "Now Playing — Low Tide", 3, "3", 10, 38, 1900, 1032, 380, {}],
    ["chat", "#design — 3 new", 4, "4", 10, 38, 1130, 1032, 720, {}],
    ["notes", "Release notes", 2, "2", 1150, 38, 760, 1032, 1500, {}],
    ["monitor", "btop", -98, "special:scratchpad", 260, 150, 1400, 780, 2880, { floating: true }],
    ["photos", "Iceland, 2026", 5, "5", 10, 38, 1130, 1032, 4800, {}],
    ["mail", "Inbox — 2 unread", 4, "4", 1150, 38, 760, 1032, 7200, {}],
    ["game", "Starfall", 6, "6", 0, 0, 1920, 1080, 10800, { fullscreen: true }],
    ["files", "Pictures", 5, "5", 1150, 38, 760, 1032, 18000, {}],
    ["calendar", "September", 7, "7", 10, 38, 1900, 1032, 86400, {}]
  ]

  Component {
    id: fathomComponent

    Fathom {}
  }

  // A sharp desktop: wallpaper, Omarchy's bar and two tiled windows.
  Component {
    id: desktopComponent

    Item {
      id: desktop

      property var leftWindow: []
      property var rightWindow: []
      readonly property var look: art.themes[art.theme]

      width: art.screenWidth
      height: art.screenHeight

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: desktop.look.wallpaper[0] }
          GradientStop { position: 1; color: desktop.look.wallpaper[1] }
        }
      }

      Rectangle {
        x: parent.width * 0.55
        y: parent.height * 0.3
        width: parent.width * 0.5
        height: width
        radius: width / 2
        color: desktop.look.glow
        opacity: 0.12
      }

      Rectangle {
        width: parent.width
        height: 28
        color: desktop.look.apps.bg

        Row {
          x: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14

          Repeater {
            model: 7

            delegate: Text {
              required property int index
              text: String(index + 1)
              color: index === 0 ? desktop.look.apps.fg : desktop.look.apps.dim
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: 13
              font.bold: index === 0
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: "Wednesday 14:32"
          color: desktop.look.apps.fg
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 13
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12

          Repeater {
            model: 4

            delegate: Rectangle {
              width: 10
              height: 10
              radius: 5
              color: desktop.look.apps.dim
            }
          }
        }
      }

      Repeater {
        model: [desktop.leftWindow, desktop.rightWindow]

        delegate: Rectangle {
          id: window

          required property var modelData
          required property int index

          visible: modelData.length > 0
          x: modelData[4] - 2
          y: modelData[5] - 2
          width: modelData[6] + 4
          height: modelData[7] + 4
          radius: 10
          color: index === 0 ? desktop.look.border : desktop.look.inactive

          MockApp {
            x: 2
            y: 2
            width: window.width - 4
            height: window.height - 4
            kind: window.modelData.length ? art.apps[window.modelData[0]][3] : ""
          }
        }
      }
    }
  }

  function useTheme(name) {
    art.theme = name
    const look = art.themes[name]
    Color.foreground = look.colors[0]
    Color.background = look.colors[1]
    Color.accent = look.colors[2]
    Color.urgent = look.colors[3]
    FakeSystem.appPalette = look.apps
  }

  function toplevel(row, history) {
    const app = art.apps[row[0]]
    const extra = row[9] || {}
    return {
      address: "a" + (history + 1).toString(16) + "0f",
      title: row[1],
      workspace: { id: row[2], name: row[3] },
      monitor: { name: "DP-1" },
      urgent: false,
      wayland: { appId: app[0], contentReady: true, width: row[6], height: row[7], kind: app[3] },
      lastIpcObject: {
        mapped: true,
        focusHistoryID: history,
        "class": app[0],
        at: [row[4], row[5]],
        size: [row[6], row[7]],
        floating: !!extra.floating,
        fullscreen: extra.fullscreen ? 1 : 0,
        grouped: []
      }
    }
  }

  function setUpDesktop() {
    FakeSystem.reset()
    FakeSystem.surfaceWidth = art.screenWidth
    FakeSystem.surfaceHeight = art.screenHeight
    FakeSystem.appPalette = art.themes[art.theme].apps
    const entries = {}
    for (const key in art.apps) {
      const app = art.apps[key]
      entries[app[0]] = { name: app[1], icon: art.icons + "/" + app[2] }
    }
    FakeSystem.desktopEntries = entries
    const values = []
    for (let i = 0; i < art.windows.length; i++) values.push(toplevel(art.windows[i], i))
    Hyprland.usingLua = true
    Hyprland.toplevels = { values: values }
    Hyprland.activeToplevel = values[0]
    Hyprland.focusedMonitor = { name: "DP-1" }
    Hyprland.monitors = { values: [{
      name: "DP-1", id: 0, x: 0, y: 0, width: art.screenWidth, height: art.screenHeight, scale: 1,
      focused: true, activeWorkspace: { id: 1, name: "1" }, lastIpcObject: {}
    }] }
    Hyprland.dispatches = []
  }

  // Real focus ages instead of the startup estimate.
  function stampAges(fathom) {
    let tracker = null
    for (let i = 0; i < fathom.data.length; i++)
      if (fathom.data[i] && fathom.data[i].recencyState !== undefined) tracker = fathom.data[i]
    verify(tracker !== null, "found the recency tracker")
    const now = Date.now()
    const state = { lastActive: {}, active: "a10f", estimated: {} }
    for (let i = 0; i < art.windows.length; i++)
      state.lastActive["a" + (i + 1).toString(16) + "0f"] = now - art.windows[i][8] * 1000
    tracker.recencyState = state
    tracker.revision++
  }

  function save(item, file) {
    let saved = false
    item.grabToImage(function(result) { saved = result.saveToFile(art.outDir + "/" + file) })
    tryVerify(function() { return saved }, 5000, "saved " + file)
  }

  function renderDesktop(name, left, right) {
    const desktop = createTemporaryObject(desktopComponent, art, { leftWindow: left, rightWindow: right })
    wait(100)
    save(desktop, name + ".png")
  }

  function makeFathom() {
    setUpDesktop()
    const fathom = createTemporaryObject(fathomComponent, art)
    tryVerify(function() { return JSON.parse(FakeSystem.ipc("fathom").state()).seeded === true }, 2000)
    stampAges(fathom)
    // Every window seen once, so the map shows frames, as after a while in use.
    FakeSystem.ipc("fathom").open()
    tryVerify(function() { return fathom.revealed }, 1000)
    for (let i = 0; i < art.windows.length; i++) {
      fathom.jumpTo(i)
      wait(480)
    }
    FakeSystem.ipc("fathom").cancel()
    return fathom
  }

  // Opens as Alt+Tab does, and freezes the camera so frames set it by hand.
  function hold(fathom) {
    FakeSystem.press("fathom", "next")
    tryVerify(function() { return fathom.revealed }, 1000)
    wait(300)
    fathom.cameraAnimated = false
    fathom.fieldView.sceneDepth = fathom.fieldView.selectedDepth
  }

  function test_1_desktops() {
    for (const name of ["tokyo-night", "rose-pine", "gruvbox", "catppuccin-latte"]) {
      useTheme(name)
      renderDesktop("desktop-" + name, art.windows[0], art.windows[2])
      renderDesktop("desktop-" + name + "-photos", art.windows[7], art.windows[10])
    }
  }

  // The marketplace preview and the banner: Alt held, three windows down.
  function test_2_stills() {
    for (const name of ["tokyo-night", "rose-pine", "gruvbox", "catppuccin-latte"]) {
      useTheme(name)
      const fathom = makeFathom()
      hold(fathom)
      FakeSystem.press("fathom", "next")
      FakeSystem.press("fathom", "next")
      fathom.fieldView.sceneDepth = fathom.fieldView.selectedDepth
      wait(500)
      save(fathom.fieldView, "field-" + name + ".png")
      FakeSystem.ipc("fathom").cancel()
      fathom.destroy()
      wait(100)
    }
  }

  // The demo: Alt+Tab, four windows down, a workspace to the right, a
  // filter, and the release onto the window found.
  function test_3_demo() {
    useTheme("tokyo-night")
    const fathom = makeFathom()
    const view = fathom.fieldView
    let frame = 0
    let fromSlot = 0
    let fromDepth = 0
    function shot(blur, desktop) {
      // Frames take longer than real time: keep the hold-mode watchdog quiet.
      fathom.noteInput()
      const tag = String(++frame).padStart(4, "0")
      // The surface, not the view: a grab leaves out the grabbed item's own
      // opacity, and the fades are the view's.
      save(view.parent, "demo/f" + tag + "_b" + String(Math.round(blur * 100)).padStart(3, "0") + "_" + desktop + ".png")
    }
    function ease(t) { return 1 - Math.pow(1 - t, 3) }
    // Runs a key's action, then glides the camera and the lead from where
    // they were, as the real animation does, a frame at a time.
    function act(action, frames, holdFrames) {
      fromSlot = fathom.cameraSlot
      fromDepth = view.sceneDepth
      action()
      const toSlot = fathom.cameraSlot
      const toDepth = view.selectedDepth
      for (let i = 1; i <= frames; i++) {
        const t = ease(i / frames)
        fathom.cameraSlot = fromSlot + (toSlot - fromSlot) * t
        view.sceneDepth = fromDepth + (toDepth - fromDepth) * t
        shot(1, "desk")
      }
      for (let j = 0; j < holdFrames; j++) shot(1, "desk")
    }

    // The desktop, then Alt+Tab.
    hold(fathom)
    view.opacity = 0
    for (let i = 0; i < 10; i++) shot(0, "desk")
    for (let i = 1; i <= 6; i++) {
      view.opacity = i / 6
      shot(i / 6, "desk")
    }
    for (let i = 0; i < 8; i++) shot(1, "desk")
    // Tab, four times: down through the hours.
    for (let n = 0; n < 4; n++) act(function() { FakeSystem.press("fathom", "next") }, 5, 5)
    for (let i = 0; i < 4; i++) shot(1, "desk")
    // Right: the next workspace's most recent window.
    act(function() { fathom.workspaceStep(1) }, 6, 10)
    // Typing filters.
    for (const text of ["p", "ph", "pho"]) act(function() { fathom.setFilter(text) }, 4, 4)
    for (let i = 0; i < 12; i++) shot(1, "desk")
    // Release: the field goes, and the chosen window is in front.
    for (let i = 5; i >= 0; i--) {
      view.opacity = i / 6
      shot(i / 6, "photos")
    }
    for (let i = 0; i < 14; i++) shot(0, "photos")
    FakeSystem.ipc("fathom").cancel()
  }
}
