// One window in the Deep: a card of the monitor's shape, placed by its slot
// relative to the camera (Layout.deepPlane), with a header strip (icon,
// title, age) and the live capture fitted inside. Fog by how long ago the
// window was used (Depth.fogForDepth) darkens the capture, not the header,
// so every card stays readable however deep it sits.

import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons // qmllint disable import
import "Depth.js" as Depth
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: card

  required property var modelData
  required property int index

  // Set by FieldView.
  property var controller: null
  property var stage: null
  property real unit: 1

  readonly property var entry: modelData
  readonly property var toplevel: entry ? entry.toplevel : null
  readonly property int slot: controller && index < controller.slots.length ? controller.slots[index] : -1
  readonly property bool inField: slot >= 0
  readonly property real r: inField && controller ? slot - controller.cameraSlot : 0
  readonly property bool selected: controller !== null && index === controller.selectedIndex
  readonly property bool hovered: mouse.containsMouse
  readonly property bool urgent: !!(toplevel && toplevel.urgent)
  readonly property bool hasContent: capture.hasContent
  readonly property size sourceSize: capture.sourceSize
  // Captures run only for cards near the camera; the rest of the field is
  // on the map, and capturing it would cost the compositor for nothing.
  readonly property bool capturing: controller !== null && controller.opened && inField
    && r > -1.2 && r < Layout.VISIBLE_STEPS + 0.5 && !!toplevel && !!toplevel.wayland

  // The window's own shape, for fitting it into the card: the frame's size
  // once one arrived, else Hyprland's reported size, else 16:10.
  readonly property real aspect: {
    if (capture.hasContent && capture.sourceSize.height > 0)
      return capture.sourceSize.width / capture.sourceSize.height
    const geometry = entry ? entry.geometry : null
    if (geometry && geometry.width > 0 && geometry.height > 0)
      return Math.max(0.3, Math.min(5, geometry.width / geometry.height))
    return 1.6
  }

  readonly property var geometry: stage ? Layout.deepPlane(stage, r) : ({ x: 0, y: 0, width: 1, height: 1, scale: 1, opacity: 0, z: 0 })
  readonly property real depthScale: Math.min(1, geometry.scale)
  readonly property real headerHeight: Math.max(18 * unit, Math.min(30 * unit, height * 0.1))
  readonly property real pad: Math.max(3, 8 * unit * depthScale)
  readonly property real radius: Math.max(4, 11 * unit * depthScale)
  readonly property real fog: entry
    ? Math.min(0.7, Math.max(0, Math.min(1, r)) * (0.12 + Depth.fogForDepth(entry.depth) * 0.75) + 0.05 * Math.max(0, r - 1))
    : 0
  readonly property string titleText: toplevel && toplevel.title ? String(toplevel.title) : (entry ? entry.title : "")

  x: geometry.x - geometry.width / 2
  y: geometry.y - geometry.height / 2
  width: geometry.width
  height: geometry.height
  z: geometry.z
  opacity: inField ? geometry.opacity : 0
  visible: opacity > 0.01

  Behavior on opacity {
    enabled: card.controller !== null && card.controller.cameraAnimated
    NumberAnimation { duration: 160 }
  }

  onHasContentChanged: if (hasContent && controller) controller.noteFirstContent()

  RectangularShadow {
    anchors.fill: parent
    radius: card.radius
    blur: (card.selected ? 40 : 26) * card.unit
    spread: card.selected ? 3 * card.unit : 0
    offset: card.selected ? Qt.vector2d(0, 0) : Qt.vector2d(0, 8 * card.unit * card.depthScale)
    color: card.selected ? Qt.alpha(Color.accent, 0.38) : Qt.rgba(0, 0, 0, 0.55)
  }

  // Glass: a little lighter at the top, like light from the surface.
  Rectangle {
    anchors.fill: parent
    radius: card.radius
    border.width: 1
    border.color: Qt.alpha(Color.foreground, card.hovered ? 0.3 : 0.11)
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.tint(Color.background, Qt.alpha(Color.foreground, card.selected ? 0.12 : 0.085)) }
      GradientStop { position: 1; color: Qt.tint(Color.background, Qt.alpha(Color.foreground, card.selected ? 0.06 : 0.035)) }
    }
  }

  // Header strip: icon, title, age. Stays readable at any depth.
  Item {
    id: header

    x: card.pad + 2 * card.unit
    width: card.width - x * 2
    height: card.headerHeight
    opacity: 1 - card.fog * 0.45

    AppIcon {
      id: headerIcon

      anchors.verticalCenter: parent.verticalCenter
      size: card.headerHeight * 0.6
      source: card.entry ? card.entry.icon : ""
      name: card.entry ? card.entry.appName : ""
    }

    Text {
      anchors.left: headerIcon.right
      anchors.leftMargin: 7 * card.unit
      anchors.right: headerAge.left
      anchors.rightMargin: 8 * card.unit
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Math.max(10, Math.min(13 * card.unit, card.headerHeight * 0.46))
      font.bold: card.selected
      text: card.titleText || (card.entry ? card.entry.appName : "")
    }

    Text {
      id: headerAge

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Math.max(9, Math.min(11 * card.unit, card.headerHeight * 0.4))
      text: card.entry ? Field.ageShort(card.entry.seconds, card.entry.active) : ""
    }
  }

  Item {
    id: preview

    x: card.pad
    y: card.headerHeight
    width: card.width - card.pad * 2
    height: card.height - card.headerHeight - card.pad

    readonly property var fitted: Layout.fit(width, height, card.aspect)

    ClippingRectangle {
      id: frame

      x: preview.fitted.x
      y: preview.fitted.y
      width: preview.fitted.width
      height: preview.fitted.height
      radius: Math.max(2, card.radius * 0.55)
      color: Qt.tint(Color.background, Qt.alpha(Color.foreground, 0.04))

      // Until a frame arrives, and for windows Hyprland does not render (a
      // scrolling layout parks them beside the screen), the app's own face.
      Column {
        anchors.centerIn: parent
        width: parent.width - 20 * card.unit
        spacing: 8 * card.unit
        visible: !capture.hasContent

        AppIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          size: Math.max(16, Math.min(88 * card.unit, frame.height * 0.3))
          source: card.entry ? card.entry.icon : ""
          name: card.entry ? card.entry.appName : ""
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          visible: frame.height > 110 * card.unit
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Math.max(10, Math.min(13 * card.unit, frame.height * 0.05))
          text: card.entry ? card.entry.appName : ""
        }
      }

      ScreencopyView {
        id: capture

        anchors.fill: parent
        captureSource: card.capturing ? card.toplevel.wayland : null
        live: card.capturing
        paintCursor: false
      }

      // Depth: older and further windows sink into the backdrop.
      Rectangle {
        anchors.fill: parent
        color: Color.background
        opacity: card.fog
        visible: opacity > 0.005
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: card.selected ? -3 * card.unit : 0
    radius: card.radius + (card.selected ? 3 * card.unit : 0)
    color: "transparent"
    visible: card.selected || card.urgent
    border.width: card.selected ? Math.max(2, 2.5 * card.unit) : 1.5
    border.color: card.selected ? Color.accent : Color.urgent
  }

  // Wants attention (Hyprland's urgent flag).
  Rectangle {
    visible: card.urgent
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: -5 * card.unit
    width: 12 * card.unit
    height: width
    radius: width / 2
    color: Color.urgent
    border.width: 2
    border.color: Color.background
  }

  // A MouseArea (not a TapHandler) so the click stops here and never reaches
  // the dismiss area behind the field.
  MouseArea {
    id: mouse

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (card.controller) card.controller.selectAndCommit(card.index)
  }
}
