pragma Singleton

import QtQuick
import FathomTest

QtObject {
  property var screens: [{ name: "eDP-1" }, { name: "DP-1" }]

  // The environment as Quickshell.env reads it; tests set what they need.
  property var environment: ({})
  function env(name) { return environment[name] || "" }

  // No icon theme offscreen: every app gets its lettered tile. Each name
  // asked for is recorded (FakeSystem.iconRequests).
  function iconPath(name, check) {
    FakeSystem.iconRequests = FakeSystem.iconRequests.concat([String(name)])
    return ""
  }
}
