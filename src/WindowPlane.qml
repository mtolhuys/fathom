// One window in the field: a live capture placed by its depth relative to
// the camera. Phase 0 applies depth to scale and opacity only.

import QtQuick
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import "Depth.js" as Depth

Item {
  id: plane

  required property var modelData
  required property int index

  // Set by Fathom.qml.
  property var controller: null
  property real centerX: 0
  property real centerY: 0
  property real vanishX: 0
  property real vanishY: 0
  property real frontWidth: 0
  property real frontHeight: 0
  property real nudgeX: 0
  property real nudgeY: 0

  readonly property var entry: modelData
  readonly property var toplevel: entry ? entry.toplevel : null
  readonly property bool selected: controller !== null && index === controller.selectedIndex
  readonly property real relativeIndex: controller ? index - controller.cameraIndex : 0
  readonly property real relativeDepth: controller && entry ? entry.depth - controller.cameraDepth : 0
  readonly property bool hasContent: capture.hasContent
  readonly property size sourceSize: capture.sourceSize

  // Once a frame arrived its real size wins; until then Hyprland's reported
  // window size, then a neutral 16:10.
  readonly property real aspect: {
    if (capture.hasContent && capture.sourceSize.height > 0)
      return capture.sourceSize.width / capture.sourceSize.height
    const ipc = plane.toplevel ? plane.toplevel.lastIpcObject : null
    const size = ipc && ipc.size ? ipc.size : null
    if (size && size.length >= 2 && Number(size[0]) > 0 && Number(size[1]) > 0)
      return Math.max(0.3, Math.min(5, Number(size[0]) / Number(size[1])))
    return 1.6
  }

  readonly property var placement: Depth.planeCenter(centerX, centerY, vanishX, vanishY,
    scale, relativeIndex, nudgeX, nudgeY)

  width: Math.max(1, Math.min(frontWidth, frontHeight * aspect))
  height: Math.max(1, width / aspect)
  // Scaling happens around the item's center, so placing the center is enough.
  x: placement.x - width / 2
  y: placement.y - height / 2
  z: 1000 - index
  scale: Depth.planeScale(relativeDepth, relativeIndex)
  opacity: Depth.planeOpacity(relativeDepth, relativeIndex)
  visible: opacity > 0.005

  onHasContentChanged: if (hasContent && controller) controller.noteFirstContent()

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
  }

  ScreencopyView {
    id: capture

    anchors.fill: parent
    // Captures exist only while the field is open.
    captureSource: plane.controller && plane.controller.opened && plane.toplevel
      ? plane.toplevel.wayland : null
    live: plane.controller !== null && plane.controller.opened
    paintCursor: false
  }

  Text {
    anchors.centerIn: parent
    width: parent.width - 16
    visible: !capture.hasContent
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    color: Color.foreground
    text: plane.entry ? (plane.entry.appId || plane.entry.title || "window") : ""
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -3
    visible: plane.selected
    color: "transparent"
    radius: 4
    border.width: 2
    border.color: Color.accent
  }

  // A MouseArea (not a TapHandler) so the click stops here and never reaches
  // the dismiss area behind the field.
  MouseArea {
    anchors.fill: parent
    onClicked: if (plane.controller) plane.controller.selectAndCommit(plane.index)
  }
}
