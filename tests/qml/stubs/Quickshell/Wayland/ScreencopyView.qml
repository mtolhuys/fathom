import QtQuick

// A capture "has content" when the fake Wayland handle says its frame is
// ready. It then paints a plausible window (title bar, text lines) in the
// handle's color, so offscreen renders show what the layout looks like.
Item {
  id: view

  property var captureSource: null
  property bool live: false
  property bool paintCursor: false
  readonly property bool hasContent: !!captureSource && captureSource.contentReady === true
  readonly property size sourceSize: hasContent
    ? Qt.size(captureSource.width, captureSource.height) : Qt.size(0, 0)

  Rectangle {
    anchors.fill: parent
    visible: view.hasContent
    color: view.captureSource && view.captureSource.color ? view.captureSource.color : "#20242a"

    Rectangle {
      width: parent.width
      height: Math.max(2, parent.height * 0.07)
      color: Qt.darker(parent.color, 1.5)
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
          color: Qt.lighter(view.captureSource && view.captureSource.color ? view.captureSource.color : "#20242a", 1.9)
          opacity: 0.55
        }
      }
    }
  }
}
