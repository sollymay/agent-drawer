import QtQuick
import Quickshell
import Quickshell.Io

// Runs the usage collector and hands the panel a parsed record.
//
// The collector script is the only thing that knows where usage lives: for
// OpenCode it aggregates opencode.db, for any other default agent it reads the
// shared record Omarchy's own agents panel watches. This file just runs it and
// parses what it prints, so a new agent never needs QML changes.
//
// An invisible Item rather than a QtObject because Process is a visual type:
// it can only be parented to something that has a `data` property.
Item {
  id: root
  visible: false

  property var settings: ({})
  property var record: null
  property bool loading: false
  property string error: ""

  // The panel shows a stale number as stale rather than as live: nothing here
  // invents a timestamp the collector did not send.
  readonly property bool hasRecord: record !== null

  readonly property string collectorPath: Qt.resolvedUrl("bin/agent-drawer-usage")
  readonly property int refreshIntervalSec: Math.max(
    30, Number(settings && settings.refreshIntervalSec) || 300)

  Process {
    id: collector
    running: false
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        root.error = "Usage collector exited with code " + exitCode
        return
      }
      root.applyOutput(collectorStdout.text)
    }

    stdout: StdioCollector {
      id: collectorStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: collectorStderr
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agent-drawer", text.trim())
    }
  }

  function applyOutput(output) {
    var parsed = null
    try {
      parsed = JSON.parse(String(output || "").trim())
    } catch (e) {
      console.warn("agent-drawer: could not parse usage record: " + e)
    }
    if (parsed === null) return
    // Reassign only on real change: a reassigned object tears down every
    // Repeater delegate in the panel for no visible reason.
    if (JSON.stringify(parsed) === JSON.stringify(root.record)) return
    root.record = parsed
    root.error = ""
  }

  function refresh() {
    if (collector.running) return
    root.loading = true
    collector.command = [root.collectorPath]
    collector.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // ------------------------------------------------------------------ format

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var tail = String(id)
    if (tail.indexOf("/") >= 0) tail = tail.slice(tail.lastIndexOf("/") + 1)
    return tail
  }
}