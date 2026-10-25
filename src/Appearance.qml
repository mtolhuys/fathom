// Reuse Omarchy's theme/user shell.toml merge and live reload. No file I/O.
import QtQuick
import qs.Commons as Commons // qmllint disable import

QtObject {
  // Machine-level [fathom] overrides survive plugin updates and theme changes.
  // Missing or invalid values follow the shell's structural style tokens.
  readonly property real cornerRadius: dimension(Commons.Color.pick("fathom.corner-radius", ""), Commons.Style.cornerRadius)
  readonly property real borderWidth: dimension(Commons.Color.pick("fathom.border-width", ""), Commons.Style.normalBorderWidth)
  // Scratchpads (special workspaces) stay in the Deep unless the value is
  // "false"; the map shows them either way.
  readonly property bool showScratchpads: String(Commons.Color.pick("fathom.show-scratchpads", "")).trim().toLowerCase() !== "false"

  function dimension(value, fallback) {
    const text = String(value).trim()
    const number = Number(text)
    return text !== "" && isFinite(number) && number >= 0 ? number : fallback
  }
}
