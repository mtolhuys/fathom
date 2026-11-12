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
  // With a single window the Alt chord does nothing unless the value is
  // "true"; then it opens the field as it does with more windows.
  readonly property bool openOnSingle: String(Commons.Color.pick("fathom.open-on-single", "")).trim().toLowerCase() === "true"

  // The card of a window in the Deep (#16). "window" gives each card its
  // window's own shape instead of the monitor's; any other value keeps the
  // monitor's.
  readonly property bool cardFitsWindow: String(Commons.Color.pick("fathom.card-fit", "")).trim().toLowerCase() === "window"
  // The space between the card's edge and its preview, in pixels on the
  // front card; negative (no value) keeps Fathom's own, which follows the
  // screen's size.
  readonly property real cardPadding: dimension(Commons.Color.pick("fathom.card-padding", ""), -1)
  // The card's surface stays behind the whole card unless the value is
  // "false"; then only the header strip keeps it, and the preview stands free.
  readonly property bool cardBackground: String(Commons.Color.pick("fathom.card-background", "")).trim().toLowerCase() !== "false"

  function dimension(value, fallback) {
    const text = String(value).trim()
    const number = Number(text)
    return text !== "" && isFinite(number) && number >= 0 ? number : fallback
  }
}
