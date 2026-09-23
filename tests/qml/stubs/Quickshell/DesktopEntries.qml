pragma Singleton

import QtQuick
import FathomTest

QtObject {
  // The real one is an object model of every entry; nothing changes offscreen.
  property var applications: null

  function heuristicLookup(name) {
    return FakeSystem.desktopEntries[name] || null
  }
}
