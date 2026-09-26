pragma Singleton

// Shared state for the stub Quickshell modules: registries of the shortcuts
// and IPC handlers the plugin created, and the desktop entries it can find.

import QtQuick

QtObject {
  property var shortcuts: []
  property var ipcHandlers: []
  // Desktop entries by app id, for DesktopEntries.heuristicLookup.
  property var desktopEntries: ({})
  // Every name Quickshell.iconPath was asked for.
  property var iconRequests: []
  // Size of the test host for the field (tests/qml/FieldSurface.qml).
  property int surfaceWidth: 800
  property int surfaceHeight: 600
  // A stand-in desktop behind the field, blurred the way Hyprland blurs the
  // layer: "light", "dark", or "" for none (renders only).
  property string backdrop: ""
  // The palette stand-in apps (MockApp) draw in: { dark, bg, surface, raised,
  // fg, dim, faint, accent, colors: [...] }, or null for Tokyo Night.
  property var appPalette: null

  function reset() {
    shortcuts = []
    ipcHandlers = []
    desktopEntries = ({})
    iconRequests = []
    surfaceWidth = 800
    surfaceHeight = 600
    backdrop = ""
    appPalette = null
  }

  function registerShortcut(shortcut) {
    shortcuts.push(shortcut)
  }

  function press(appid, name) {
    for (let i = shortcuts.length - 1; i >= 0; i--) {
      const shortcut = shortcuts[i]
      if (shortcut && shortcut.appid === appid && shortcut.name === name) {
        shortcut.pressed()
        return true
      }
    }
    return false
  }

  function registerIpc(handler) {
    ipcHandlers.push(handler)
  }

  function ipc(target) {
    for (let i = ipcHandlers.length - 1; i >= 0; i--) {
      if (ipcHandlers[i] && ipcHandlers[i].target === target) return ipcHandlers[i]
    }
    return null
  }
}
