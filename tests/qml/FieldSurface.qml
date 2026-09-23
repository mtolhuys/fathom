// Test replacement for src/FieldSurface.qml: hosts the real FieldView in a
// plain item instead of a layer-shell window.

import QtQuick

Item {
  id: surface

  property var controller: null
  readonly property alias view: view

  // The offscreen platform's screen is 800x600; pointer events outside it
  // are dropped.
  width: 800
  height: 600
  visible: controller !== null && controller.opened

  onVisibleChanged: if (visible) Qt.callLater(view.focusKeys)

  FieldView {
    id: view

    anchors.fill: parent
    controller: surface.controller
  }
}
