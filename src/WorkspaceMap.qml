// The Surface: every workspace with its windows, in one row of cards. Card
// widths follow each workspace's minimap aspect and shrink together when the
// row would not fit.

pragma ComponentBehavior: Bound

import QtQuick
import "Layout.js" as Layout

Item {
  id: map

  property var controller: null
  property var view: null
  property real unit: 1

  readonly property var groups: controller ? controller.groups : []
  readonly property real gap: 10 * unit
  readonly property real chrome: 16 * unit
  readonly property real headerSpace: 34 * unit
  readonly property bool multiMonitor: {
    const info = controller ? controller.monitorInfo : ({})
    return Object.keys(info).length > 1
  }
  readonly property var aspects: {
    const list = []
    const info = controller ? controller.monitorInfo : ({})
    const names = Object.keys(info)
    for (let i = 0; i < groups.length; i++) {
      const group = groups[i]
      const viewport = info[group.monitor] || (names.length ? info[names[0]] : { x: 0, y: 0, width: 1920, height: 1080 })
      const windows = []
      for (let j = 0; j < group.entries.length; j++) {
        const entry = controller.field[group.entries[j]]
        if (entry && entry.geometry) windows.push(entry.geometry)
      }
      const bounds = Layout.minimapBounds(viewport, windows)
      list.push(bounds.width / bounds.height)
    }
    return list
  }
  readonly property var metrics: Layout.mapCards(aspects, width, Math.max(20, height - headerSpace), gap, chrome, 90 * unit)
  readonly property real rowWidth: {
    let total = 0
    for (let i = 0; i < metrics.widths.length; i++) total += metrics.widths[i]
    return total + gap * Math.max(0, metrics.widths.length - 1)
  }

  // The map tile of entry `entryIndex`, for the offscreen tests.
  function tileFor(entryIndex) {
    for (let i = 0; i < cards.count; i++) {
      const card = cards.itemAt(i) as WorkspaceCard
      const tile = card ? card.tileFor(entryIndex) : null
      if (tile) return tile
    }
    return null
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    spacing: map.gap

    Repeater {
      id: cards

      model: map.groups

      delegate: WorkspaceCard {
        controller: map.controller
        view: map.view
        unit: map.unit
        showMonitor: map.multiMonitor
        width: map.metrics.widths[index] || 100
        height: map.metrics.height + map.headerSpace
      }
    }
  }
}
