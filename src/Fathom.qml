// Fathom: a depth-based Alt-Tab for Omarchy Quattro.
//
// Every window is placed on a z-axis by how long ago it last had focus: the
// window you used most recently is in front, older ones recede. Hold Alt, dive
// with Tab, release Alt to focus the window in front. The overlay never moves,
// resizes or closes a real window; focusing the selection is its only write.
//
// Phase 0: live thumbnails, depth applied to scale and opacity, Tab and
// Shift+Tab selection, focus on Alt release. See docs/SPEC.md.
//
// Input reaches this item three ways, and every handler is idempotent:
//   * Hyprland global shortcuts fathom:next, fathom:previous and
//     fathom:release, bound by hypr/fathom.lua (the release comes from a raw
//     key hook, so it is seen even when Alt is let go before this surface has
//     keyboard focus);
//   * keys delivered to the overlay while it holds exclusive keyboard focus;
//   * IPC: `omarchy-shell fathom <method>` and the shell's summon/hide.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Depth.js" as Depth
import "Recency.js" as Recency
import "Focus.js" as Focus

Item {
  id: root

  // Injected by Omarchy's panel loader.
  property var shell: null
  property var manifest: null

  readonly property string buildIdentity: "0.1.0-phase0"
  readonly property string pluginId: String((manifest && manifest.id) || "io.github.mtolhuys.fathom")

  // Read by the shell (isPluginOpen) as well as by the planes.
  property bool opened: false
  // "hold": opened by the Alt+Tab chord, releasing Alt commits.
  // "browse": opened by IPC or summon without a step, Enter or a click commits.
  property string mode: "hold"
  property var field: []
  property int selectedIndex: -1
  // The camera sits on the selection. Both coordinates animate together so a
  // plane's scale and opacity stay continuous while the camera moves.
  property real cameraIndex: 0
  property real cameraDepth: 0
  property bool cameraAnimated: false
  property var targetScreen: null
  property real openedAtMs: 0
  property real firstContentMs: -1

  property string pendingFocusAddress: ""
  property int pendingGroupIndex: 0

  property bool probeEnabled: false
  property real benchEndsAtMs: 0
  property var lastStats: null
  property var lastCaptures: []

  readonly property var selectedEntry: selectedIndex >= 0 && selectedIndex < field.length ? field[selectedIndex] : null
  // The field's content item, for diagnostics and the offscreen tests.
  readonly property Item fieldView: surface.view

  Behavior on cameraIndex {
    enabled: root.cameraAnimated
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Behavior on cameraDepth {
    enabled: root.cameraAnimated
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  RecencyTracker {
    id: recency
  }

  // ------------------------------------------------------------ field

  function screenForFocusedMonitor() {
    const name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      if (screens[i] && String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length ? screens[0] : null
  }

  function collectCandidates() {
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    const candidates = []
    for (let i = 0; i < toplevels.length; i++) {
      const toplevel = toplevels[i]
      if (!toplevel) continue
      const ipc = toplevel.lastIpcObject || {}
      const workspace = toplevel.workspace
      const ipcWorkspace = ipc.workspace || {}
      const workspaceId = workspace ? Number(workspace.id) : Number(ipcWorkspace.id)
      const workspaceName = String((workspace ? workspace.name : ipcWorkspace.name) || "")
      candidates.push({
        address: toplevel.address,
        toplevel: toplevel,
        hasHandle: !!toplevel.wayland,
        mapped: ipc.mapped,
        special: (isFinite(workspaceId) && workspaceId < 0) || workspaceName.indexOf("special") === 0,
        workspaceId: isFinite(workspaceId) ? workspaceId : null,
        workspaceName: workspaceName,
        focusHistoryID: ipc.focusHistoryID,
        grouped: ipc.grouped || [],
        title: String(toplevel.title || ipc.title || ""),
        appId: String((toplevel.wayland && toplevel.wayland.appId) || ipc["class"] || "")
      })
    }
    return candidates
  }

  function openField(nextMode, step) {
    if (root.opened) {
      if (step) root.step(step)
      return true
    }

    // Fresh geometry for lastIpcObject; planes bind to it and update when the
    // reply lands, so opening does not wait for it.
    Hyprland.refreshToplevels()

    // Windows the tracker has not seen yet get their seed from the data
    // Quickshell already holds.
    recency.seedFromToplevels()

    const now = Date.now()
    const fallbackActive = Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
    const entries = Recency.buildField(root.collectCandidates(), recency.state, now, fallbackActive)
    // Holding Alt+Tab with a single window has nowhere to go.
    if (entries.length < (nextMode === "hold" ? 2 : 1)) return false

    root.cameraAnimated = false
    root.targetScreen = root.screenForFocusedMonitor()
    root.mode = nextMode
    root.field = entries
    root.selectedIndex = Recency.initialSelection(entries.length, step)
    root.cameraIndex = root.selectedIndex
    root.cameraDepth = entries[root.selectedIndex].depth
    root.openedAtMs = now
    root.firstContentMs = -1
    root.opened = true
    if (nextMode === "hold") watchdog.restart()
    Qt.callLater(function() {
      root.cameraAnimated = true
      surface.view.focusKeys()
    })
    return true
  }

  function step(delta) {
    if (!root.opened || !root.field.length) return false
    root.selectedIndex = Recency.stepSelection(root.selectedIndex, delta, root.field.length)
    root.cameraIndex = root.selectedIndex
    root.cameraDepth = root.field[root.selectedIndex].depth
    if (root.mode === "hold") watchdog.restart()
    return true
  }

  // A step that comes from the Alt chord arms release-to-commit, even when the
  // field was opened in browse mode.
  function chordStep(delta) {
    if (root.opened) {
      root.mode = "hold"
      return root.step(delta)
    }
    return root.openField("hold", delta)
  }

  function altReleased() {
    if (root.opened && root.mode === "hold") root.commit()
  }

  // Any key while holding counts as activity for the watchdog.
  function noteInput() {
    if (root.opened && root.mode === "hold") watchdog.restart()
  }

  function selectAndCommit(index) {
    if (!root.opened || index < 0 || index >= root.field.length) return
    root.selectedIndex = index
    // Deferred: committing clears the field, which destroys the plane whose
    // click handler is still running.
    Qt.callLater(root.commit)
  }

  function commit() {
    if (!root.opened) return false
    const entry = root.selectedEntry
    root.dismiss()
    if (!entry) return false
    root.pendingFocusAddress = entry.address
    root.pendingGroupIndex = Focus.groupIndexFor(entry.address, entry.grouped)
    focusTimer.restart()
    return true
  }

  function cancel() {
    if (!root.opened) return false
    root.dismiss()
    return true
  }

  function dismiss() {
    watchdog.stop()
    if (benchTimer.running) root.finishBench()
    root.opened = false
    root.cameraAnimated = false
    root.field = []
    root.selectedIndex = -1
    // Keep the shell's open-state bookkeeping in step when Fathom closes itself.
    // hide() calls close() below, which is a no-op by now.
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function noteFirstContent() {
    if (root.opened && root.firstContentMs < 0) root.firstContentMs = Date.now() - root.openedAtMs
  }

  // ------------------------------------------------------------ shell hooks

  // `omarchy-shell shell summon <id> '{"step":1}'` behaves like the Alt chord;
  // a summon without a step opens the field for browsing.
  function open(payloadJson) {
    let payload = ({})
    try {
      payload = JSON.parse(payloadJson || "{}") || ({})
    } catch (error) {
      payload = ({})
    }
    const raw = Number(payload.step) || 0
    const direction = raw > 0 ? 1 : (raw < 0 ? -1 : 0)
    const shown = direction ? root.chordStep(direction) : root.openField("browse", 0)
    if (!shown && !root.opened && root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function close() {
    root.cancel()
  }

  // ------------------------------------------------------------ reporting

  function visibleWorkspaceIds() {
    const ids = []
    const monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (let i = 0; i < monitors.length; i++) {
      const monitor = monitors[i]
      if (!monitor) continue
      let id = monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : NaN
      if (!isFinite(id) && monitor.lastIpcObject && monitor.lastIpcObject.activeWorkspace)
        id = Number(monitor.lastIpcObject.activeWorkspace.id)
      if (isFinite(id)) ids.push(id)
    }
    return ids
  }

  function stateJson() {
    return JSON.stringify({
      buildIdentity: root.buildIdentity,
      opened: root.opened,
      mode: root.mode,
      windows: root.field.length,
      selectedIndex: root.selectedIndex,
      usingLua: Hyprland.usingLua,
      trackedWindows: recency.trackedCount(),
      seeded: recency.seeded,
      screen: root.targetScreen ? String(root.targetScreen.name || "") : ""
    })
  }

  function fieldJson() {
    const now = Date.now()
    const fallbackActive = Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
    const entries = root.opened
      ? root.field
      : Recency.buildField(root.collectCandidates(), recency.state, now, fallbackActive)
    const rows = []
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      rows.push({
        index: i,
        address: Focus.dispatchAddress(entry.address),
        appId: entry.appId,
        title: entry.title,
        workspace: entry.workspaceName,
        seconds: isFinite(entry.seconds) ? Math.round(entry.seconds * 10) / 10 : null,
        depth: Math.round(entry.depth * 1000) / 1000,
        scale: Math.round(Depth.scaleForDepth(entry.depth) * 1000) / 1000,
        opacity: Math.round(Depth.opacityForDepth(entry.depth) * 1000) / 1000
      })
    }
    return JSON.stringify(rows)
  }

  // Whether each open plane received a frame, and whether its workspace is
  // shown on any monitor: the "does capture work off-screen" answer.
  function collectCaptures() {
    const visible = root.visibleWorkspaceIds()
    const rows = []
    for (let i = 0; i < surface.view.planeCount; i++) {
      const plane = surface.view.planeAt(i)
      if (!plane || !plane.entry) continue
      rows.push({
        address: Focus.dispatchAddress(plane.entry.address),
        appId: plane.entry.appId,
        workspace: plane.entry.workspaceName,
        workspaceVisible: plane.entry.workspaceId !== null && visible.indexOf(plane.entry.workspaceId) !== -1,
        hasContent: plane.hasContent,
        sourceSize: plane.hasContent ? plane.sourceSize.width + "x" + plane.sourceSize.height : ""
      })
    }
    return rows
  }

  function statsJson() {
    const summary = surface.view.probe.running ? surface.view.probe.summary() : (root.lastStats ? root.lastStats.frames : null)
    return JSON.stringify({
      buildIdentity: root.buildIdentity,
      windows: root.opened ? root.field.length : (root.lastStats ? root.lastStats.windows : 0),
      firstContentMs: root.lastStats ? root.lastStats.firstContentMs : root.firstContentMs,
      frames: summary
    })
  }

  // Opens the field for browsing, steps one window deeper every 250 ms so the
  // camera is always animating, then closes. Read the result with `stats` and
  // `captures`.
  function startBench(seconds) {
    const duration = Math.max(2, Math.min(60, Number(seconds) || 10))
    if (!root.opened && !root.openField("browse", 0)) return "no windows"
    root.lastStats = null
    root.probeEnabled = true
    root.benchEndsAtMs = Date.now() + duration * 1000
    benchTimer.restart()
    return "ok"
  }

  function finishBench() {
    benchTimer.stop()
    const summary = surface.view.probe.summary()
    root.lastCaptures = root.collectCaptures()
    root.lastStats = {
      windows: root.field.length,
      firstContentMs: root.firstContentMs,
      frames: summary
    }
    root.probeEnabled = false
  }

  // ------------------------------------------------------------ timers

  // Focus only after the overlay surface is gone: releasing the exclusive
  // keyboard grab makes Hyprland restore focus to the previous window, which
  // would undo a focus sent any earlier.
  Timer {
    id: focusTimer

    interval: 100
    onTriggered: {
      const usingLua = Hyprland.usingLua
      const group = Focus.groupActivateRequest(root.pendingFocusAddress, root.pendingGroupIndex, usingLua)
      if (group) Hyprland.dispatch(group)
      const request = Focus.focusRequest(root.pendingFocusAddress, usingLua)
      if (request) Hyprland.dispatch(request)
      root.pendingFocusAddress = ""
      root.pendingGroupIndex = 0
    }
  }

  // If an Alt release is ever missed the field would stay up for good; after
  // 15 seconds without input in hold mode it closes without focusing.
  Timer {
    id: watchdog

    interval: 15000
    onTriggered: root.cancel()
  }

  Timer {
    id: benchTimer

    interval: 250
    repeat: true
    onTriggered: {
      if (Date.now() >= root.benchEndsAtMs) {
        root.finishBench()
        root.cancel()
        return
      }
      root.step(1)
    }
  }

  // ------------------------------------------------------------ shortcuts

  GlobalShortcut {
    appid: "fathom"
    name: "next"
    description: "Fathom: open the field or dive one window deeper"
    onPressed: root.chordStep(1)
  }

  GlobalShortcut {
    appid: "fathom"
    name: "previous"
    description: "Fathom: open the field at the far end or rise one window"
    onPressed: root.chordStep(-1)
  }

  GlobalShortcut {
    appid: "fathom"
    name: "release"
    description: "Fathom: Alt was released"
    onPressed: root.altReleased()
  }

  IpcHandler {
    target: "fathom"

    function open(): string {
      return root.openField("browse", 0) ? "ok" : "no windows"
    }

    function hold(direction: int): string {
      return root.chordStep(direction < 0 ? -1 : 1) ? "ok" : "no windows"
    }

    function step(direction: int): string {
      return root.step(direction < 0 ? -1 : 1) ? "ok" : "closed"
    }

    function release(): string {
      root.altReleased()
      return "ok"
    }

    function commit(): string {
      return root.commit() ? "ok" : "closed"
    }

    function cancel(): string {
      return root.cancel() ? "ok" : "closed"
    }

    function state(): string {
      return root.stateJson()
    }

    function field(): string {
      return root.fieldJson()
    }

    function captures(): string {
      return JSON.stringify(root.opened ? root.collectCaptures() : root.lastCaptures)
    }

    function stats(): string {
      return root.statsJson()
    }

    function bench(seconds: int): string {
      return root.startBench(seconds)
    }
  }

  // ------------------------------------------------------------ surface

  FieldSurface {
    id: surface

    controller: root
  }
}
