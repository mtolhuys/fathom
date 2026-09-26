pragma Singleton

import QtQuick
import FathomTest

QtObject {
  property var screens: [{ name: "eDP-1" }, { name: "DP-1" }]

  // No icon theme offscreen: every app gets its lettered tile. Each name
  // asked for is recorded (FakeSystem.iconRequests).
  function iconPath(name, check) {
    FakeSystem.iconRequests = FakeSystem.iconRequests.concat([String(name)])
    return ""
  }
}
