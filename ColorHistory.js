// Pure model for the color history: parsing, dedup, starring, formats.
//
// QML imports this as a stateless library; `node --test` requires it. Nothing
// in here touches a QML type, so the format math and the star/delete/clear
// rules are testable without starting a shell.

var HEX_PATTERN = /^#[0-9A-Fa-f]{6}$/
var FORMATS = ["hex", "rgb", "hsl"]

function normalizeHex(value) {
  var hex = String(value === undefined || value === null ? "" : value).trim()
  return HEX_PATTERN.test(hex) ? hex.toUpperCase() : ""
}

// One line of the TSV: "<epoch>\t<hex>[\t*]". A missing third field means
// unstarred, which is why pick.sh never has to know that starring exists.
function parseLine(line) {
  var parts = String(line).split("\t")
  var hex = normalizeHex(parts[1])
  if (!hex) return null

  var ts = parseInt(parts[0], 10)
  return {
    ts: isFinite(ts) && ts > 0 ? ts : 0,
    hex: hex,
    starred: String(parts[2] || "").trim() === "*"
  }
}

// Oldest first, matching the file. Unparseable lines are dropped rather than
// repaired: the file is append-only, so a bad line is either a hand-edit or a
// torn write, and neither is worth guessing at.
function parseHistory(raw) {
  var lines = String(raw === undefined || raw === null ? "" : raw).split("\n")
  var rows = []
  for (var i = 0; i < lines.length; i++) {
    var row = parseLine(lines[i])
    if (row) rows.push(row)
  }
  return rows
}

function serialize(rows) {
  var out = ""
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    out += row.ts + "\t" + row.hex + (row.starred ? "\t*" : "") + "\n"
  }
  return out
}

function toRgb(hex) {
  return [
    parseInt(hex.substr(1, 2), 16),
    parseInt(hex.substr(3, 2), 16),
    parseInt(hex.substr(5, 2), 16)
  ]
}

function toHsl(hex) {
  var rgb = toRgb(hex)
  var r = rgb[0] / 255
  var g = rgb[1] / 255
  var b = rgb[2] / 255
  var max = Math.max(r, g, b)
  var min = Math.min(r, g, b)
  var lightness = (max + min) / 2
  var hue = 0
  var saturation = 0

  if (max !== min) {
    var delta = max - min
    saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min)
    if (max === r) hue = (g - b) / delta + (g < b ? 6 : 0)
    else if (max === g) hue = (b - r) / delta + 2
    else hue = (r - g) / delta + 4
    hue /= 6
  }

  return [Math.round(hue * 360), Math.round(saturation * 100), Math.round(lightness * 100)]
}

function normalizeFormat(value) {
  var format = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return FORMATS.indexOf(format) >= 0 ? format : "hex"
}

function nextFormat(value) {
  return FORMATS[(FORMATS.indexOf(normalizeFormat(value)) + 1) % FORMATS.length]
}

function formatColor(hex, format) {
  var value = normalizeHex(hex)
  if (!value) return ""

  if (normalizeFormat(format) === "rgb") {
    var rgb = toRgb(value)
    return "rgb(" + rgb[0] + ", " + rgb[1] + ", " + rgb[2] + ")"
  }
  if (normalizeFormat(format) === "hsl") {
    var hsl = toHsl(value)
    return "hsl(" + hsl[0] + ", " + hsl[1] + "%, " + hsl[2] + "%)"
  }
  return value
}

// The newest row for a color decides whether it is starred. setStar keeps every
// row for that color in agreement, so this is a shortcut rather than a guess.
function isStarred(rows, hex) {
  var target = normalizeHex(hex)
  for (var i = rows.length - 1; i >= 0; i--)
    if (rows[i].hex === target) return rows[i].starred === true
  return false
}

// Starring is a property of the color, not of one pick, so the flag is written
// to every row with that hex. displayRows then trusts the newest row it meets
// instead of rescanning per color, which would make rendering O(n^2).
function setStar(rows, hex, starred) {
  var target = normalizeHex(hex)
  var next = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    next.push(row.hex === target ? { ts: row.ts, hex: row.hex, starred: starred === true } : row)
  }
  return next
}

function toggleStar(rows, hex) {
  return setStar(rows, hex, !isStarred(rows, hex))
}

// Delete drops every pick of that color, not just the most recent one, so the
// swatch does not reappear from an older row the moment it is removed.
function removeColor(rows, hex) {
  var target = normalizeHex(hex)
  var next = []
  for (var i = 0; i < rows.length; i++)
    if (rows[i].hex !== target) next.push(rows[i])
  return next
}

function clearUnstarred(rows) {
  var next = []
  for (var i = 0; i < rows.length; i++)
    if (rows[i].starred) next.push(rows[i])
  return next
}

// One entry per color, newest first, starred pinned above the timeline. The
// file is oldest-first, so walking backwards keeps the most recent pick of each
// color and drops the rest. The filter matches the label as displayed, so
// searching "255" finds things while the rgb format is active.
function displayRows(rows, filter, format) {
  var resolvedFormat = normalizeFormat(format)
  var needle = String(filter === undefined || filter === null ? "" : filter).trim().toLowerCase()
  var seen = {}
  var starred = []
  var timeline = []

  for (var i = rows.length - 1; i >= 0; i--) {
    var row = rows[i]
    if (seen[row.hex]) continue
    seen[row.hex] = true

    var entry = {
      hex: row.hex,
      ts: row.ts,
      starred: row.starred === true,
      label: formatColor(row.hex, resolvedFormat)
    }
    if (needle && entry.label.toLowerCase().indexOf(needle) < 0) continue
    if (entry.starred) starred.push(entry)
    else timeline.push(entry)
  }

  return starred.concat(timeline)
}

// Swatches sit on the theme background, so a color close to it would otherwise
// be an invisible tile. Pick whichever of the theme's own foreground/background
// contrasts more with the swatch itself.
function relativeLuminance(hex) {
  var rgb = toRgb(normalizeHex(hex) || "#000000")
  var channels = []
  for (var i = 0; i < 3; i++) {
    var c = rgb[i] / 255
    channels.push(c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
  }
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    normalizeHex: normalizeHex,
    parseLine: parseLine,
    parseHistory: parseHistory,
    serialize: serialize,
    normalizeFormat: normalizeFormat,
    nextFormat: nextFormat,
    formatColor: formatColor,
    isStarred: isStarred,
    setStar: setStar,
    toggleStar: toggleStar,
    removeColor: removeColor,
    clearUnstarred: clearUnstarred,
    displayRows: displayRows,
    relativeLuminance: relativeLuminance
  }
}
