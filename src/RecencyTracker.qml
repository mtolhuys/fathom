// Keeps address -> last focus time for every window, from the moment the
// shell loads Fathom (the plugin is keepLoaded, so this runs all session).
//
// Hyprland exposes focus order but no timestamps, so the socket2 event stream
// is followed through Quickshell's Hyprland.rawEvent, and the map is seeded
// from focusHistoryID. The seed comes from Quickshell's own `j/clients`
// request (Hyprland.refreshToplevels fills each toplevel's lastIpcObject, the
// same JSON `hyprctl clients -j` prints), so Fathom starts no program at all.
// Read-only: it never sends anything to the compositor.

import QtQuick
import Quickshell.Hyprland
import "Recency.js" as Recency

Item {
  id: tracker

  property var recencyState: Recency.createState()
  // True once at least one window was seeded from its focusHistoryID.
  property bool seeded: false
  // Bumped on every change; the state object itself is mutated in place.
  property int revision: 0

  // A window closed (socket2 closewindow); the field drops it at once.
  signal windowClosed(string address)

  function secondsSince(address, nowMs, fallbackActive) {
    return Recency.secondsSince(tracker.recencyState, address, nowMs, fallbackActive)
  }

  function trackedCount() {
    return Object.keys(tracker.recencyState.lastActive).length
  }

  // Seeds every window the map does not know yet from the focusHistoryID in
  // its lastIpcObject. Safe to call any number of times: known windows (and
  // every window a focus event has stamped) are left alone.
  function seedFromToplevels() {
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    const clients = []
    for (let i = 0; i < toplevels.length; i++) {
      const toplevel = toplevels[i]
      const ipc = toplevel ? toplevel.lastIpcObject : null
      if (!ipc || ipc.focusHistoryID === undefined) continue
      clients.push({ address: toplevel.address, focusHistoryID: ipc.focusHistoryID })
    }
    const count = Recency.seedFromClients(tracker.recencyState, clients, Date.now())
    if (clients.length > 0) tracker.seeded = true
    if (count > 0) tracker.revision++
    return count
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Qt.callLater(tracker.seedFromToplevels)
    seedRetry.start()
  }

  // The refresh reply lands a round trip after the request; retry until the
  // toplevels carry their focusHistoryID, for at most ten seconds.
  Timer {
    id: seedRetry

    property int attempts: 0

    interval: 500
    repeat: true
    onTriggered: {
      attempts++
      tracker.seedFromToplevels()
      if (tracker.seeded || attempts >= 20) stop()
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      const name = event.name
      let changed = false
      // activewindowv2 carries the address; plain activewindow only has
      // class and title.
      if (name === "activewindowv2") changed = Recency.recordFocus(tracker.recencyState, event.data, Date.now())
      else if (name === "openwindow") changed = Recency.recordOpen(tracker.recencyState, event.data, Date.now())
      else if (name === "closewindow") {
        changed = Recency.recordClose(tracker.recencyState, event.data)
        if (changed) tracker.windowClosed(Recency.firstField(event.data))
      }
      if (changed) tracker.revision++
    }
  }
}
