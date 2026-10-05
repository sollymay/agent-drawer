import QtQuick
import Quickshell
import Quickshell.Io

// Thin wrapper around bin/agent-drawer.
//
// The shell script owns everything Hyprland-specific — geometry, sliding the
// drawer in and out above the top edge of the screen, launching the terminal —
// because those are far easier to reason about as bash than as QML. This exposes
// just enough to drive it from the panel: a running/visible state, and
// toggle/show/hide/restart.
//
// An invisible Item rather than a QtObject because Process is a visual type:
// it can only be parented to something that has a `data` property.
Item {
  id: root
  visible: false

  property var bar: null

  // "visible" | "hidden" | "missing". Not `state` or `visible`: those are
  // QQuickItem's own and shadowing them breaks the item's visibility.
  readonly property string phase: statusWord
  readonly property bool isOpen: statusWord === "visible"
  readonly property bool running: statusWord !== "missing"
  readonly property string address: statusAddress
  readonly property bool busy: pending.running

  property string statusWord: "missing"
  property string statusAddress: ""
  property string error: ""

  readonly property string controlPath: Qt.resolvedUrl("bin/agent-drawer")

  function invoke(action) {
    if (pending.running) return
    pending.command = [root.controlPath, action]
    pending.running = true
  }

  function toggle() { root.invoke("toggle") }
  function show() { root.invoke("show") }
  function hide() { root.invoke("hide") }
  function restart() { root.invoke("restart") }

  // Reads `visible 0x…` / `hidden 0x…` / `missing` off stdout.
  function applyOutput(output) {
    var words = String(output || "").trim().split(/\s+/)
    var word = words.length > 0 ? words[0] : "missing"
    if (word !== "visible" && word !== "hidden") word = "missing"
    root.statusWord = word
    root.statusAddress = words.length > 1 ? words[1] : ""
  }

  Process {
    id: pending
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.error = "agent-drawer " + pending.command[1] + " failed (code " + exitCode + ")"
        console.warn("agent-drawer", root.error)
      } else {
        root.error = ""
        status.running = true
      }
    }
  }

  // status is a different command shape than the mutating actions, so it gets
  // its own process rather than racing them through the same one.
  Process {
    id: status
    running: false
    onExited: root.applyOutput(statusStdout.text)

    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agent-drawer", text.trim())
    }
  }

  // Deferred while a mutating command is in flight. `show` relaunches the
  // terminal, and a status poll landing in that gap reads "not-running", which
  // would flip `running` false and tear the watcher down only to bring it
  // straight back -- stranding its socket reader each time.
  function pollStatus() {
    if (status.running || pending.running) return
    status.command = [root.controlPath, "status"]
    status.running = true
  }

  Component.onCompleted: pollStatus()

  Timer {
    // The panel is open while this runs, so it keeps up with a drawer that the
    // keybinding hid from somewhere else. Cheap: one hyprctl clients call.
    interval: 1500
    running: root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollStatus()
  }

  Timer {
    interval: 3000
    running: !status.running && !pending.running
    repeat: false
    onTriggered: root.pollStatus()
  }

  // Hides the drawer when focus moves off it, which is what "click outside to
  // dismiss" reduces to in Hyprland. Bound to `running` so quitting the agent
  // tears the watcher down, and restarting it brings the watcher back.
  Process {
    running: root.running
    command: [root.controlPath, "watch"]

    stdout: StdioCollector {}

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("agent-drawer watch", text.trim())
    }
  }
}