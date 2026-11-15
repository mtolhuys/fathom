// The sounding line laid flat, for the row (layout = "row"): it runs under the
// cards and above the map, from the surface ("now") on the left to two hours
// and more on the right, the same way the row's cards step off to the right as
// they get older. Every window shown is a mark above the line at its depth,
// and the lead runs out along the line to the selection's depth. A click or a
// drag along the line picks the window nearest that depth, as on the upright
// line.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons // qmllint disable import
import "Depth.js" as Depth
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: gauge

  property var controller: null
  required property var theme
  property real unit: 1
  property real textUnit: unit
  // The selection's depth, animated by FieldView as the camera moves.
  property real leadDepth: 0

  readonly property real lineStart: 22 * textUnit
  readonly property real lineEnd: width - 14 * textUnit
  // Leaves room under the line for the tick labels.
  readonly property real lineY: height - 26 * textUnit
  readonly property real markSize: 6 * unit
  readonly property real markStep: markSize + 2 * unit
  readonly property real marksBottom: lineY - 8 * unit
  readonly property var shown: {
    const list = []
    const controller = gauge.controller
    if (!controller) return list
    for (let i = 0; i < controller.order.length; i++) list.push(controller.field[controller.order[i]])
    return list
  }
  // As many marks per column as fit above the line, leaving room for a "+N".
  readonly property int maxRows: Math.max(1, Math.floor((marksBottom - 12 * textUnit) / markStep))
  readonly property var marks: {
    const depths = []
    for (let i = 0; i < shown.length; i++) depths.push(shown[i] ? shown[i].depth : 0)
    return Layout.soundingMarks(depths, lineStart, lineEnd, markSize * 1.3, maxRows)
  }

  function pick(x, y) {
    if (!gauge.controller || !gauge.marks.length) return
    const row = Math.max(0, Math.round((gauge.marksBottom - gauge.markSize / 2 - y) / gauge.markStep))
    const at = Layout.nearestMark(gauge.marks, x, row)
    const entry = at >= 0 ? gauge.shown[at] : null
    if (entry) gauge.controller.jumpTo(entry.index)
  }

  // The surface.
  Text {
    x: gauge.lineStart - width - 6 * gauge.unit
    y: gauge.lineY - height / 2
    color: gauge.theme.textFaint
    font.family: Commons.Style.font.family
    font.pixelSize: 14 * gauge.textUnit
    textFormat: Text.PlainText
    text: "≈"
  }

  // The line itself, and a mark per fathom with the time it stands for.
  Rectangle {
    x: gauge.lineStart
    y: gauge.lineY
    width: gauge.lineEnd - gauge.lineStart
    height: 1
    color: gauge.theme.line
  }

  Repeater {
    model: Depth.MAX_DEPTH + 1

    delegate: Item {
      id: tick

      required property int index

      x: Layout.soundingY(index, gauge.lineStart, gauge.lineEnd)
      y: gauge.lineY

      Rectangle {
        x: -width / 2
        width: 1
        height: (tick.index % 2 === 0 ? 9 : 5) * gauge.unit
        color: gauge.theme.tick
      }

      Text {
        x: -width / 2
        y: 11 * gauge.unit
        color: gauge.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 10 * gauge.textUnit
        textFormat: Text.PlainText
        text: Field.depthMarkLabel(tick.index)
      }
    }
  }

  // The windows.
  Repeater {
    model: gauge.marks

    delegate: Rectangle {
      id: mark

      required property var modelData
      required property int index

      readonly property var entry: gauge.shown[index] || null
      readonly property bool selected: gauge.controller !== null && entry !== null && entry.index === gauge.controller.selectedIndex

      x: modelData.y - width / 2
      y: gauge.marksBottom - height - modelData.column * gauge.markStep
      width: gauge.markSize
      height: width
      radius: width / 2
      visible: !modelData.hidden
      color: selected ? gauge.theme.accent : (entry && entry.estimated ? "transparent" : gauge.theme.mark)
      border.width: entry && entry.estimated && !selected ? 1 : 0
      border.color: gauge.theme.markBorder

      // More windows at this depth than the column can show.
      Text {
        anchors.bottom: parent.top
        anchors.bottomMargin: 2 * gauge.unit
        anchors.horizontalCenter: parent.horizontalCenter
        visible: mark.modelData.more > 0
        color: gauge.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 9 * gauge.textUnit
        textFormat: Text.PlainText
        text: "+" + mark.modelData.more
      }
    }
  }

  // The sounding lead, run out along the line to the selection's depth.
  Rectangle {
    x: gauge.lineStart
    y: gauge.lineY - height / 2
    width: Math.max(0, Layout.soundingY(gauge.leadDepth, gauge.lineStart, gauge.lineEnd) - gauge.lineStart)
    height: 1.5
    color: gauge.theme.accent
    visible: gauge.controller !== null && gauge.controller.selectedIndex >= 0
  }

  Rectangle {
    x: Layout.soundingY(gauge.leadDepth, gauge.lineStart, gauge.lineEnd) - width / 2
    y: gauge.lineY - height / 2
    width: 9 * gauge.unit
    height: width
    rotation: 45
    radius: 1.5
    color: gauge.theme.accent
    visible: gauge.controller !== null && gauge.controller.selectedIndex >= 0
  }

  // Click or drag along the line to pick a window by how long ago it was used.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => gauge.pick(mouse.x, mouse.y)
    onPositionChanged: mouse => {
      if (pressed) gauge.pick(mouse.x, mouse.y)
    }
  }
}
