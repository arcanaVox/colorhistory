pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ColorHistory.js" as ColorHistory

// The picked-color history, shared by the bar panel and the overlay.
//
// Correctness does not depend on this being a true singleton: both FileViews
// watch their files, so if a relative-path import ever yields one instance per
// importer, the instances still converge through the file. The file is the
// state; this is just the code that reads and writes it.
QtObject {
  id: root

  readonly property string stateDir: {
    var base = Quickshell.env("XDG_STATE_HOME")
    return (base ? base : Quickshell.env("HOME") + "/.local/state") + "/omarchy"
  }
  readonly property string historyPath: stateDir + "/color-history.tsv"
  readonly property string formatPath: stateDir + "/color-history-format"

  // Oldest first, exactly as pick.sh appends them.
  property var rows: []
  property string format: "hex"

  readonly property bool empty: rows.length === 0
  readonly property string lastColor: rows.length > 0 ? rows[rows.length - 1].hex : ""

  function display(filter) { return ColorHistory.displayRows(root.rows, filter, root.format) }
  function label(hex) { return ColorHistory.formatColor(hex, root.format) }
  function isLight(hex) { return ColorHistory.relativeLuminance(hex) > 0.4 }

  // Star, delete and clear are all the same operation — write the model back —
  // which is the whole reason the star lives in a third column instead of a
  // second file.
  function save(next) {
    root.rows = next
    historyFile.setText(ColorHistory.serialize(next))
  }

  function toggleStar(hex) { root.save(ColorHistory.toggleStar(root.rows, hex)) }
  function removeColor(hex) { root.save(ColorHistory.removeColor(root.rows, hex)) }

  // No confirmation: this only ever destroys unstarred rows, so starring is the
  // confirmation step.
  function clearUnstarred() { root.save(ColorHistory.clearUnstarred(root.rows)) }

  function cycleFormat() {
    root.format = ColorHistory.nextFormat(root.format)
    formatFile.setText(root.format + "\n")
  }

  function copy(hex) {
    var text = root.label(hex)
    if (text) Quickshell.execDetached(["wl-copy", "-n", "--", text])
  }

  property FileView historyFile: FileView {
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.rows = ColorHistory.parseHistory(text())
    onLoadFailed: root.rows = []
    onFileChanged: reload()
  }

  property FileView formatFile: FileView {
    path: root.formatPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.format = ColorHistory.normalizeFormat(text())
    onLoadFailed: root.format = "hex"
    onFileChanged: reload()
  }
}
