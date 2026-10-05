import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon + popup for the agent drawer.
//
// Left click opens this panel. Right click slides the drawer in or out from
// the bar itself, so the drawer is one click away even with no keyboard
// binding in play. Middle click restarts the agent.
//
// The panel is a plain KeyboardPanel: it fades in under the icon and does not
// slide or use a special workspace, which is deliberate — the drawer already
// owns the sliding surface, and a panel that moved would fight it.
Panel {
  id: root
  moduleName: "agent-drawer"
  ipcTarget: "agent-drawer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool cursorActive: false

  Usage {
    id: usage
    settings: root.settings
  }

  // AgentDrawer, not Drawer: QtQuick.Controls already owns that name and
  // wins the import order, which would silently resolve to the control.
  AgentDrawer {
    id: drawer
    bar: root.bar
  }

  // ------------------------------------------------------------------ helpers

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function field(record, name, fallback) {
    if (!record || record[name] === undefined || record[name] === null) return fallback
    return record[name]
  }

  // The record's own reason it has nothing to show, when it has one. A
  // collector that ran fine but found zeros gets the plain wording instead.
  function emptyText() {
    var record = usage.record
    if (!record) return usage.loading ? "Reading usage…" : "No usage data yet."
    if (String(record.note || "") !== "") return String(record.note)
    if (String(record.statusText || "") !== "") return String(record.statusText)
    return root.agentName() + " has no recorded usage yet."
  }

  function heroMeta() {
    var record = usage.record
    if (record && String(record.statusText || "") !== "") return String(record.statusText)
    return "Default agent"
  }

  function agentName() {
    var record = usage.record
    return record && String(record.agentName || "") !== "" ? String(record.agentName) : "Agent"
  }

  function todayLabel() {
    var record = usage.record
    var day = record && record.today ? record.today : null
    if (!day) return "—"
    return usage.formatTokenCount(Number(day.tokens || 0))
  }

  function todayDetail() {
    var record = usage.record
    var day = record && record.today ? record.today : null
    if (!day) return ""
    return Number(day.messages || 0) + " replies · "
      + Number(day.sessions || 0) + " session" + (Number(day.sessions || 0) === 1 ? "" : "s")
  }

  function weekLabel() {
    var record = usage.record
    var week = record && record.week ? record.week : null
    if (!week) return "—"
    return usage.formatTokenCount(Number(week.tokens || 0))
  }

  function weekDetail() {
    var record = usage.record
    var week = record && record.week ? record.week : null
    if (!week) return ""
    return Number(week.messages || 0) + " replies · last 7 days"
  }

  function allTimeDetail() {
    var totals = usage.record ? usage.record.totals : null
    var all = usage.record ? usage.record.allTime : null
    if (all && Number(all.sessions || 0) > 0)
      return usage.formatTokenCount(Number(all.messages || 0)) + " replies · "
        + Number(all.sessions || 0) + " sessions since " + Number(all.days || 0) + " active days"
    if (totals) return usage.formatTokenCount(Number(totals.tokens || 0)) + " tokens all time"
    return ""
  }

  // `provider/model` from the collector, reduced to the model half so a row
  // reads "big-pickle" rather than "opencode/big-pickle".
  function modelName(row) {
    return usage.friendlyModelName(row ? row.id : "")
  }

  function weekPeak() {
    var days = usage.record && usage.record.days ? usage.record.days : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].tokens || 0))
    return peak
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function isToday(date) {
    var now = new Date()
    var today = now.getFullYear() + "-"
      + String(now.getMonth() + 1).padStart(2, "0") + "-"
      + String(now.getDate()).padStart(2, "0")
    return String(date || "") === today
  }

  function dayLabel(day) {
    return isToday(day ? day.date : "") ? "Today" : dayName(day ? day.date : "")
  }

  function dayTooltip(day) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime()) ? String(day.date) : dayName(day.date)
    return label + " · " + usage.formatTokenCount(Number(day.tokens || 0)) + " tokens"
      + " · " + Number(day.messages || 0) + " replies"
  }

  function modelTooltip(row) {
    if (!row) return ""
    var record = usage.record
    var day = record && record.today ? record.today : null
    if (!day) return ""
    return Number(row.messages || 0) + " replies · "
      + usage.formatTokenCount(Number(row.tokens || 0)) + " tokens all time"
  }

  function drawerStateText() {
    if (drawer.busy) return "Working…"
    if (drawer.phase === "missing") return "Not running"
    return drawer.isOpen ? "Open" : "Hidden"
  }

  function footerText() {
    var parts = []
    var record = usage.record
    if (record && String(record.source || "") !== "")
      parts.push("source: " + String(record.source))
    if (usage.error !== "") parts.push(usage.error)
    return parts.join(" · ")
  }

  // ------------------------------------------------------------------ settings

  function writeSetting(key, value) {
    if (settingsWriter.running) return
    settingsWriter.command = ["omarchy", "bar", "set", "agent-drawer", key, String(value), "--json"]
    settingsWriter.running = true
  }

  // `omarchy bar set --json` wants a JSON value, so a string has to be quoted
  // or the command rejects it as malformed.
  function writeStringSetting(key, value) {
    if (settingsWriter.running) return
    settingsWriter.command = ["omarchy", "bar", "set", "agent-drawer", key, JSON.stringify(String(value)), "--json"]
    settingsWriter.running = true
  }

  Process {
    id: settingsWriter
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agent-drawer", text.trim())
    }
  }

  // The bind script owns the Hyprland side, so the panel asks it to apply,
  // suspend or put back rather than editing bindings.lua itself.
  readonly property string bindPath: Qt.resolvedUrl("bin/agent-drawer-bind")

  Process {
    id: shortcutBinder
    running: false
    command: [root.bindPath, "apply"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = text.trim()
        if (out !== "")
          root.keyStatus = out.charAt(0).toUpperCase() + out.slice(1)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() === "") return
        root.keyStatus = text.trim().split("\n").pop()
        root.keyStatusIsError = true
      }
    }
  }

  Process {
    id: shortcutSuspender
    running: false
    command: [root.bindPath, "suspend"]
  }

  // Recovery for a recording that was abandoned rather than finished.
  //
  // Arming lifts the live binding so the shortcut in force cannot swallow the
  // key press being recorded. That leaves one bad case: the panel goes away
  // first, through a click outside or a workspace change, and nothing ever puts
  // the binding back. The shortcut then silently does nothing, which is the
  // worst way for this to fail. The script writes a marker while a binding is
  // lifted, and this puts it back on the next open or close. It is a no-op when
  // no recording is outstanding, so it costs nothing in the normal case.
  Process {
    id: shortcutHealer
    running: false
    command: [root.bindPath, "heal"]
  }

  // Listens for the shortcut being recorded. Focus only matters while armed,
  // and it is handed back afterwards so the panel's own keys keep working.
  //
  // The item stays visible: Qt will not give an invisible item the focus that
  // receiving key events requires. It is one transparent pixel, so it costs
  // nothing and is not seen.
  Item {
    id: shortcutCatcher
    width: 1
    height: 1
    opacity: 0
    focus: root.recordingKey

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (!root.recordingKey) return
      event.accepted = true

      if (event.key === Qt.Key_Escape) {
        root.cancelShortcut()
        return
      }

      var combo = root.comboFromEvent(event)
      if (combo === "") {
        root.keyStatusIsError = true
        root.keyStatus = "Press a key with a modifier, such as SUPER + SHIFT + A"
        return
      }

      root.applyShortcut(combo)
    }
  }

  // Both sliders are a fraction of whichever monitor the drawer opens on, so the
  // same setting reads the same on a laptop panel and on a 4K display.
  function percentLabel(value) {
    return Math.round(Number(value) || 0) + "% of screen"
  }

  function secondsLabel(value) {
    var n = Number(value) || 0
    if (n >= 3600) return (n / 3600).toFixed(n % 3600 === 0 ? 0 : 1) + " h"
    if (n >= 60) return Math.round(n / 60) + " min"
    return n + " s"
  }

  // A finished drag writes once; `moved` fires on every pixel of travel.
  function persist(key, value) {
    root.writeSetting(key, value)
  }

  // ------------------------------------------------------------------ shortcut

  readonly property string defaultToggleKey: "SUPER + SHIFT + A"

  // Armed while waiting for a key press, and the capture item holds focus for
  // exactly that long.
  property bool recordingKey: false
  property string keyStatus: ""
  property bool keyStatusIsError: false

  function toggleKey() {
    return String(root.setting("toggleKey", root.defaultToggleKey))
  }

  // What the row shows: the shortcut, or the fact that there isn't one. An
  // empty value is the deliberate "off" state, not a missing setting, so it
  // reads differently from the default rather than as an empty field.
  function shortcutLabel() {
    var key = root.toggleKey().trim()
    return key === "" ? "Not bound" : key
  }

  // The words for keys that have no single character, so the captured value is
  // something Hyprland recognises rather than whatever Qt calls it.
  function namedKey(key) {
    if (key >= Qt.Key_F1 && key <= Qt.Key_F24) return "F" + (key - Qt.Key_F1 + 1)
    switch (key) {
      case Qt.Key_Escape: return "ESCAPE"
      case Qt.Key_Return:
      case Qt.Key_Enter: return "RETURN"
      case Qt.Key_Space: return "SPACE"
      case Qt.Key_Tab: return "TAB"
      case Qt.Key_Backspace: return "BACKSPACE"
      case Qt.Key_Delete: return "DELETE"
      case Qt.Key_Insert: return "INSERT"
      case Qt.Key_Home: return "HOME"
      case Qt.Key_End: return "END"
      case Qt.Key_PageUp: return "PAGE_UP"
      case Qt.Key_PageDown: return "PAGE_DOWN"
      case Qt.Key_Minus: return "MINUS"
      case Qt.Key_Equal: return "EQUAL"
      case Qt.Key_BracketLeft: return "BRACKETLEFT"
      case Qt.Key_BracketRight: return "BRACKETRIGHT"
      case Qt.Key_Semicolon: return "SEMICOLON"
      case Qt.Key_Apostrophe: return "APOSTROPHE"
      case Qt.Key_QuoteLeft: return "GRAVE"
      case Qt.Key_Backslash: return "BACKSLASH"
      case Qt.Key_Comma: return "COMMA"
      case Qt.Key_Period: return "PERIOD"
      case Qt.Key_Slash: return "SLASH"
    }
    return ""
  }

  // Turn a key press into the "SUPER + SHIFT + A" form the panel stores.
  // Returns "" for a key with no Hyprland name, so the caller can say so
  // instead of writing a shortcut that would silently never fire.
  function comboFromEvent(event) {
    var key = root.namedKey(event.key)
    if (key === "") {
      var text = String(event.text || "")
      key = text.length === 1 && /[a-z0-9]/i.test(text) ? text.toUpperCase() : ""
    }
    if (key === "") return ""

    var parts = []
    if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
    if (event.modifiers & Qt.AltModifier) parts.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")
    // A shortcut with no modifier at all would swallow a bare letter, so it is
    // refused rather than accepted and immediately regretted.
    if (parts.length === 0) return ""
    parts.push(key)
    return parts.join(" + ")
  }

  // The line under the drawer buttons that explains what the shortcut does. With
  // no shortcut there is nothing to explain, so it says the other true thing
  // instead of naming a key that does nothing.
  function shortcutHint() {
    var key = root.toggleKey().trim()
    if (key === "")
      return "Hiding keeps the agent running. No toggle shortcut is set."
    return key.replace(/ \+ /g, "+") + " toggles the drawer from anywhere. Hiding keeps the agent running."
  }

  // Persist the shortcut and hand it to the script that owns the binding. The
  // value goes as an argument rather than being read back from the settings
  // file, because that write is a separate process and reading it here would
  // race it into binding the previous shortcut.
  function applyShortcut(value) {
    root.recordingKey = false
    root.keyStatusIsError = false
    root.writeStringSetting("toggleKey", value)
    shortcutBinder.arguments = [value]
    shortcutBinder.running = true
    // Hand the keyboard back to the panel now rather than when the script
    // finishes, so a slow Hyprland reload cannot swallow the next key press.
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function armShortcut() {
    root.keyStatus = ""
    root.recordingKey = true
    // The shortcut in force would fire instead of reaching the panel, so lift
    // it for as long as the panel is listening.
    shortcutSuspender.running = true
    shortcutCatcher.forceActiveFocus()
  }

  function cancelShortcut() {
    // Only a recording in progress needs undoing. Cancelling an idle panel must
    // not rewrite the setting or reload Hyprland, so this returns early.
    if (!root.recordingKey) return
    root.applyShortcut(root.toggleKey())
    root.keyStatus = "Unchanged"
  }

  // ------------------------------------------------------------- bar contents

  // The bar names the agent the drawer will actually launch, so switching the
  // default agent is visible without opening the panel.
  //
  // These are Nerd Font marks written as codepoints so the mapping is
  // checkable, and checked against the bar's own font. They are the fallback for
  // agents with no asset: a glyph that is not quite the agent's identity still
  // beats borrowing another agent's mark, which would be a lie about what is
  // about to open.
  readonly property var agentGlyphs: ({
    "opencode": "\uf0233",
    "claude": "\uf0316",
    "codex": "\uf0317",
    "gemini": "\uf0318",
    "copilot": "\uf0314",
  })

  readonly property string fallbackGlyph: "\uf0a29"

  function agentId() {
    return String(root.field(usage.record, "agentId", "")).toLowerCase()
  }

  // A real mark beats a substitute: assets/opencode.svg is OpenCode's own logo,
  // and no Nerd Font glyph is a convincing stand-in for it. Candidates resolve
  // by convention, so dropping assets/<id>.svg in is all a new agent needs.
  // Marks that work on both surfaces ship a -light twin for light ones.
  function agentIconCandidates() {
    var id = root.agentId()
    if (!id) return []
    var candidates = []
    if (root.colorLuminance(Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + id + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + id + ".svg"))
    return candidates
  }

  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    if (!color) return 0
    return 0.2126 * root.colorChannelLuminance(color.r)
      + 0.7152 * root.colorChannelLuminance(color.g)
      + 0.0722 * root.colorChannelLuminance(color.b)
  }

  function agentGlyph() {
    var glyph = root.agentGlyphs[root.agentId()]
    return glyph !== undefined ? glyph : root.fallbackGlyph
  }

  // Today, not all time: an all-time count on a bar reads as a rate, and a
  // lifetime figure that keeps climbing is not something you act on. Blank
  // until the collector has answered, rather than 0, which would claim the
  // agent has never been used.
  function barTokenText() {
    var record = usage.record
    var today = record ? record.today : null
    if (!today) return usage.loading ? "" : "—"
    var text = usage.formatTokenCount(Number(today.tokens || 0))
    var limits = record.limits || []
    return limits.length ? text + " · " + root.limitSummary(limits) : text
  }

  // Providers report how much of a window is spent, not a token allowance, so
  // there is no used/limit fraction to print. The window nearest its ceiling is
  // the one worth the space; the popup names them all.
  function limitSummary(limits) {
    var worst = limits[0]
    for (var i = 1; i < limits.length; i++) {
      if (Number(limits[i].percent || 0) > Number(worst.percent || 0)) worst = limits[i]
    }
    return Math.round(Number(worst.percent || 0) * 100) + "%"
  }

  // One set of button behaviour for the icon and the count beside it, so the
  // whole widget is the same button rather than an icon with a dead label.
  function handlePress(buttonCode) {
    if (buttonCode === Qt.RightButton) drawer.toggle()
    else if (buttonCode === Qt.MiddleButton) drawer.restart()
    else root.toggle()
  }

  visible: true
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // Runs on both edges, not just on open.
  //
  // Recording a shortcut lifts the live binding so the key can reach the panel
  // instead of firing the drawer. Anything that closes the panel without a key
  // being captured — a click outside, a workspace change, Escape at the wrong
  // moment — would otherwise leave the shortcut silently dead, so closing always
  // cancels an armed recording and always asks the script to heal.
  onOpenedChanged: {
    shortcutHealer.running = true
    if (!opened) {
      root.cancelShortcut()
      return
    }
    cursorActive = false
    usage.refresh()
    drawer.pollStatus()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { usage.refresh(); drawer.pollStatus(); return "ok" }
    function drawerToggle(): string { drawer.toggle(); return "ok" }
    function drawerShow(): string { drawer.show(); return "ok" }
    function drawerHide(): string { drawer.hide(); return "ok" }
    function drawerRestart(): string { drawer.restart(); return "ok" }
    // Distinct from the base class's open/close/toggle. The base Panel registers
    // those names on this same target, and whichever handler Quickshell resolves
    // first wins, so a plain `open` here was silently answered by the disabled
    // base handler and the panel never appeared.
    function panelOpen(): void { root.open() }
    function panelClose(): void { root.close() }
  }

  // The icon and the count beside it are one button. The Row owns the bar slot's
  // width, so the count does not need the panel open to be readable and the
  // panel does not change shape when it is.
  Row {
    id: row
    spacing: Style.space(5)

    BarIconButton {
      id: button
      bar: root.bar
      active: drawer.isOpen
      onPressed: function(buttonCode) { root.handlePress(buttonCode) }

      iconComponent: Component {
        Item {
          id: mark
          readonly property var candidates: root.agentIconCandidates()
          // Provider objects are rebuilt on every refresh, which churns the
          // array's identity without changing its content. Restart the fallback
          // walk only when the URLs change: re-pointing source at a URL whose
          // load already failed emits no statusChanged, so an identity-only
          // reset would strand the walker on a missing -light twin.
          readonly property string candidatesKey: candidates.join("\n")
          property int candidateIndex: 0
          onCandidatesKeyChanged: candidateIndex = 0

          Image {
            id: markImage
            anchors.fill: parent
            source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
            sourceSize.width: Style.bar.iconCanvas * 2
            sourceSize.height: Style.bar.iconCanvas * 2
            fillMode: Image.PreserveAspectFit
            // Advancing source from inside its own status change trips the
            // binding-loop detector; defer the step one tick.
            onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
              Qt.callLater(function() { mark.candidateIndex++ })
          }

          Text {
            anchors.fill: parent
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: markImage.status !== Image.Ready
            text: root.agentGlyph()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
          }
        }
      }
    }

    Text {
      id: barTokens
      text: root.barTokenText()
      // Dimmed against the foreground so the count reads as a readout beside the
      // button rather than as a second control. It takes the active tint while
      // the drawer is open: the icon is a fixed-colour asset and cannot.
      color: button.active && button.useActiveColor ? button.activeColor : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      // Row places children by their top edge, so centre the text against the
      // row's own height rather than anchoring it inside a positioner.
      height: row.implicitHeight
      verticalAlignment: Text.AlignVCenter

      MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) { root.handlePress(mouse.button) }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a shortcut is being recorded the panel's own keys would close it
      // or run a command out from under the key press being recorded.
      blocked: root.recordingKey

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: usage.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") usage.refresh()
        else if (t === "d" || t === "D") drawer.toggle()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: what this is ----------
          PanelHero {
            width: parent.width
            title: root.agentName()
            meta: root.heroMeta()
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // ---------- Today / this week ----------
          Row {
            width: parent.width
            spacing: Style.spacing.md

            StatTile {
              width: (parent.width - parent.spacing) / 2
              label: "TODAY"
              value: root.todayLabel()
              detail: root.todayDetail()
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            StatTile {
              width: (parent.width - parent.spacing) / 2
              label: "THIS WEEK"
              value: root.weekLabel()
              detail: root.weekDetail()
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          // Nothing recorded yet, or the collector had something to say about
          // why. Either way it replaces the charts rather than showing zeros.
          Text {
            textFormat: Text.PlainText
            visible: !usage.hasRecord || usage.record.available === false
            width: parent.width
            topPadding: Style.space(8)
            text: root.emptyText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Tokens by day ----------
          PanelSeparator {
            visible: chart.visible
            foreground: root.foreground
          }

          Column {
            id: chart
            visible: usage.hasRecord && usage.record.available === true
            width: parent.width
            spacing: Style.space(8)

            readonly property var days: usage.record && usage.record.days ? usage.record.days : []
            readonly property real peak: Math.max(1, root.weekPeak())

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: chart.days

              DayRow {
                required property var modelData
                width: chart.width
                day: modelData
                ratio: Number(modelData.tokens || 0) / chart.peak
                today: root.isToday(modelData.date)
              }
            }
          }

          // ---------- Tokens by model ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: usage.hasRecord && usage.record.models && usage.record.models.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: usage.record ? usage.record.models : []

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                share: Number(modelData.tokens || 0) / Math.max(1, usage.record.models[0].tokens)
              }
            }
          }

          // ---------- Drawer ----------
          PanelSeparator {
            visible: drawerSection.visible
            foreground: root.foreground
          }

          Column {
            id: drawerSection
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "DRAWER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(drawerState.implicitHeight, drawerValue.implicitHeight)

              Text {
                id: drawerState
                textFormat: Text.PlainText
                text: drawer.running ? "Agent window" : "Agent window not running"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: drawerValue
                textFormat: Text.PlainText
                text: root.drawerStateText()
                color: drawer.isOpen ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: drawer.isOpen
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: (parent.width - parent.spacing * 2) / 3
                text: drawer.isOpen ? "Hide" : "Show"
                selected: drawer.isOpen
                hasCursor: root.cursorActive
                bordered: true
                enabled: !drawer.busy
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: drawer.isOpen ? drawer.hide() : drawer.show()
              }

              Button {
                width: (parent.width - parent.spacing * 2) / 3
                text: "Restart"
                hasCursor: root.cursorActive
                bordered: true
                enabled: !drawer.busy && drawer.running
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: drawer.restart()
              }

              Button {
                width: (parent.width - parent.spacing * 2) / 3
                // Sliders write shell.json, but the window only takes the new
                // size the next time it is placed — so this pushes the current
                // settings at the drawer that is already open.
                text: "Apply size"
                hasCursor: root.cursorActive
                bordered: true
                enabled: !drawer.busy && drawer.running
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: drawer.show()
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              // Reads the shortcut rather than naming it, so the sentence cannot
              // go stale the moment the shortcut is changed.
              text: root.shortcutHint()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Geometry + refresh ----------
          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "SIZE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SliderRow {
              width: parent.width
              label: "Width"
              display: root.percentLabel(root.setting("drawerWidthPct", 44))
              bar: button
              value: Number(root.setting("drawerWidthPct", 44))
              minimum: 10
              maximum: 100
              step: 1
              onReleased: function(v) { root.persist("drawerWidthPct", v) }
            }

            SliderRow {
              width: parent.width
              label: "Height"
              display: root.percentLabel(root.setting("drawerHeightPct", 50))
              bar: button
              value: Number(root.setting("drawerHeightPct", 50))
              minimum: 10
              maximum: 100
              step: 1
              onReleased: function(v) { root.persist("drawerHeightPct", v) }
            }

            SliderRow {
              width: parent.width
              label: "Usage refresh"
              display: root.secondsLabel(root.setting("refreshIntervalSec", 300))
              bar: button
              value: Number(root.setting("refreshIntervalSec", 300))
              minimum: 30
              maximum: 3600
              step: 30
              integer: true
              onReleased: function(v) { root.persist("refreshIntervalSec", v) }
            }

            PanelSectionHeader {
              width: parent.width
              topPadding: Style.space(4)
              text: "SHORTCUT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ShortcutRow {
              width: parent.width
              recording: root.recordingKey
              display: root.shortcutLabel()
              status: root.recordingKey ? "Esc to cancel" : root.keyStatus
              onArmed: root.armShortcut()
              onCleared: root.applyShortcut("")
              onReset: root.applyShortcut(root.defaultToggleKey)
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Two big numbers side by side. The label sits above so the pair reads as a
  // header row rather than as two unrelated figures.
  component StatTile: Column {
    id: tile
    property string label: ""
    property string value: ""
    property string detail: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    spacing: Style.space(2)

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(2), Style.spacing.hairline * 2)
      radius: height / 2
      color: root.alpha(tile.foreground, 0.25)
    }

    Text {
      textFormat: Text.PlainText
      text: tile.label
      color: root.dim
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      textFormat: Text.PlainText
      text: tile.value
      color: tile.foreground
      font.family: tile.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      text: tile.detail
      color: root.dim
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.tokens || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(56)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day)
      fontFamily: root.fontFamily
    }
  }

  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: root.modelName(modelRow.row)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: usage.formatTokenCount(modelRow.row ? Number(modelRow.row.tokens || 0) : 0)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }

  // PanelSlider with the label and the resolved value above it. `value` is
  // bound from settings, so the knob jumps as the drag commits.
  component SliderRow: Column {
    id: sliderRow
    property string label: ""
    property string display: ""
    property var bar: null
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property bool integer: false

    signal released(real value)

    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(sliderLabel.implicitHeight, sliderDisplay.implicitHeight)

      Text {
        id: sliderLabel
        textFormat: Text.PlainText
        text: sliderRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sliderDisplay
        textFormat: Text.PlainText
        text: sliderRow.display
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: sliderRow.bar
      value: sliderRow.value
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: sliderRow.integer
      onReleased: function(v) { sliderRow.released(v) }
    }
  }

  // The shortcut row reads as a setting rather than a button: the label says
  // what it is, the value on the right says what it currently is, and the whole
  // row is the click target. While it is armed the value turns into an
  // instruction instead, because the user is about to press something and needs
  // to know the panel is listening.
  component ShortcutRow: Column {
    id: shortcutRow
    property bool recording: false
    property string display: ""
    property string status: ""
    property bool statusIsError: false

    signal armed()
    signal cleared()
    signal reset()


    spacing: Style.space(2)

    Item {
      id: shortcutRowItem
      width: parent.width
      implicitHeight: Math.max(shortcutLabel.implicitHeight, shortcutValue.implicitHeight)

      // Declared before the label and the actions on purpose. Siblings take
      // input in declaration order, so a full-row MouseArea placed after them
      // sits on top and swallows every click meant for Off and Default — which
      // would leave the row impossible to arm as well as impossible to change.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: shortcutRow.armed()
      }

      Text {
        id: shortcutLabel
        textFormat: Text.PlainText
        text: "Toggle shortcut"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        spacing: Style.space(6)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: shortcutValue
          textFormat: Text.PlainText
          text: shortcutRow.recording ? "Press keys…" : shortcutRow.display
          color: shortcutRow.recording ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        CaptionAction {
          visible: !shortcutRow.recording && shortcutRow.display !== ""
          text: "Off"
          foreground: root.dim
          fontFamily: root.fontFamily
          onClicked: shortcutRow.cleared()
        }

        CaptionAction {
          visible: !shortcutRow.recording
          text: "Default"
          foreground: root.dim
          fontFamily: root.fontFamily
          onClicked: shortcutRow.reset()
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      text: shortcutRow.status
      color: shortcutRow.statusIsError ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  // A caption-sized text button, for the handful of row-level actions the
  // panel needs. Kept here rather than pulled in so it inherits the panel's
  // colours and font the way the rest of the rows do.
  component CaptionAction: Item {
    id: action
    property string text: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal clicked()

    implicitWidth: actionLabel.implicitWidth + Style.space(8)
    implicitHeight: Math.max(actionLabel.implicitHeight, Style.space(14))

    Text {
      id: actionLabel
      textFormat: Text.PlainText
      text: action.text
      color: action.foreground
      font.family: action.fontFamily
      font.pixelSize: Style.font.caption
      anchors.centerIn: parent
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(2)
      radius: Style.cornerRadius
      color: Style.selectedFillFor(action.foreground, Color.accent)
      opacity: actionMouse.containsPress ? 0.5 : (actionMouse.containsMouse ? 0.25 : 0)
      Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }
  }
}