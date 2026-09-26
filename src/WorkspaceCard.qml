// One workspace on the map: its name, how many windows it holds, whether it
// is on screen, and a minimap of its windows at their real positions. Each
// window shows the last frame the field saw of it (the snapshot its card
// kept, so the map costs no capture of its own), else its app icon, and its
// title where the tile has room. Hovering a window selects it; a click
// focuses it; a click on the card focuses the workspace's most recent window.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Commons // qmllint disable import
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: card

  Appearance { id: appearance }

  required property var modelData
  required property int index

  // Set by WorkspaceMap.
  property var controller: null
  property var view: null
  required property var theme
  property real unit: 1
  property real textUnit: unit
  property bool showMonitor: false

  readonly property var group: modelData
  readonly property real padding: 8 * unit
  readonly property real headerHeight: 20 * textUnit
  readonly property bool holdsSelection: controller !== null && group.entries.indexOf(controller.selectedIndex) !== -1
  readonly property var viewport: {
    const info = controller ? controller.monitorInfo : ({})
    if (info[group.monitor]) return info[group.monitor]
    for (const name in info) return info[name]
    return { x: 0, y: 0, width: 1920, height: 1080 }
  }
  // Positions follow Hyprland's latest client list (see geometryOf).
  readonly property var windows: {
    const list = []
    for (let i = 0; i < group.entries.length; i++) {
      const entry = controller ? controller.field[group.entries[i]] : null
      list.push(controller ? controller.geometryOf(entry) : null)
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
    objectName: "workspaceSurface"
    anchors.fill: parent
    radius: appearance.cornerRadius
    color: card.holdsSelection ? card.theme.mapCardSelected : card.theme.mapCard
    border.width: appearance.borderWidth
    border.color: card.holdsSelection ? card.theme.mapCardSelectedBorder : card.theme.mapCardBorder

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
        color: card.holdsSelection ? card.theme.accentText : card.theme.text
        font.family: Style.font.family
        font.pixelSize: 14 * card.textUnit
        font.bold: true
        font.italic: card.group.special
        textFormat: Text.PlainText
        text: card.group.label
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: card.theme.textSoft
        font.family: Style.font.family
        font.pixelSize: 11 * card.textUnit
        textFormat: Text.PlainText
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
        color: card.theme.textFaint
        font.family: Style.font.family
        font.pixelSize: 10 * card.textUnit
        textFormat: Text.PlainText
        text: card.group.monitor
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: card.group.onScreen
        width: 6 * card.unit
        height: width
        radius: width / 2
        color: card.theme.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: card.group.onScreen && card.width > 190 * card.unit
        color: card.theme.accentText
        font.family: Style.font.family
        font.pixelSize: 10 * card.textUnit
        textFormat: Text.PlainText
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
    clip: true

    // The monitor's screen area; windows a scrolling layout parked beside
    // it show outside this outline.
    Rectangle {
      visible: card.items.viewport !== null
      x: card.items.viewport ? card.items.viewport.x : 0
      y: card.items.viewport ? card.items.viewport.y : 0
      width: card.items.viewport ? card.items.viewport.width : 0
      height: card.items.viewport ? card.items.viewport.height : 0
      radius: appearance.cornerRadius
      color: card.theme.screen
      border.width: appearance.borderWidth
      border.color: card.group.onScreen ? card.theme.screenBorderOn : card.theme.screenBorder
    }

    Text {
      anchors.centerIn: parent
      visible: card.group.entries.length === 0
      color: card.theme.textFaint
      font.family: Style.font.family
      font.pixelSize: 10 * card.textUnit
      textFormat: Text.PlainText
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
        readonly property bool parked: Layout.outside(card.windows[index], card.viewport)
        readonly property var snapshot: card.controller && entry ? (card.controller.snapshots[entry.address] || null) : null
        // A frame is worth showing from a thumbnail's size on; a title from
        // a tile that can hold a line of it.
        readonly property bool showsFrame: snapshot !== null && width >= 36 * card.unit && height >= 24 * card.unit
        readonly property bool roomy: width >= 84 * card.unit && height >= 46 * card.unit
        readonly property string title: {
          const toplevel = entry ? entry.toplevel : null
          return toplevel && toplevel.title ? String(toplevel.title) : (entry ? (entry.title || entry.appName) : "")
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
          radius: appearance.cornerRadius
          color: tile.selected ? card.theme.tileSelected : (hover.containsMouse ? card.theme.tileHover : card.theme.tile)
        }

        // The frame: the same image (and texture) the card holds, no copy and
        // no capture. Only a tile that has one pays for the rounded clip (two
        // offscreen passes on the GPU). It fades in over the icon when the
        // first frame is kept.
        Loader {
          anchors.fill: parent
          active: tile.showsFrame || opacity > 0
          opacity: tile.showsFrame ? (tile.selected || hover.containsMouse ? 1 : 0.78) : 0

          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

          sourceComponent: ClippingRectangle {
            radius: appearance.cornerRadius
            color: "transparent"

            Image {
              anchors.fill: parent
              source: tile.snapshot ? tile.snapshot.url : ""
              fillMode: Image.PreserveAspectCrop
              smooth: true
              mipmap: true
            }
          }
        }

        // Icon alone: centered, and above the title when there is room.
        AppIcon {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: tile.roomy ? -7 * card.textUnit : 0
          size: Math.min(26 * card.unit, Math.min(tile.width, tile.height) * (tile.roomy ? 0.42 : 0.64))
          opacity: tile.showsFrame ? 0 : 1
          visible: opacity > 0 && size >= 7

          Behavior on opacity { NumberAnimation { duration: 180 } }
          source: tile.entry ? tile.entry.icon : ""
          name: tile.entry ? tile.entry.appName : ""
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 4 * card.unit
          width: parent.width - 8 * card.unit
          opacity: tile.showsFrame ? 0 : 1
          visible: tile.roomy && opacity > 0

          Behavior on opacity { NumberAnimation { duration: 180 } }
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          color: tile.selected ? card.theme.text : card.theme.textSoft
          font.family: Style.font.family
          font.pixelSize: 10 * card.textUnit
          textFormat: Text.PlainText
          text: tile.title
        }

        // Over a frame: the icon, and the title where there is room, in a
        // strip along the bottom.
        Rectangle {
          id: strip

          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 1
          height: Math.round(16 * card.textUnit)
          radius: appearance.cornerRadius
          opacity: tile.showsFrame ? 1 : 0
          visible: opacity > 0
          color: tile.roomy ? card.theme.panel : "transparent"

          Behavior on opacity { NumberAnimation { duration: 180 } }

          AppIcon {
            id: stripIcon

            x: 3 * card.unit
            anchors.verticalCenter: parent.verticalCenter
            size: 11 * card.textUnit
            source: tile.entry ? tile.entry.icon : ""
            name: tile.entry ? tile.entry.appName : ""
          }

          Text {
            anchors.left: stripIcon.right
            anchors.leftMargin: 4 * card.unit
            anchors.right: parent.right
            anchors.rightMargin: 4 * card.unit
            anchors.verticalCenter: parent.verticalCenter
            visible: tile.roomy
            elide: Text.ElideRight
            color: card.theme.text
            font.family: Style.font.family
            font.pixelSize: 10 * card.textUnit
            textFormat: Text.PlainText
            text: tile.title
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: appearance.cornerRadius
          color: "transparent"
          objectName: "tileOutline"
          border.width: appearance.borderWidth
          border.color: tile.selected ? card.theme.accent
            : (tile.urgent ? card.theme.urgent
              : (tile.entry && tile.entry.active ? card.theme.tileBorderActive : card.theme.tileBorder))
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
