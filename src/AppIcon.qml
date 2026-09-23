// An application icon, or a lettered tile in a color derived from the app's
// name when the icon theme has nothing for it. Loaded only while shown: a
// card showing a live frame never decodes the icon of its placeholder.

import QtQuick

Item {
  id: icon

  property string source: ""
  property string name: ""
  property real size: 24

  readonly property bool loaded: image.status === Image.Ready
  // The letter stands in only where the icon theme has nothing, never for
  // the moment an icon takes to decode.
  readonly property bool missing: source.length === 0 || image.status === Image.Error

  function hue(text) {
    let hash = 0
    for (let i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) % 3600
    return hash / 3600
  }

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Image {
    id: image

    anchors.fill: parent
    source: icon.visible ? icon.source : ""
    sourceSize: Qt.size(Math.ceil(icon.size * 2), Math.ceil(icon.size * 2))
    asynchronous: true
    mipmap: true
    fillMode: Image.PreserveAspectFit
    visible: icon.loaded
  }

  Rectangle {
    anchors.fill: parent
    visible: icon.missing
    radius: width * 0.26
    color: Qt.hsla(icon.hue(icon.name || "?"), 0.32, 0.42, 1)

    Text {
      anchors.centerIn: parent
      text: (icon.name || "?").charAt(0).toUpperCase()
      color: "#f4f4f4"
      font.pixelSize: Math.max(6, icon.size * 0.52)
      font.bold: true
    }
  }
}
