// Contents of the field: scrim, planes, caption, keys and the frame probe.
// Kept apart from the layer-shell window so tests can host it in a plain item.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons // qmllint disable import

Item {
  id: view

  property var controller: null
  readonly property alias probe: probe
  readonly property int planeCount: planes.count

  function planeAt(index) {
    return planes.itemAt(index)
  }

  function focusKeys() {
    keyCatcher.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
  }

  // A click on empty space closes the field without focusing anything.
  MouseArea {
    anchors.fill: parent
    onClicked: if (view.controller) view.controller.cancel()
  }

  Item {
    id: stage

    anchors.fill: parent

    // Phase 0 layout (docs/SPEC.md): the plane at the camera is centered in
    // a box of 56% of the screen, deeper planes recede toward a vanishing
    // point beyond its top-right corner. Phase 1 replaces this with the
    // tuned perspective layout.
    readonly property real frontWidth: width * 0.56
    readonly property real frontHeight: height * 0.56
    readonly property real vanishX: width * 0.92
    readonly property real vanishY: height * 0.1
    readonly property int planeTotal: view.controller ? Math.max(1, view.controller.field.length) : 1
    readonly property real nudgeX: Math.min(width * 0.008, width * 0.2 / Math.max(1, planeTotal - 1))
    readonly property real nudgeY: nudgeX * 0.6

    Repeater {
      id: planes

      model: view.controller ? view.controller.field : []

      delegate: WindowPlane {
        controller: view.controller
        centerX: stage.width / 2
        centerY: stage.height / 2
        vanishX: stage.vanishX
        vanishY: stage.vanishY
        frontWidth: stage.frontWidth
        frontHeight: stage.frontHeight
        nudgeX: stage.nudgeX
        nudgeY: stage.nudgeY
      }
    }
  }

  Text {
    readonly property var entry: view.controller ? view.controller.selectedEntry : null

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: parent.height * 0.06
    width: parent.width * 0.6
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    color: Color.foreground
    font.pixelSize: 16
    text: entry
      ? (view.controller.selectedIndex + 1) + " / " + view.controller.field.length + "   "
        + (entry.appId ? entry.appId + "  |  " : "") + entry.title
      : ""
  }

  Item {
    id: keyCatcher

    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      const controller = view.controller
      if (!controller) return
      controller.noteInput()
      const shifted = (event.modifiers & Qt.ShiftModifier) !== 0
      if (event.key === Qt.Key_Tab && !shifted) {
        controller.step(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Tab) {
        controller.step(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        controller.cancel()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        controller.commit()
        event.accepted = true
      }
    }

    // The Alt press predates this surface, but its release arrives here once
    // the exclusive keyboard grab is in place.
    Keys.onReleased: function(event) {
      if (event.key === Qt.Key_Alt && !event.isAutoRepeat && view.controller) {
        view.controller.altReleased()
        event.accepted = true
      }
    }
  }

  FrameProbe {
    id: probe

    running: view.controller !== null && view.controller.opened && view.controller.probeEnabled
  }
}
