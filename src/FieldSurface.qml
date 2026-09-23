// The layer-shell window that carries the field. One surface, on the focused
// monitor only: a surface per output would duplicate every capture.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: surface

  property var controller: null
  readonly property alias view: view

  visible: controller !== null && controller.opened
  screen: controller ? controller.targetScreen : null
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "fathom"
  WlrLayershell.layer: WlrLayer.Overlay
  // Exclusive only while open. Escape, a click, the Alt release and the
  // watchdog all close the field, so the grab cannot outlive a switch.
  WlrLayershell.keyboardFocus: surface.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onVisibleChanged: if (visible) Qt.callLater(view.focusKeys)

  FieldView {
    id: view

    anchors.fill: parent
    controller: surface.controller
  }
}
