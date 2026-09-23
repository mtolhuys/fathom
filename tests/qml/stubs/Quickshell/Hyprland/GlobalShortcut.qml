import QtQuick
import FathomTest

QtObject {
  id: shortcut

  property string appid: ""
  property string name: ""
  property string description: ""

  signal pressed()
  signal released()

  Component.onCompleted: FakeSystem.registerShortcut(shortcut)
}
