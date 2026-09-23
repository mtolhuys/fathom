import QtQuick

// A capture "has content" when the fake Wayland handle says its frame is ready.
Item {
  property var captureSource: null
  property bool live: false
  property bool paintCursor: false
  readonly property bool hasContent: !!captureSource && captureSource.contentReady === true
  readonly property size sourceSize: hasContent
    ? Qt.size(captureSource.width, captureSource.height) : Qt.size(0, 0)
}
