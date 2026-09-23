// Contents of the field: backdrop, the Deep (the selection in front, older
// windows receding behind it), the caption, the map of every workspace, the
// filter, and the key, wheel and pointer handling. Kept apart from the
// layer-shell window so tests can host it in a plain item.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons // qmllint disable import
import "Layout.js" as Layout
import "Field.js" as Field
import "Focus.js" as Focus

Item {
  id: view

  property var controller: null
  readonly property alias probe: probe
  readonly property int planeCount: planes.count
  readonly property alias map: map
  readonly property alias gauge: gauge

  // One unit is a pixel on a 1000 px tall screen; everything scales with it.
  readonly property real unit: Math.max(0.75, Math.min(1.6, height / 1000))
  // Text also follows Omarchy's text size (`omarchy display text size`).
  readonly property real textUnit: unit * Math.max(0.85, Math.min(1.6, Number(Style.fontScale) || 1))
  readonly property real margin: Math.max(16, width * 0.022)
  readonly property var entry: controller ? controller.selectedEntry : null
  readonly property bool holding: controller !== null && controller.mode === "hold"
  readonly property bool filtering: controller !== null && controller.filterText.length > 0
  readonly property bool nothingShown: controller !== null && controller.opened && controller.order.length === 0

  function planeAt(index) {
    return planes.itemAt(index)
  }

  function focusKeys() {
    keyCatcher.forceActiveFocus()
  }

  // Hover selects only after the pointer really moves: when the field opens
  // (or the Deep slides) under a resting pointer, nothing changes.
  property bool pointerPrimed: false
  property point pointerAt: Qt.point(0, 0)

  function pointerMoved(item, x, y) {
    const point = item.mapToItem(view, x, y)
    if (!view.pointerPrimed) {
      view.pointerPrimed = true
      view.pointerAt = point
      return false
    }
    if (Math.abs(point.x - view.pointerAt.x) < 3 && Math.abs(point.y - view.pointerAt.y) < 3) return false
    view.pointerAt = point
    if (view.controller) view.controller.noteInput()
    return true
  }

  Connections {
    target: view.controller
    function onOpenedChanged() {
      view.pointerPrimed = false
    }
  }

  opacity: controller && controller.revealed ? 1 : 0

  Behavior on opacity {
    enabled: view.controller !== null && view.controller.opened
    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------ backdrop

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.alpha(Color.background, 0.66) }
      GradientStop { position: 0.55; color: Qt.alpha(Color.background, 0.78) }
      GradientStop { position: 1.0; color: Qt.alpha(Color.background, 0.9) }
    }
  }

  // Light from the surface, fading as the selection goes deeper; the whole
  // scene darkens with it. Diving into older windows feels like diving.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height * 0.45
    opacity: 1 - view.sceneDepth / 8
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.alpha(Color.foreground, 0.06) }
      GradientStop { position: 1.0; color: Qt.alpha(Color.foreground, 0) }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
    opacity: view.sceneDepth * 0.035
    visible: opacity > 0.005
  }

  // A click on empty space closes the field without focusing anything; any
  // pointer movement keeps a held field alive.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (view.controller) view.controller.cancel()
    onPositionChanged: mouse => view.pointerMoved(view, mouse.x, mouse.y)
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      if (view.controller)
        view.controller.wheel(event.angleDelta.y, event.pixelDelta.y, event.angleDelta.x, event.pixelDelta.x)
    }
  }

  // ------------------------------------------------------------ the Deep

  readonly property real mapHeight: Math.max(96, Math.min(height * 0.2, 210 * unit))
  readonly property real captionHeight: 62 * unit
  readonly property real deepTop: margin + 44 * unit
  // The sounding line takes a column on the left when there is room for it.
  readonly property real gaugeWidth: width >= 1000 ? 112 * textUnit : 0
  // Cards take the shape of this screen, which is the focused monitor.
  readonly property var stage: Layout.deepStage(width, height, deepTop,
    mapHeight + captionHeight + margin + 30 * unit, width / Math.max(1, height), margin + gaugeWidth)

  // How deep the selection sits, animated: the lead follows it down the
  // sounding line and the light fades with it.
  readonly property real selectedDepth: entry ? Math.min(8, Math.max(0, entry.depth)) : 0
  property real sceneDepth: selectedDepth

  Behavior on sceneDepth {
    enabled: view.controller !== null && view.controller.cameraAnimated
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  Item {
    id: deep

    anchors.fill: parent

    Repeater {
      id: planes

      model: view.controller ? view.controller.field : []

      delegate: WindowPlane {
        controller: view.controller
        stage: view.stage
        unit: view.unit
        textUnit: view.textUnit
      }
    }
  }

  // ------------------------------------------------------------ the sounding line

  SoundingLine {
    id: gauge

    x: view.margin
    y: view.deepTop
    width: view.gaugeWidth
    height: view.stage.frontY + view.stage.frontHeight / 2 - view.deepTop
    visible: view.gaugeWidth > 0
    controller: view.controller
    unit: view.unit
    textUnit: view.textUnit
    leadDepth: view.sceneDepth
  }

  // ------------------------------------------------------------ caption

  Item {
    id: caption

    x: view.stage.frontX - view.stage.frontWidth / 2
    y: view.height - view.margin - view.mapHeight - view.captionHeight - 14 * view.unit
    width: view.width - x - view.margin
    height: view.captionHeight
    visible: view.entry !== null

    // The caption names the selection; a click on it focuses it.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (view.controller && view.controller.selectedEntry) view.controller.commit()
    }

    AppIcon {
      id: captionIcon

      anchors.verticalCenter: parent.verticalCenter
      size: 38 * view.unit
      source: view.entry ? view.entry.icon : ""
      name: view.entry ? view.entry.appName : ""
    }

    Column {
      anchors.left: captionIcon.right
      anchors.leftMargin: 14 * view.unit
      anchors.right: counter.left
      anchors.rightMargin: 20 * view.unit
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3 * view.unit

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: 20 * view.textUnit
        font.bold: true
        text: {
          const toplevel = view.entry ? view.entry.toplevel : null
          return toplevel && toplevel.title ? String(toplevel.title) : (view.entry ? (view.entry.title || view.entry.appName) : "")
        }
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: 13 * view.textUnit
        text: {
          const entry = view.entry
          if (!entry) return ""
          const parts = []
          if (entry.appName) parts.push(entry.appName)
          const workspace = Field.workspaceLabel(entry.workspaceName, entry.workspaceId)
          parts.push(Field.isSpecialName(entry.workspaceName) ? "scratchpad " + workspace : "workspace " + workspace)
          const tab = Focus.groupIndexFor(entry.address, entry.grouped)
          if (tab > 0 && entry.grouped.length > 1) parts.push("tab " + tab + " of " + entry.grouped.length)
          parts.push(Field.ageLabel(entry.seconds, entry.active, entry.estimated))
          const reading = Field.fathomLabel(entry.depth, entry.active, entry.estimated)
          if (reading) parts.push(reading)
          if (entry.toplevel && entry.toplevel.urgent) parts.push("wants attention")
          return parts.join("  ·  ")
        }
      }
    }

    Text {
      id: counter

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: 13 * view.textUnit
      text: view.controller && view.controller.selectedSlot >= 0
        ? (view.controller.selectedSlot + 1) + " / " + view.controller.order.length : ""
    }
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -view.mapHeight / 2
    spacing: 8 * view.unit
    visible: view.nothingShown

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: 20 * view.textUnit
      text: "No window matches “" + (view.controller ? view.controller.filterText : "") + "”"
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: 13 * view.textUnit
      text: "Backspace to edit  ·  Esc to clear"
    }
  }

  // ------------------------------------------------------------ summary

  Text {
    x: view.margin
    y: view.margin + 8 * view.unit
    visible: !filterBar.visible && view.controller !== null
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: 13 * view.textUnit
    text: {
      const controller = view.controller
      if (!controller) return ""
      const windows = controller.field.length
      const workspaces = controller.groups.filter(group => group.entries.length > 0).length
      return windows + (windows === 1 ? " window" : " windows") + "  \u00b7  "
        + workspaces + (workspaces === 1 ? " workspace" : " workspaces")
    }
  }

  // ------------------------------------------------------------ filter

  Rectangle {
    id: filterBar

    x: view.margin
    y: view.margin
    height: 34 * view.unit
    width: filterRow.implicitWidth + 28 * view.unit
    radius: height / 2
    color: Qt.alpha(Color.background, 0.85)
    border.width: 1
    border.color: view.filtering ? Qt.alpha(Color.accent, 0.7) : Qt.alpha(Color.foreground, 0.14)
    visible: view.filtering || (view.controller !== null && view.controller.mode === "browse")

    // Not empty space: a click here must not close the field.
    MouseArea {
      anchors.fill: parent
      onClicked: view.focusKeys()
    }

    Row {
      id: filterRow

      anchors.verticalCenter: parent.verticalCenter
      x: 14 * view.unit
      spacing: 8 * view.unit

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: view.filtering ? Color.accent : Color.muted
        font.family: Style.font.family
        font.pixelSize: 14 * view.textUnit
        text: "/"
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: view.filtering ? Color.foreground : Color.muted
        font.family: Style.font.family
        font.pixelSize: 14 * view.textUnit
        text: view.filtering ? view.controller.filterText : "type to filter"
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: view.filtering
        width: 2
        height: 16 * view.unit
        color: Color.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: view.filtering
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: 12 * view.textUnit
        text: view.controller ? view.controller.order.length + " of " + view.controller.field.length : ""
      }
    }
  }

  // ------------------------------------------------------------ hints

  Row {
    id: hints

    anchors.right: parent.right
    anchors.rightMargin: view.margin
    y: view.height - view.margin - view.mapHeight - 20 * view.unit
    spacing: 16 * view.unit
    opacity: 0.8

    Repeater {
      model: view.holding
        ? [["Tab", "deeper"], ["↑↓", "dive"], ["←→", "workspace"], ["Space", "keep open"], ["Esc", "cancel"]]
        : [["↑↓", "dive"], ["←→", "workspace"], ["1–9", "go to"], ["Enter", "focus"], ["Esc", view.filtering ? "clear" : "close"]]

      delegate: Row {
        id: hint

        required property var modelData

        spacing: 5 * view.unit

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(height, keyText.implicitWidth + 10 * view.unit)
          height: 18 * view.unit
          radius: 4 * view.unit
          color: Qt.alpha(Color.foreground, 0.08)
          border.width: 1
          border.color: Qt.alpha(Color.foreground, 0.2)

          Text {
            id: keyText

            anchors.centerIn: parent
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: 11 * view.textUnit
            text: hint.modelData[0]
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: 11 * view.textUnit
          text: hint.modelData[1]
        }
      }
    }
  }

  // Not empty space: a click on the hints must not close the field.
  MouseArea {
    x: hints.x
    y: hints.y
    width: hints.width
    height: hints.height
    onClicked: view.focusKeys()
  }

  // ------------------------------------------------------------ the map

  WorkspaceMap {
    id: map

    x: view.margin
    width: view.width - view.margin * 2
    height: view.mapHeight
    y: view.height - view.margin - height
    controller: view.controller
    view: view
    unit: view.unit
    textUnit: view.textUnit
  }

  // ------------------------------------------------------------ keys

  Item {
    id: keyCatcher

    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      if (view.controller)
        event.accepted = view.controller.handleKey(event.key, event.modifiers, event.text)
    }

    // The Alt press predates this surface, but its release arrives here once
    // the exclusive keyboard grab is in place.
    Keys.onReleased: event => {
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
