pragma Singleton

// Stands in for Quickshell's Hyprland singleton: toplevels and monitors are
// plain objects set by the test; dispatches are recorded.

import QtQuick

QtObject {
  property bool usingLua: true
  property var toplevels: ({ values: [] })
  property var monitors: ({ values: [] })
  property var activeToplevel: null
  property var focusedMonitor: null
  property var dispatches: []
  property int refreshCount: 0

  signal rawEvent(var event)

  function dispatch(request) {
    dispatches = dispatches.concat([request])
  }

  function refreshToplevels() {
    refreshCount++
  }
}
