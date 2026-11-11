// One window in the Deep: a card of the monitor's shape, placed by its slot
// relative to the camera (Layout.deepPlane), with a header strip (icon,
// title, age) and the live capture fitted inside. Fog by how long ago the
// window was used (Depth.fogForDepth) fades the capture into the backdrop,
// not the header, so every card stays readable however deep it sits. Colors
// come from the theme through FieldView (Palette.js).

import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons as Commons // qmllint disable import
import "Depth.js" as Depth
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: card

  // The row of the controller's planeModel, which mirrors its field.
  required property int index

  // Set by FieldView.
  property var controller: null
  required property var theme
  required property var appearance
  property var stage: null
  property real unit: 1
  property real textUnit: unit

  readonly property var entry: controller && index >= 0 && index < controller.field.length ? controller.field[index] : null
  readonly property var toplevel: entry ? entry.toplevel : null
  readonly property int slot: controller && index >= 0 && index < controller.slots.length ? controller.slots[index] : -1
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
    && r > -1.2 && r < Layout.LIVE_STEPS && !!toplevel && !!toplevel.wayland

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

  // Outside the visible band [-1.5, Layout.VISIBLE_STEPS + 1] the shared
  // offscreen shape replaces Layout.deepPlane, with no object allocated in
  // any branch. The swap is invisible because deepPlane's opacity is exactly
  // 0 at both band edges: the passed branch fades out within PASSED_FADE =
  // 0.6, so opacity is 0 at r = -1.5, and the deep branch's opacity =
  // clamp(VISIBLE_STEPS + 1 - r) hits 0 at r = VISIBLE_STEPS + 1. Planes out
  // of band stop driving their x/y/width/height/z/opacity/pad/radius/fog
  // bindings every animation frame, and since the same object reference
  // comes back each time, the var change signal stays quiet.
  readonly property var geometry: !stage || r < -1.5 || r > Layout.VISIBLE_STEPS + 1
    ? Layout.OFFSCREEN_GEOMETRY
    : Layout.deepPlane(stage, r)
  readonly property real depthScale: Math.min(1, geometry.scale)
  readonly property real headerHeight: Math.max(18 * textUnit, Math.min(30 * textUnit, height * 0.1))
  readonly property real pad: Math.max(3, 8 * unit * depthScale)
  // The shell's corner radius on the front card, shrinking with depth like
  // the card itself (screen pixels: zero stays zero).
  readonly property real radius: card.appearance.cornerRadius * depthScale
  readonly property real fog: entry
    ? theme.fogStrength * Math.min(0.7, Math.max(0, Math.min(1, r)) * (0.12 + Depth.fogForDepth(entry.depth) * 0.75) + 0.05 * Math.max(0, r - 1))
    : 0
  readonly property string titleText: toplevel && toplevel.title ? String(toplevel.title) : (entry ? entry.title : "")
  // Outside its monitor's area (a scrolling layout parked it beside the
  // screen): Hyprland does not render it, so no live frame will come.
  readonly property bool parked: controller !== null && entry !== null
    && Layout.outside(controller.geometries[index], controller.monitorInfo[entry.monitorName])
  // The last frame seen of this window while the field was open, if any.
  readonly property var snapshot: controller && entry ? (controller.snapshots[entry.address] || null) : null
  readonly property bool showsSnapshot: !capture.hasContent && snapshot !== null

  // Keeps the frame a moment after it arrives (the first one can be partial).
  // The grab is of what the card draws (the clipped frame); the fog and the
  // badge sit outside it. A grab renders the frame's own items whatever the
  // card's opacity, so the window you were on, captured one step behind the
  // camera where its card has faded out, keeps a frame too: the map shows it.
  function takeSnapshot() {
    if (!capture.hasContent || !controller || !controller.opened || !entry || !capturing) return
    if (!controller.wantsSnapshot(entry.address)) return
    const width = Math.max(1, Math.min(controller.snapshotWidth, capture.sourceSize.width))
    const height = Math.max(1, Math.round(width * frame.height / Math.max(1, frame.width)))
    const address = entry.address
    const target = controller
    frame.grabToImage(result => target.keepSnapshot(address, result), Qt.size(width, height))
  }

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

  onHasContentChanged: {
    if (!hasContent || !controller) return
    controller.noteFirstContent()
    snapshotTimer.restart()
  }

  Timer {
    id: snapshotTimer

    interval: 400
    onTriggered: card.takeSnapshot()
  }

  RectangularShadow {
    anchors.fill: parent
    radius: card.radius
    blur: (card.selected ? 40 : 26) * card.unit
    spread: card.selected ? 3 * card.unit : 0
    offset: card.selected ? Qt.vector2d(0, 0) : Qt.vector2d(0, 8 * card.unit * card.depthScale)
    color: card.selected ? card.theme.glow : card.theme.shadow
  }

  // Glass on a dark theme, paper on a light one: a little lighter at the
  // top, like light from the surface.
  Rectangle {
    objectName: "cardSurface"
    anchors.fill: parent
    radius: card.radius
    border.width: card.appearance.borderWidth
    border.color: card.hovered ? card.theme.cardBorderHover : card.theme.cardBorder
    gradient: Gradient {
      GradientStop { position: 0; color: card.selected ? card.theme.cardSelectedTop : card.theme.cardTop }
      GradientStop { position: 1; color: card.selected ? card.theme.cardSelectedBottom : card.theme.cardBottom }
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
      color: card.theme.text
      font.family: Commons.Style.font.family
      font.pixelSize: Math.max(10, Math.min(13 * card.textUnit, card.headerHeight * 0.46))
      font.bold: card.selected
      textFormat: Text.PlainText
      text: card.titleText || (card.entry ? card.entry.appName : "")
    }

    Text {
      id: headerAge

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: card.theme.textSoft
      font.family: Commons.Style.font.family
      font.pixelSize: Math.max(9, Math.min(11 * card.textUnit, card.headerHeight * 0.4))
      textFormat: Text.PlainText
      text: card.entry ? Field.ageShort(card.entry.seconds, card.entry.active, card.entry.estimated) : ""
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
      objectName: "previewFrame"

      x: preview.fitted.x
      y: preview.fitted.y
      width: preview.fitted.width
      height: preview.fitted.height
      radius: Math.max(0, card.radius * 0.55)
      color: card.theme.bed

      // Until a frame arrives, and for windows Hyprland does not render (a
      // scrolling layout parks them beside the screen), the last frame seen,
      // or else the app's own face.
      Image {
        anchors.fill: parent
        visible: card.showsSnapshot
        source: card.snapshot ? card.snapshot.url : ""
        fillMode: Image.PreserveAspectCrop
        cache: false
        smooth: true
        mipmap: true
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - 20 * card.unit
        spacing: 8 * card.unit
        visible: !capture.hasContent && !card.showsSnapshot

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
          color: card.theme.textSoft
          font.family: Commons.Style.font.family
          font.pixelSize: Math.max(10, Math.min(13 * card.textUnit, frame.height * 0.05))
          textFormat: Text.PlainText
          text: card.entry ? card.entry.appName : ""
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          visible: card.parked && frame.height > 130 * card.unit
          color: card.theme.textFaint
          font.family: Commons.Style.font.family
          font.pixelSize: Math.max(9, Math.min(11 * card.textUnit, frame.height * 0.042))
          textFormat: Text.PlainText
          text: "off screen \u00b7 no live preview"
        }
      }

      ScreencopyView {
        id: capture

        anchors.fill: parent
        captureSource: card.capturing ? card.toplevel.wayland : null
        live: card.capturing
        paintCursor: false
      }
    }

    // Depth: older and further windows sink into the backdrop.
    Rectangle {
      anchors.fill: frame
      radius: frame.radius
      color: card.theme.fog
      opacity: card.fog
      visible: opacity > 0.005
    }

    Rectangle {
      anchors.fill: frame
      radius: frame.radius
      color: "transparent"
      border.width: card.appearance.borderWidth
      border.color: card.theme.frameEdge
    }

    // A still frame says so, and how old it is.
    Rectangle {
      anchors.left: frame.left
      anchors.bottom: frame.bottom
      anchors.margins: 8 * card.unit * card.depthScale + 2
      visible: card.showsSnapshot && frame.height > 70 * card.unit
      width: badgeText.implicitWidth + 14 * card.unit
      height: badgeText.implicitHeight + 6 * card.unit
      radius: Math.min(card.appearance.cornerRadius, height / 2)
      color: card.theme.panel
      border.width: card.appearance.borderWidth
      border.color: card.theme.panelBorder

      Text {
        id: badgeText

        anchors.centerIn: parent
        color: card.theme.textSoft
        font.family: Commons.Style.font.family
        font.pixelSize: Math.max(9, 11 * card.textUnit * Math.max(0.8, card.depthScale))
        textFormat: Text.PlainText
        text: {
          const snapshot = card.snapshot
          if (!snapshot || !card.controller) return ""
          const seconds = Math.max(0, (card.controller.openedAtMs - snapshot.takenAt) / 1000)
          return "last seen " + Field.ageLabel(seconds, false, false)
        }
      }
    }
  }

  // The selection's ring sits just outside the card and follows its corner
  // (square around a square card), always heavier than the idle border; an
  // urgent window's outline is never lighter than it.
  Rectangle {
    anchors.fill: parent
    objectName: "selectionOutline"
    anchors.margins: card.selected ? -3 * card.unit : 0
    radius: card.selected && card.radius > 0 ? card.radius + 3 * card.unit : card.radius
    color: "transparent"
    visible: card.selected || card.urgent
    border.width: card.selected ? Math.max(card.appearance.borderWidth + 1, 2.5 * card.unit)
      : Math.max(card.appearance.borderWidth, 1.5)
    border.color: card.selected ? card.theme.accent : card.theme.urgent
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
    color: card.theme.urgent
    border.width: 2
    border.color: card.theme.background
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
