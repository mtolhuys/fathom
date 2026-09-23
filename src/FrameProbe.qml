// Frame timing for the Phase 0 report. Only runs when asked (bench or the
// probe IPC call), because a running FrameAnimation keeps the overlay
// rendering every vsync.
//
// Two measurements:
//   * intervals between animation ticks of this window (FrameAnimation);
//   * frames actually swapped by this window's render loop (frameSwapped).

import QtQuick
import "Stats.js" as Stats

Item {
  id: probe

  property bool running: false
  property var intervalsMs: []
  property int swappedFrames: 0
  property real startedAtMs: 0
  property real stoppedAtMs: 0
  property int warmupFrames: 0
  readonly property int maxSamples: 20000

  onRunningChanged: {
    if (running) probe.reset()
    else probe.stoppedAtMs = Date.now()
  }

  function reset() {
    probe.intervalsMs = []
    probe.swappedFrames = 0
    probe.startedAtMs = Date.now()
    probe.stoppedAtMs = 0
    // The first ticks after mapping include surface setup, not steady state.
    probe.warmupFrames = 3
  }

  function summary() {
    const end = probe.stoppedAtMs > 0 ? probe.stoppedAtMs : Date.now()
    const duration = probe.startedAtMs > 0 ? end - probe.startedAtMs : 0
    return Stats.summarize(probe.intervalsMs, probe.swappedFrames, duration)
  }

  FrameAnimation {
    running: probe.running

    onTriggered: {
      if (probe.warmupFrames > 0) {
        probe.warmupFrames--
        return
      }
      if (probe.intervalsMs.length < probe.maxSamples)
        probe.intervalsMs.push(frameTime * 1000)
    }
  }

  Connections {
    target: probe.running ? probe.Window.window : null
    ignoreUnknownSignals: true

    function onFrameSwapped() {
      probe.swappedFrames++
    }
  }
}
