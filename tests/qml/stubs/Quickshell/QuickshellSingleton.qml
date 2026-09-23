pragma Singleton

import QtQuick

QtObject {
  property var screens: [{ name: "eDP-1" }, { name: "DP-1" }]

  // No icon theme offscreen: every app gets its lettered tile.
  function iconPath(name, check) {
    return ""
  }
}
