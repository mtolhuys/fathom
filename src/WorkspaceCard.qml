// One workspace on the map: its name, how many windows it holds, whether it
// is on screen, and a minimap of its windows at their real positions (each
// with its app icon). Hovering a window selects it; a click focuses it; a
// click on the card focuses the workspace's most recent window.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons // qmllint disable import
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: card

  required property var modelData
  required property int index

  // Set by WorkspaceMap.
  property var controller: null
  property var view: null
  property real unit: 1
  property bool showMonitor: false

  readonly property var group: modelData
  readonly property real padding: 8 * unit
  readonly property real headerHeight: 20 * unit
  readonly property bool holdsSelection: controller !== null && group.entries.indexOf(controller.selectedIndex) !== -1
  readonly property var viewport: {
    const info = controller ? controller.monitorInfo : ({})
    if (info[group.monitor]) return info[group.monitor]
    for (const name in info) return info[name]
    return { x: 0, y: 0, width: 1920, height: 1080 }
  }
  readonly property var windows: {
    const list = []
    for (let i = 0; i < group.entries.length; i++) {
      const entry = controller ? controller.field[group.entries[i]] : null
      list.push(entry ? entry.geometry : null)
    }
    return list
  }
  readonly property var items: Layout.minimapItems(viewport, windows, box.width, box.height)
  readonly property int shownCount: {
    let count = 0
    const slots = controller ? controller.slots : []
    for (let i = 0; i < group.entries.length; i++) if (slots[group.entries[i]] >= 0) count++
    return count
  }

  // The tile that shows entry `entryIndex`, for the offscreen tests.
  function tileFor(entryIndex) {
    const at = card.group.entries.indexOf(entryIndex)
    return at >= 0 ? tiles.itemAt(at) : null
  }

  opacity: shownCount > 0 || group.entries.length === 0 ? 1 : 0.4

  Behavior on opacity { NumberAnimation { duration: 140 } }

  Rectangle {
    anchors.fill: parent
    radius: 10 * card.unit
    color: card.holdsSelection ? Qt.alpha(Color.accent, 0.08) : Qt.alpha(Color.foreground, 0.045)
    border.width: card.holdsSelection ? 1.5 : 1
    border.color: card.holdsSelection ? Qt.alpha(Color.accent, 0.7) : Qt.alpha(Color.foreground, 0.1)

    Behavior on border.color { ColorAnimation { duration: 140 } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (!card.controller) return
      const front = Field.groupFront(card.group, card.controller.order)
      if (front >= 0) card.controller.selectAndCommit(front)
    }
  }

  Item {
    id: header

    x: card.padding
    y: card.padding * 0.7
    width: card.width - card.padding * 2
    height: card.headerHeight

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6 * card.unit

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: card.holdsSelection ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: 14 * card.unit
        font.bold: true
        font.italic: card.group.special
        text: card.group.label
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: 11 * card.unit
        text: {
          const total = card.group.entries.length
          if (total === 0) return "empty"
          const count = card.shownCount < total ? card.shownCount + " of " + total : String(total)
          return card.width > 150 * card.unit ? count + (total === 1 ? " window" : " windows") : count
        }
      }
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 5 * card.unit

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: card.showMonitor && card.group.monitor.length > 0
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: 10 * card.unit
        text: card.group.monitor
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: card.group.onScreen
        width: 6 * card.unit
        height: width
        radius: width / 2
        color: Color.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: card.group.onScreen && card.width > 190 * card.unit
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: 10 * card.unit
        text: "on screen"
      }
    }
  }

  Item {
    id: box

    x: card.padding
    y: header.y + header.height + card.padding * 0.5
    width: card.width - card.padding * 2
    height: card.height - y - card.padding

    // The monitor's screen area; windows a scrolling layout parked beside
    // it show outside this outline.
    Rectangle {
      visible: card.items.viewport !== null
      x: card.items.viewport ? card.items.viewport.x : 0
      y: card.items.viewport ? card.items.viewport.y : 0
      width: card.items.viewport ? card.items.viewport.width : 0
      height: card.items.viewport ? card.items.viewport.height : 0
      radius: 4 * card.unit
      color: Qt.rgba(0, 0, 0, 0.22)
      border.width: 1
      border.color: Qt.alpha(Color.foreground, card.group.onScreen ? 0.28 : 0.12)
    }

    Text {
      anchors.centerIn: parent
      visible: card.group.entries.length === 0
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: 10 * card.unit
      text: "no windows"
    }

    Repeater {
      id: tiles

      model: card.group.entries

      delegate: Item {
        id: tile

        required property var modelData
        required property int index

        readonly property int entryIndex: modelData
        readonly property var entry: card.controller ? card.controller.field[entryIndex] : null
        readonly property var rect: card.items.rects[index] || ({ x: 0, y: 0, width: 0, height: 0 })
        readonly property bool shown: card.controller !== null && card.controller.slots[entryIndex] >= 0
        readonly property bool selected: card.controller !== null && card.controller.selectedIndex === entryIndex
        readonly property bool urgent: !!(entry && entry.toplevel && entry.toplevel.urgent)
        readonly property real inset: Math.min(1.5, rect.width / 6)
        // A scrolling layout parks windows beside the screen: shown, dimmer.
        readonly property bool parked: {
          const viewport = card.items.viewport
          if (!viewport) return false
          return rect.x >= viewport.x + viewport.width - 1 || rect.x + rect.width <= viewport.x + 1
            || rect.y >= viewport.y + viewport.height - 1 || rect.y + rect.height <= viewport.y + 1
        }

        x: rect.x + inset
        y: rect.y + inset
        width: Math.max(2, rect.width - inset * 2)
        height: Math.max(2, rect.height - inset * 2)
        z: selected ? 3 : (entry && entry.floating ? 2 : 1)
        opacity: shown ? (parked && !selected ? 0.62 : 1) : 0.22

        Behavior on opacity { NumberAnimation { duration: 140 } }

        Rectangle {
          anchors.fill: parent
          radius: Math.min(4 * card.unit, width / 4)
          color: tile.selected ? Qt.alpha(Color.accent, 0.36)
            : (hover.containsMouse ? Qt.alpha(Color.foreground, 0.2) : Qt.tint(Qt.rgba(0.12, 0.12, 0.12, 0.9), Qt.alpha(Color.foreground, 0.08)))
          border.width: tile.selected ? Math.max(1.5, 2 * card.unit) : 1
          border.color: tile.selected ? Color.accent
            : (tile.urgent ? Color.urgent
              : (tile.entry && tile.entry.active ? Qt.alpha(Color.foreground, 0.75) : Qt.alpha(Color.foreground, 0.24)))
        }

        AppIcon {
          anchors.centerIn: parent
          size: Math.min(26 * card.unit, Math.min(tile.width, tile.height) * 0.64)
          visible: size >= 7
          source: tile.entry ? tile.entry.icon : ""
          name: tile.entry ? tile.entry.appName : ""
        }

        MouseArea {
          id: hover

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: mouse => {
            if (tile.shown && card.view && card.view.pointerMoved(hover, mouse.x, mouse.y))
              card.controller.jumpTo(tile.entryIndex)
          }
          onClicked: if (card.controller) card.controller.selectAndCommit(tile.entryIndex)
        }
      }
    }
  }
}
