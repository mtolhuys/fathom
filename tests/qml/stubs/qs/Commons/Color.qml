pragma Singleton

import QtQuick

QtObject {
  property var shellValues: ({})

  function pick(key, fallback) {
    const value = shellValues[key]
    return typeof value === "string" && value.length > 0 ? value : fallback
  }

  property color foreground: "#ccd0cf"
  property color background: "#171717"
  property color accent: "#f25623"
  property color urgent: "#e0463a"
  property color muted: "#8a8f8e"
}
