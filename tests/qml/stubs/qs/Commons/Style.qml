pragma Singleton

import QtQuick

QtObject {
  property int cornerRadius: 7
  property int normalBorderWidth: 1
  property real fontScale: 1
  readonly property var font: ({ family: "monospace" })
}
