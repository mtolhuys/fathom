// Reuse Omarchy's theme/user shell.toml merge and live reload. No file I/O.
import QtQuick
import qs.Commons // qmllint disable import

QtObject {
  // Machine-level [fathom] overrides survive plugin updates and theme changes.
  // Missing or invalid values follow the shell's structural style tokens.
  readonly property real cornerRadius: dimension(Color.pick("fathom.corner-radius", ""), Style.cornerRadius)
  readonly property real borderWidth: dimension(Color.pick("fathom.border-width", ""), Style.normalBorderWidth)
  // Scratchpads (special workspaces) stay in the Deep unless the value is
  // "false"; the map shows them either way.
  readonly property bool showScratchpads: String(Color.pick("fathom.show-scratchpads", "")).trim().toLowerCase() !== "false"
  // With a single window the Alt chord does nothing unless the user opts in
  // with `open-on-single = true`; then it opens the field for browsing.
  readonly property bool openOnSingle: String(Color.pick("fathom.open-on-single", "")).trim().toLowerCase() === "true"

  function dimension(value, fallback) {
    const text = String(value).trim()
    const number = Number(text)
    return text !== "" && isFinite(number) && number >= 0 ? number : fallback
  }
}
