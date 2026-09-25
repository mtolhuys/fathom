// Fathom: a depth-based Alt-Tab for Omarchy Quattro.
//
// Every window is placed on a z-axis by how long ago it last had focus: the
// window you used most recently is in front, older ones recede. Hold Alt, dive
// with Tab (or the arrows, or the wheel), release Alt to focus the window in
// front. Below the depth view, a map shows every workspace with its windows.
// The overlay never moves, resizes or closes a real window; focusing the
// selection is its only write.
//
// Input reaches this item three ways, and every handler is idempotent:
//   * Hyprland global shortcuts fathom:next, fathom:previous and
//     fathom:release, bound by hypr/fathom.lua (which also enters a `fathom`
//     submap while Alt is held, so chords such as Alt+Left reach the overlay
//     instead of the user's own Alt bindings);
//   * keys, the wheel and the pointer on the overlay, which holds exclusive
//     keyboard focus while it is open;
//   * IPC: `omarchy-shell fathom <method>` and the shell's summon/hide.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Depth.js" as Depth
import "Recency.js" as Recency
import "Focus.js" as Focus
import "Field.js" as Field

Item {
  id: root

  // Injected by Omarchy's panel loader.
  property var shell: null
  property var manifest: null

  readonly property string buildIdentity: "0.2.0-deep"
  readonly property string pluginId: String((manifest && manifest.id) || "io.github.mtolhuys.fathom")

  // Read by the shell (isPluginOpen) as well as by the view.
  property bool opened: false
  // Whether special workspaces (scratchpads) are included in the field.
  // Defaults to true, configurable in shell.json under this plugin's properties.
  property bool showScratchpads: true

  function readPluginConfig() {
    const list = (shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins)) ? shell.shellConfig.plugins : []
    for (let i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].id) === root.pluginId) return list[i]
    }
    return ({})
  }

  onShellChanged: {
    const cfg = root.readPluginConfig()
    if (cfg.showScratchpads !== undefined) {
      root.showScratchpads = Boolean(cfg.showScratchpads)
    }
  }
  // Whether the field is drawn. In hold mode it appears after 90 ms
  // (revealTimer), so a quick Alt+Tab switches without flashing the overlay;
  // the surface
  // (and its keyboard grab) exists from the first moment either way.
  property bool revealed: false
  // "hold": opened by the Alt+Tab chord, releasing Alt commits.
  // "browse": opened by IPC or summon without a step, or kept open with
  // Space; Enter or a click commits.
  property string mode: "hold"
  property bool pinned: false

  // The field is frozen while open: entries keep their index. What is shown
  // is `order`, the entry indices that are neither closed nor filtered out.
  property var field: []
  property var closed: ({})
  property string filterText: ""
  property var order: []
  property var slots: []
  property var groups: []
  property var monitorInfo: ({})
  property int selectedIndex: -1
  // The camera sits on the selection's slot and animates between slots.
  property real cameraSlot: 0
  property bool cameraAnimated: false
  property var targetScreen: null
  property real openedAtMs: 0
  property real firstContentMs: -1
  property real wheelCarryY: 0
  property real wheelCarryX: 0

  property string pendingFocusAddress: ""
  property int pendingGroupIndex: 0

  property bool probeEnabled: false
  property real benchEndsAtMs: 0
  property var lastStats: null
  property var lastCaptures: []

  readonly property var selectedEntry: selectedIndex >= 0 && selectedIndex < field.length ? field[selectedIndex] : null
  readonly property int selectedSlot: selectedIndex >= 0 && selectedIndex < slots.length ? slots[selectedIndex] : -1
  // The field's content item, for diagnostics and the offscreen tests.
  readonly property Item fieldView: surface.view

  Behavior on cameraSlot {
    enabled: root.cameraAnimated
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  RecencyTracker {
    id: recency

    onWindowClosed: address => {
      root.dropSnapshot(address)
      root.markClosed(address)
    }
  }

  // ------------------------------------------------------------ the field

  function screenForFocusedMonitor() {
    const name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      if (screens[i] && String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length ? screens[0] : null
  }

  // Icons come from the desktop entry that matches the window's app id or
  // class, through Quickshell's own index (no process, no file of ours).
  property var iconCache: ({})

  function desktopEntryFor(appId, windowClass) {
    const candidates = [appId, windowClass]
    for (let i = 0; i < candidates.length; i++) {
      const name = String(candidates[i] || "")
      if (!name) continue
      try {
        const entry = DesktopEntries.heuristicLookup(name)
        if (entry) return entry
      } catch (error) {
        return null
      }
    }
    return null
  }

  function appInfo(appId, windowClass) {
    const key = String(appId || "") + "|" + String(windowClass || "")
    if (key in root.iconCache) return root.iconCache[key]
    const entry = root.desktopEntryFor(appId, windowClass)
    let icon = ""
    const names = [entry ? String(entry.icon || "") : "", String(appId || ""), String(windowClass || "")]
    for (let i = 0; i < names.length && !icon; i++) {
      if (!names[i]) continue
      if (names[i].charAt(0) === "/") icon = "file://" + names[i]
      else icon = String(Quickshell.iconPath(names[i], true) || "")
    }
    const info = { icon: icon, name: Field.appName(appId || windowClass, entry ? entry.name : "") }
    root.iconCache[key] = info
    return info
  }

  function monitorName(toplevel, ipc) {
    if (toplevel.monitor && toplevel.monitor.name) return String(toplevel.monitor.name)
    const monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (let i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].id === ipc.monitor) return String(monitors[i].name || "")
    }
    return ""
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
      const appId = String((toplevel.wayland && toplevel.wayland.appId) || ipc["class"] || "")
      const info = root.appInfo(appId, ipc["class"])
      const at = ipc.at || []
      const size = ipc.size || []
      const isSpecial = Field.isSpecialName(workspaceName)

      // Skip scratchpad windows if configured to do so
      if (isSpecial && !root.showScratchpads) continue

      candidates.push({
        address: toplevel.address,
        toplevel: toplevel,
        hasHandle: !!toplevel.wayland,
        mapped: ipc.mapped,
        special: isSpecial,
        workspaceId: isFinite(workspaceId) ? workspaceId : null,
        workspaceName: workspaceName,
        monitorName: root.monitorName(toplevel, ipc),
        focusHistoryID: ipc.focusHistoryID,
        grouped: ipc.grouped || [],
        floating: ipc.floating === true,
        fullscreen: Number(ipc.fullscreen) > 0,
        geometry: at.length >= 2 && size.length >= 2
          ? { x: Number(at[0]), y: Number(at[1]), width: Number(size[0]), height: Number(size[1]) } : null,
        title: String(toplevel.title || ipc.title || ""),
        appId: appId,
        appName: info.name,
        icon: info.icon
      })
    }
    return candidates
  }

  // A window's position and size from Hyprland's latest client list, falling
  // back to the one read when the field opened. Bindings that call this
  // follow the list: it is refreshed on open and lands a moment later.
  function geometryOf(entry) {
    const ipc = entry && entry.toplevel ? entry.toplevel.lastIpcObject : null
    const at = ipc && ipc.at ? ipc.at : null
    const size = ipc && ipc.size ? ipc.size : null
    if (at && size && at.length >= 2 && size.length >= 2)
      return { x: Number(at[0]), y: Number(at[1]), width: Number(size[0]), height: Number(size[1]) }
    return entry ? entry.geometry : null
  }

  // Logical geometry of every monitor, for the map's minimaps.
  function collectMonitors() {
    const info = {}
    const monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (let i = 0; i < monitors.length; i++) {
      const monitor = monitors[i]
      if (!monitor) continue
      const ipc = monitor.lastIpcObject || {}
      const scale = Number(monitor.scale || ipc.scale) > 0 ? Number(monitor.scale || ipc.scale) : 1
      let width = Number(monitor.width || ipc.width) / scale
      let height = Number(monitor.height || ipc.height) / scale
      if (Number(ipc.transform) % 2 === 1) {
        const swap = width
        width = height
        height = swap
      }
      info[String(monitor.name || "")] = {
        x: Number(monitor.x !== undefined ? monitor.x : ipc.x) || 0,
        y: Number(monitor.y !== undefined ? monitor.y : ipc.y) || 0,
        width: width > 0 ? width : 1920,
        height: height > 0 ? height : 1080,
        focused: !!monitor.focused
      }
    }
    return info
  }

  function visibleWorkspaces() {
    const list = []
    const monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (let i = 0; i < monitors.length; i++) {
      const monitor = monitors[i]
      if (!monitor) continue
      const workspace = monitor.activeWorkspace
      let id = workspace ? Number(workspace.id) : NaN
      let name = workspace ? String(workspace.name || "") : ""
      if (!isFinite(id) && monitor.lastIpcObject && monitor.lastIpcObject.activeWorkspace) {
        id = Number(monitor.lastIpcObject.activeWorkspace.id)
        name = String(monitor.lastIpcObject.activeWorkspace.name || "")
      }
      if (isFinite(id)) list.push({ id: id, name: name || String(id), monitor: String(monitor.name || "") })
    }
    return list
  }

  function visibleWorkspaceIds() {
    const on = root.visibleWorkspaces()
    const ids = []
    for (let i = 0; i < on.length; i++) ids.push(on[i].id)
    return ids
  }

  function refreshOrder() {
    const previous = root.order
    const next = Field.visibleOrder(root.field, root.closed, root.filterText)
    root.order = next
    root.slots = Field.slotsFor(next, root.field.length)
    root.select(Field.reselect(next, root.selectedIndex, previous))
  }

  function select(index) {
    const valid = index >= 0 && index < root.slots.length && root.slots[index] >= 0
    root.selectedIndex = valid ? index : -1
    if (valid) root.cameraSlot = root.slots[index]
  }

  // ------------------------------------------------------------ snapshots

  // Hyprland renders a window for capture only while it lies within its
  // monitor's area; a scrolling layout parks windows beside the screen, and
  // those never deliver a frame. So each card keeps the last frame it saw
  // while the field was open, here, in memory only (never on disk), and shows
  // it, marked with its age, when a live frame does not come; the map shows
  // the same images as thumbnails. Bounded to
  // snapshotLimit windows, oldest dropped first; a window's snapshot goes
  // when the window closes.
  readonly property int snapshotLimit: 24
  readonly property int snapshotWidth: 640
  property var snapshots: ({})

  function keepSnapshot(address, result) {
    const key = Recency.normalizeAddress(address)
    if (!key || !result || !result.url) return false
    const next = Object.assign({}, root.snapshots)
    next[key] = { url: String(result.url), takenAt: Date.now(), result: result }
    const keys = Object.keys(next)
    if (keys.length > root.snapshotLimit) {
      keys.sort((a, b) => next[a].takenAt - next[b].takenAt)
      for (let i = 0; i < keys.length - root.snapshotLimit; i++) delete next[keys[i]]
    }
    root.snapshots = next
    return true
  }

  // A snapshot younger than this is not taken again: a grab reads the frame
  // back from the GPU, and doing that for every card on every Alt+Tab is waste.
  readonly property int snapshotFreshMs: 30000

  function wantsSnapshot(address) {
    const kept = root.snapshots[Recency.normalizeAddress(address)]
    return !kept || Date.now() - kept.takenAt > root.snapshotFreshMs
  }

  // Snapshots of windows that no longer exist go, even when the closewindow
  // event was missed: Hyprland reuses addresses.
  function sweepSnapshots() {
    const keys = Object.keys(root.snapshots)
    if (!keys.length) return
    const present = {}
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (let i = 0; i < toplevels.length; i++) {
      if (toplevels[i]) present[Recency.normalizeAddress(toplevels[i].address)] = true
    }
    for (let j = 0; j < keys.length; j++) if (!present[keys[j]]) root.dropSnapshot(keys[j])
  }

  function dropSnapshot(address) {
    const key = Recency.normalizeAddress(address)
    if (!key || !(key in root.snapshots)) return
    const next = Object.assign({}, root.snapshots)
    delete next[key]
    root.snapshots = next
  }

  function markClosed(address) {
    const key = Recency.normalizeAddress(address)
    if (!root.opened || !key || root.closed[key]) return
    let known = false
    for (let i = 0; i < root.field.length; i++) if (root.field[i].address === key) known = true
    if (!known) return
    const next = Object.assign({}, root.closed)
    next[key] = true
    root.closed = next
    root.refreshOrder()
    // Nothing left to switch to.
    if (!root.order.length && !root.filterText) root.cancel()
  }

  function sweepClosed() {
    if (!root.opened) return
    const present = {}
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (let i = 0; i < toplevels.length; i++) {
      if (toplevels[i]) present[Recency.normalizeAddress(toplevels[i].address)] = true
    }
    for (let j = 0; j < root.field.length; j++) {
      if (!present[root.field[j].address]) root.markClosed(root.field[j].address)
    }
  }

  // Every window as it stands now, front to back.
  function currentField(now) {
    const fallbackActive = Hyprland.activeToplevel ? Hyprland.activeToplevel.address : ""
    return Recency.buildField(root.collectCandidates(), recency.recencyState, now, fallbackActive)
  }

  function openField(nextMode, step) {
    if (root.opened) {
      if (step) root.step(step)
      return true
    }

    // Fresh geometry for lastIpcObject; the view binds to it and updates when
    // the reply lands, so opening does not wait for it.
    Hyprland.refreshToplevels()

    // Windows the tracker has not seen yet get their seed from the data
    // Quickshell already holds.
    recency.seedFromToplevels()

    const now = Date.now()
    const entries = root.currentField(now)
    // Holding Alt+Tab with a single window has nowhere to go.
    if (entries.length < (nextMode === "hold" ? 2 : 1)) return false
    root.showField(entries, nextMode, step, now)
    return true
  }

  function showField(entries, nextMode, step, now) {
    root.cameraAnimated = false
    root.targetScreen = root.screenForFocusedMonitor()
    root.mode = nextMode
    root.pinned = false
    root.filterText = ""
    root.closed = ({})
    root.wheelCarryX = 0
    root.wheelCarryY = 0
    root.field = entries
    root.monitorInfo = root.collectMonitors()
    root.groups = Field.workspaceGroups(entries, root.visibleWorkspaces(), root.visibleWorkspaceIds())
    root.order = Field.visibleOrder(entries, root.closed, "")
    root.slots = Field.slotsFor(root.order, entries.length)
    root.select(Recency.initialSelection(entries.length, step))
    root.openedAtMs = now
    root.firstContentMs = -1
    root.revealed = nextMode !== "hold"
    root.opened = true
    if (nextMode === "hold") {
      watchdog.restart()
      revealTimer.restart()
    }
    Qt.callLater(function() {
      root.cameraAnimated = true
      surface.view.focusKeys()
    })
  }

  // Tab and Shift+Tab: one window deeper or shallower, wrapping at the ends.
  function step(delta) {
    if (!root.opened || !root.order.length) return false
    root.select(Field.step(root.order, root.selectedIndex, delta, true))
    root.noteInput()
    return true
  }

  // Arrows, paging and the wheel: the same, stopping at the ends.
  function move(delta) {
    if (!root.opened || !root.order.length) return false
    root.select(Field.step(root.order, root.selectedIndex, delta, false))
    root.noteInput()
    return true
  }

  function jumpTo(index) {
    if (!root.opened || index < 0) return false
    root.select(index)
    root.noteInput()
    return true
  }

  // Left and right: the most recent window of the neighboring workspace.
  function workspaceStep(direction) {
    if (!root.opened || !root.order.length) return false
    return root.jumpTo(Field.neighborWorkspace(root.groups, root.order, root.selectedIndex, direction))
  }

  function workspaceJump(number) {
    if (!root.opened) return false
    const index = Field.workspaceByNumber(root.groups, root.order, number)
    return index >= 0 ? root.jumpTo(index) : false
  }

  function setFilter(text) {
    if (!root.opened) return false
    const value = String(text || "").replace(/^\s+/, "")
    if (value === root.filterText) return true
    root.filterText = value
    root.refreshOrder()
    // A new query starts at its best (most recent) match.
    if (root.order.length) root.select(root.order[0])
    root.noteInput()
    return true
  }

  // Space while holding Alt: keep the field open after Alt is released.
  function pin() {
    if (!root.opened) return false
    root.pinned = true
    root.mode = "browse"
    root.revealed = true
    watchdog.stop()
    revealTimer.stop()
    return true
  }

  // A step that comes from the Alt chord arms release-to-commit, even when the
  // field was opened in browse mode (unless it was pinned there on purpose).
  function chordStep(delta) {
    if (root.opened) {
      if (!root.pinned) root.mode = "hold"
      return root.step(delta)
    }
    return root.openField("hold", delta)
  }

  function altReleased() {
    if (!root.opened || root.mode !== "hold") return
    if (root.selectedEntry) root.commit()
    else root.cancel()
  }

  // Any input while holding counts as activity for the watchdog.
  function noteInput() {
    if (root.opened && root.mode === "hold") watchdog.restart()
  }

  function selectAndCommit(index) {
    if (!root.opened || index < 0 || index >= root.field.length || root.slots[index] < 0) return
    root.selectedIndex = index
    // Deferred: committing clears the field, which destroys the plane whose
    // click handler is still running.
    Qt.callLater(root.commit)
  }

  // Keys delivered to the overlay. Returns whether the key was used.
  function handleKey(key, modifiers, text) {
    if (!root.opened) return false
    const shift = (modifiers & Qt.ShiftModifier) !== 0
    const control = (modifiers & Qt.ControlModifier) !== 0
    switch (key) {
    case Qt.Key_Tab: return root.step(shift ? -1 : 1) || true
    case Qt.Key_Backtab: return root.step(-1) || true
    case Qt.Key_Down: return root.move(1) || true
    case Qt.Key_Up: return root.move(-1) || true
    case Qt.Key_Right: return root.workspaceStep(1) || true
    case Qt.Key_Left: return root.workspaceStep(-1) || true
    case Qt.Key_PageDown: return root.move(5) || true
    case Qt.Key_PageUp: return root.move(-5) || true
    case Qt.Key_Home: return root.jumpTo(Field.first(root.order)) || true
    case Qt.Key_End: return root.jumpTo(Field.last(root.order)) || true
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (root.selectedEntry) root.commit()
      return true
    case Qt.Key_S:
      if (root.mode === "hold" || (modifiers & Qt.AltModifier) || !root.filterText) {
        root.showScratchpads = !root.showScratchpads
        const now = Date.now()
        const entries = root.currentField(now)
        root.showField(entries, root.mode, 0, now)
        return true
      }
      break
    case Qt.Key_Escape:
      if (root.filterText) root.setFilter("")
      else root.cancel()
      return true
    case Qt.Key_Backspace:
      root.setFilter(control ? "" : root.filterText.slice(0, -1))
      return true
    case Qt.Key_Space:
      // Between filter words it is a space; otherwise, while holding, it
      // keeps the field open.
      if (root.filterText) root.setFilter(root.filterText + " ")
      else if (root.mode === "hold") root.pin()
      return true
    }
    if (control) return false
    const typed = Field.typedCharacter(key, shift, text)
    if (!typed) return false
    // Digits pick a workspace until a filter is being typed.
    if (!root.filterText && typed >= "1" && typed <= "9") {
      root.workspaceJump(Number(typed))
      return true
    }
    return root.setFilter(root.filterText + typed)
  }

  // Wheel and touchpad: vertical dives (down is deeper), horizontal moves
  // between workspaces. Remainders carry over so slow scrolls add up.
  function wheel(angleY, pixelY, angleX, pixelX) {
    if (!root.opened) return false
    const vertical = Field.wheelSteps(root.wheelCarryY, angleY, pixelY)
    root.wheelCarryY = vertical.rest
    if (vertical.steps) root.move(vertical.steps)
    const horizontal = Field.wheelSteps(root.wheelCarryX, angleX, pixelX)
    root.wheelCarryX = horizontal.rest
    if (horizontal.steps) root.workspaceStep(horizontal.steps)
    root.noteInput()
    return true
  }

  function commit() {
    if (!root.opened) return false
    const entry = root.selectedEntry
    const closed = entry ? root.closed[entry.address] === true : true
    root.dismiss()
    if (!entry || closed) return false
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
    revealTimer.stop()
    if (benchTimer.running) root.finishBench()
    root.opened = false
    root.revealed = false
    root.cameraAnimated = false
    root.field = []
    root.order = []
    root.slots = []
    root.groups = []
    root.closed = ({})
    root.filterText = ""
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

  function stateJson() {
    return JSON.stringify({
      buildIdentity: root.buildIdentity,
      opened: root.opened,
      revealed: root.revealed,
      mode: root.mode,
      pinned: root.pinned,
      windows: root.field.length,
      shown: root.order.length,
      workspaces: root.groups.length,
      selectedIndex: root.selectedIndex,
      filter: root.filterText,
      usingLua: Hyprland.usingLua,
      snapshots: Object.keys(root.snapshots).length,
      trackedWindows: recency.trackedCount(),
      seeded: recency.seeded,
      screen: root.targetScreen ? String(root.targetScreen.name || "") : ""
    })
  }

  function fieldJson() {
    const entries = root.opened ? root.field : root.currentField(Date.now())
    const rows = []
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      rows.push({
        index: i,
        address: Focus.dispatchAddress(entry.address),
        appId: entry.appId,
        app: entry.appName,
        title: entry.title,
        workspace: entry.workspaceName,
        shown: !root.opened || (root.slots[i] !== undefined && root.slots[i] >= 0),
        seconds: isFinite(entry.seconds) ? Math.round(entry.seconds * 10) / 10 : null,
        age: Field.ageLabel(entry.seconds, entry.active, entry.estimated),
        depth: Math.round(entry.depth * 1000) / 1000,
        fog: Math.round(Depth.fogForDepth(entry.depth) * 1000) / 1000
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
        capturing: plane.capturing,
        hasContent: plane.hasContent,
        snapshot: plane.snapshot !== null,
        parked: plane.parked,
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

  // Opens the field for browsing, dives one window every 250 ms so the camera
  // is always animating, then closes. Read the result with `stats` and
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

  Timer {
    id: revealTimer

    interval: 90
    onTriggered: if (root.opened) root.revealed = true
  }

  // Focus only after the overlay surface is gone: releasing the exclusive
  // keyboard grab makes Hyprland restore focus to the previous window, which
  // would undo a focus sent any earlier. Hyprland announces that restore
  // (activewindowv2 with the previous window's address), and the request
  // goes out on that event; this timer is the fallback when none comes.
  function dispatchPendingFocus() {
    focusTimer.stop()
    const address = root.pendingFocusAddress
    root.pendingFocusAddress = ""
    const groupIndex = root.pendingGroupIndex
    root.pendingGroupIndex = 0
    if (!address) return
    // The window may have closed in the meantime.
    let present = false
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (let i = 0; i < toplevels.length; i++) {
      if (toplevels[i] && Recency.normalizeAddress(toplevels[i].address) === address) present = true
    }
    if (!present) return
    const usingLua = Hyprland.usingLua
    const group = Focus.groupActivateRequest(address, groupIndex, usingLua)
    if (group) Hyprland.dispatch(group)
    const request = Focus.focusRequest(address, usingLua)
    if (request) Hyprland.dispatch(request)
  }

  Timer {
    id: focusTimer

    interval: 120
    onTriggered: root.dispatchPendingFocus()
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

  // A window that closes while the field is open leaves it at once.
  Connections {
    target: Hyprland.toplevels && typeof Hyprland.toplevels.valuesChanged === "function" ? Hyprland.toplevels : null
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.sweepClosed()
      root.sweepSnapshots()
    }
  }

  Connections {
    target: Hyprland
    ignoreUnknownSignals: true

    function onToplevelsChanged() {
      root.sweepClosed()
      root.sweepSnapshots()
    }

    // The grab is gone and Hyprland gave focus back: safe to move it.
    function onRawEvent(event) {
      if (root.pendingFocusAddress && event && event.name === "activewindowv2"
          && Recency.normalizeAddress(event.data) !== "")
        root.dispatchPendingFocus()
    }
  }

  // Newly installed apps bring icons of their own.
  Connections {
    target: DesktopEntries.applications && typeof DesktopEntries.applications.valuesChanged === "function"
      ? DesktopEntries.applications : null
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.iconCache = ({})
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

    function move(delta: int): string {
      return root.move(delta) ? "ok" : "closed"
    }

    function workspace(direction: int): string {
      return root.workspaceStep(direction < 0 ? -1 : 1) ? "ok" : "closed"
    }

    function filter(text: string): string {
      return root.setFilter(text) ? "ok" : "closed"
    }

    function pin(): string {
      return root.pin() ? "ok" : "closed"
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
