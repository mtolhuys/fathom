import QtQuick
import FathomTest

QtObject {
  id: handler

  property string target: ""
  property bool enabled: true

  Component.onCompleted: FakeSystem.registerIpc(handler)
}
