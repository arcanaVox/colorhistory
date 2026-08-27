pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ColorHistory.js" as ColorHistory

// The picked-color history, shared by the bar panel and pick.sh.
//
// Every read and write goes through safeio.py rather than a FileView. These are
// predictable paths in a directory anything running as the user can write, and
// this code runs inside a shell process that stays up for days: a FIFO planted
// at one of them would park that shell forever, and a symlink would aim its
// writes at another of the user's files. safeio.py opens with O_NOFOLLOW and
// O_NONBLOCK, refuses anything that is not a regular file, and caps the read.
//
// Dropping FileView costs the change watch, so pick.sh calls back over IPC
// after it appends, and the panel reloads whenever it opens. Correctness never
// depends on a notification arriving: the file is the state, and every read
// re-reads it whole.
QtObject {
  id: root

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string safeIo: pluginDir + "/safeio.py"
  readonly property string stateDir: {
    var base = Quickshell.env("XDG_STATE_HOME")
    return (base ? base : Quickshell.env("HOME") + "/.local/state") + "/omarchy"
  }
  readonly property string historyPath: stateDir + "/color-history.tsv"
  readonly property string formatPath: stateDir + "/color-history-format"

  // Oldest first, exactly as pick.sh appends them.
  property var rows: []
  property string format: "hex"

  // Reads are subprocesses now, so they land some milliseconds after they are
  // asked for. Two things follow, and both have teeth:
  //
  //   loaded          until the first read lands, `rows` is empty because
  //                   nothing has been read yet — not because the history is
  //                   empty. Saving that model would truncate the file.
  //   writeGeneration a read started before a write must not apply after it,
  //                   or the model silently reverts to the older file and the
  //                   next save persists the revert.
  //
  // A generation check alone is not enough, because a read started *after* a
  // write is issued still reads the old bytes until that write reaches disk.
  // So reads never start while a write is in flight; they wait for it.
  property bool loaded: false
  property int writeGeneration: 0
  property bool reloadQueued: false

  readonly property bool empty: rows.length === 0
  readonly property string lastColor: rows.length > 0 ? rows[rows.length - 1].hex : ""

  function display(filter) { return ColorHistory.displayRows(root.rows, filter, root.format) }
  function label(hex) { return ColorHistory.formatColor(hex, root.format) }
  function isLight(hex) { return ColorHistory.relativeLuminance(hex) > 0.4 }

  function writesInFlight() {
    return historyWrite.running || historyWrite.pending !== ""
      || formatWrite.running || formatWrite.pending !== ""
  }

  function reload() {
    if (root.writesInFlight()) {
      root.reloadQueued = true
      return
    }
    if (!historyRead.running) {
      historyRead.generation = root.writeGeneration
      historyRead.running = true
    }
    if (!formatRead.running) {
      formatRead.generation = root.writeGeneration
      formatRead.running = true
    }
  }

  // Star, delete and clear are all the same operation — write the model back —
  // which is the whole reason the star lives in a third column instead of a
  // second file.
  function save(next) {
    // Refuse rather than persist a model that was never read. A dropped star is
    // a click the user can repeat; a truncated history is not recoverable.
    if (!root.loaded) return
    root.rows = next
    root.writeGeneration++
    historyWrite.queue(ColorHistory.serialize(next))
  }

  function toggleStar(hex) { root.save(ColorHistory.toggleStar(root.rows, hex)) }
  function removeColor(hex) { root.save(ColorHistory.removeColor(root.rows, hex)) }

  // No confirmation: this only ever destroys unstarred rows, so starring is the
  // confirmation step.
  function clearUnstarred() { root.save(ColorHistory.clearUnstarred(root.rows)) }

  function cycleFormat() {
    root.format = ColorHistory.nextFormat(root.format)
    root.writeGeneration++
    formatWrite.queue(root.format + "\n")
  }

  function releaseQueuedReload() {
    if (!root.reloadQueued || root.writesInFlight()) return
    root.reloadQueued = false
    root.reload()
  }

  function copy(hex) {
    var text = root.label(hex)
    if (text) Quickshell.execDetached(["wl-copy", "-n", "--", text])
  }

  // Exit 2 is "nothing there yet", which is a normal first run. Exit 1 means the
  // path held something this plugin refuses to touch, and the user should be
  // told rather than left with a history that silently stays empty.
  function readFailed(code, path) {
    if (code === 1) console.warn("colorhistory: refused to read " + path + " (not a regular file, or too large)")
  }

  property Process historyRead: Process {
    property int generation: 0
    command: ["python3", root.safeIo, "read", root.historyPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (historyRead.generation === root.writeGeneration)
          root.rows = ColorHistory.parseHistory(text)
        root.loaded = true
      }
    }
    onExited: function(code) {
      root.readFailed(code, root.historyPath)
      // A refusal or a missing file is still an answer: the model is known to
      // be empty, so mutations may proceed.
      root.loaded = true
    }
  }

  property Process formatRead: Process {
    property int generation: 0
    command: ["python3", root.safeIo, "read", root.formatPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (formatRead.generation === root.writeGeneration)
          root.format = ColorHistory.normalizeFormat(text)
      }
    }
    onExited: function(code) { root.readFailed(code, root.formatPath) }
  }

  // Writes carry one base64 line on stdin so the helper's read ends at the
  // newline; this Process holds the pipe open, so waiting for EOF would hang it.
  // A write requested while one is in flight is held rather than dropped —
  // Process.running is already true, so setting it again would do nothing and
  // lose the newer model.
  property Process historyWrite: Process {
    property string payload: ""
    property string pending: ""
    function queue(content) {
      if (running) { pending = content; return }
      payload = Qt.btoa(content)
      running = true
    }
    command: ["python3", root.safeIo, "write", root.historyPath]
    stdinEnabled: true
    onStarted: write(payload + "\n")
    onExited: function(code) {
      if (code !== 0) console.warn("colorhistory: refused to write " + root.historyPath)
      if (pending !== "") {
        var next = pending
        pending = ""
        queue(next)
        return
      }
      // Let `running` settle before deciding nothing is in flight.
      if (root.reloadQueued) Qt.callLater(root.releaseQueuedReload)
    }
  }

  property Process formatWrite: Process {
    property string payload: ""
    property string pending: ""
    function queue(content) {
      if (running) { pending = content; return }
      payload = Qt.btoa(content)
      running = true
    }
    command: ["python3", root.safeIo, "write", root.formatPath]
    stdinEnabled: true
    onStarted: write(payload + "\n")
    onExited: function(code) {
      if (code !== 0) console.warn("colorhistory: refused to write " + root.formatPath)
      if (pending !== "") {
        var next = pending
        pending = ""
        queue(next)
        return
      }
      // Let `running` settle before deciding nothing is in flight.
      if (root.reloadQueued) Qt.callLater(root.releaseQueuedReload)
    }
  }

  Component.onCompleted: root.reload()
}
