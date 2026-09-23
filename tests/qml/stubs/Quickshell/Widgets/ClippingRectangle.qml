import QtQuick

// The real one clips its children to a rounded rectangle through a shader;
// offscreen a clipped plain rectangle is close enough.
Rectangle {
  clip: true
}
