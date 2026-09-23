pragma Singleton

// Shared state for the stub Quickshell modules: registries of the shortcuts
// and IPC handlers the plugin created.

import QtQuick

QtObject {
  property var shortcuts: []
  property var ipcHandlers: []

  function reset() {
    shortcuts = []
    ipcHandlers = []
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
