import QtQuick
import FathomTest

// A capture "has content" when the fake Wayland handle says its frame is
// ready. It then paints a plausible window (title bar, text lines) in the
// handle's color, light or dark, so offscreen renders show what the layout
// looks like; a handle with a `kind` gets an illustrated app (MockApp).
Item {
  id: view

  property var captureSource: null
  property bool live: false
  property bool paintCursor: false
  readonly property bool hasContent: !!captureSource && captureSource.contentReady === true
  readonly property size sourceSize: hasContent
    ? Qt.size(captureSource.width, captureSource.height) : Qt.size(0, 0)
  readonly property color face: captureSource && captureSource.color ? captureSource.color : "#20242a"
  readonly property bool lightFace: face.hslLightness > 0.6

  Loader {
    anchors.fill: parent
    active: view.hasContent && !!(view.captureSource && view.captureSource.kind)
    sourceComponent: MockApp {
      kind: view.captureSource.kind
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: view.hasContent && !(view.captureSource && view.captureSource.kind)
    color: view.face

    Rectangle {
      width: parent.width
      height: Math.max(2, parent.height * 0.07)
      color: Qt.darker(view.face, view.lightFace ? 1.06 : 1.5)
    }

    Column {
      x: parent.width * 0.06
      y: parent.height * 0.14
      spacing: Math.max(1, parent.height * 0.035)

      Repeater {
        model: 9

        delegate: Rectangle {
          required property int index
          width: view.width * (0.3 + ((index * 37) % 50) / 100)
          height: Math.max(1, view.height * 0.028)
          radius: height / 2
          color: view.lightFace ? Qt.darker(view.face, 1.9) : Qt.lighter(view.face, 1.9)
          opacity: 0.55
        }
      }
    }
  }
}
