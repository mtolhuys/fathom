// Test replacement for src/FieldSurface.qml: hosts the real FieldView in a
// plain item instead of a layer-shell window. For renders it can put a
// stand-in desktop behind the field (FakeSystem.backdrop), so a render shows
// what the veil really sits on.

import QtQuick
import FathomTest

Item {
  id: surface

  property var controller: null
  readonly property alias view: view

  // The offscreen platform's screen is 800x600; pointer events outside it
  // are dropped. Renders ask for a real screen size instead.
  width: FakeSystem.surfaceWidth
  height: FakeSystem.surfaceHeight
  visible: controller !== null && controller.opened

  onVisibleChanged: if (visible) Qt.callLater(view.focusKeys)

  // Drawn already blurred, the way Hyprland blurs what is behind the layer:
  // the offscreen tests render in software, where a blur effect would draw
  // nothing at all. Text smears into faint bands, a picture into its colors.
  Item {
    id: desktop

    readonly property bool light: FakeSystem.backdrop === "light"
    readonly property color wallpaper: light ? "#d9d3c7" : "#1b1f24"
    readonly property color window: light ? "#fbfaf7" : "#16181c"
    readonly property color ink: light ? "#2c2c30" : "#c9ccd1"

    anchors.fill: parent
    visible: FakeSystem.backdrop !== ""

    Rectangle {
      anchors.fill: parent
      color: desktop.wallpaper
    }

    // Two tiled windows of text, one with a picture in it, under a bar.
    Repeater {
      model: [[0.004, 0.62], [0.63, 0.366]]

      delegate: Rectangle {
        id: window

        required property var modelData

        x: surface.width * modelData[0]
        y: surface.height * 0.03
        width: surface.width * modelData[1]
        height: surface.height * 0.96
        radius: 8
        color: desktop.window

        Column {
          x: parent.width * 0.04
          y: parent.height * 0.05
          spacing: parent.height * 0.012

          Repeater {
            model: 20

            delegate: Rectangle {
              required property int index

              width: window.width * (0.4 + ((index * 41) % 50) / 100)
              height: window.height * 0.03
              radius: height / 2
              color: desktop.ink
              opacity: index % 6 === 0 ? 0.3 : 0.16
            }
          }
        }

        Rectangle {
          visible: window.modelData[0] > 0.5
          x: parent.width * 0.06
          y: parent.height * 0.5
          width: parent.width * 0.88
          height: parent.height * 0.34
          radius: 30
          gradient: Gradient {
            GradientStop { position: 0; color: "#b8744a" }
            GradientStop { position: 1; color: "#4a6a8f" }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: surface.height * 0.026
      color: desktop.light ? "#efeae1" : "#0e1013"
    }
  }

  FieldView {
    id: view

    anchors.fill: parent
    controller: surface.controller
  }
}
