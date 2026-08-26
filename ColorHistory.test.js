const { test } = require("node:test")
const assert = require("node:assert")
const H = require("./ColorHistory.js")

const tsv = [
  "1756200000\t#FF0044",
  "1756200010\t#22cc88",
  "1756200020\t#FF0044",
  "1756200030\t#123456\t*"
].join("\n") + "\n"

test("parses the TSV, normalizing case and reading the star column", () => {
  const rows = H.parseHistory(tsv)
  assert.equal(rows.length, 4)
  assert.deepEqual(rows[1], { ts: 1756200010, hex: "#22CC88", starred: false })
  assert.equal(rows[3].starred, true)
})

test("drops junk lines instead of repairing them", () => {
  assert.deepEqual(H.parseHistory("garbage\n\n123\tnothex\n"), [])
  assert.equal(H.parseHistory("notanumber\t#ff0044\n")[0].ts, 0)
})

test("serialize round-trips, and omits the star column when unstarred", () => {
  const rows = H.parseHistory(tsv)
  assert.equal(H.serialize(rows).split("\n")[0], "1756200000\t#FF0044")
  assert.equal(H.serialize(rows).split("\n")[3], "1756200030\t#123456\t*")
  assert.deepEqual(H.parseHistory(H.serialize(rows)), rows)
})

test("formats a color three ways", () => {
  assert.equal(H.formatColor("#ff0044", "hex"), "#FF0044")
  assert.equal(H.formatColor("#ff0044", "rgb"), "rgb(255, 0, 68)")
  assert.equal(H.formatColor("#ff0044", "hsl"), "hsl(344, 100%, 50%)")
  assert.equal(H.formatColor("#808080", "hsl"), "hsl(0, 0%, 50%)")
  assert.equal(H.formatColor("nonsense", "hex"), "")
})

test("format cycles and falls back to hex on junk", () => {
  assert.equal(H.nextFormat("hex"), "rgb")
  assert.equal(H.nextFormat("hsl"), "hex")
  assert.equal(H.normalizeFormat("HSL"), "hsl")
  assert.equal(H.normalizeFormat("cmyk"), "hex")
})

test("dedup keeps the most recent pick of a color, newest first", () => {
  const shown = H.displayRows(H.parseHistory(tsv), "", "hex")
  assert.deepEqual(shown.map(r => r.hex), ["#123456", "#FF0044", "#22CC88"])
  assert.equal(shown.find(r => r.hex === "#FF0044").ts, 1756200020)
})

test("starred colors pin above the timeline", () => {
  const shown = H.displayRows(H.parseHistory(tsv), "", "hex")
  assert.equal(shown[0].hex, "#123456")
  assert.equal(shown[0].starred, true)
})

test("starring writes the flag to every row of that color", () => {
  const rows = H.toggleStar(H.parseHistory(tsv), "#ff0044")
  assert.deepEqual(rows.filter(r => r.hex === "#FF0044").map(r => r.starred), [true, true])
  assert.equal(H.isStarred(rows, "#FF0044"), true)
  assert.equal(H.isStarred(H.toggleStar(rows, "#FF0044"), "#FF0044"), false)
})

test("filter matches the displayed format, not the stored hex", () => {
  const rows = H.parseHistory(tsv)
  assert.deepEqual(H.displayRows(rows, "255", "rgb").map(r => r.hex), ["#FF0044"])
  assert.deepEqual(H.displayRows(rows, "255", "hex"), [])
  assert.deepEqual(H.displayRows(rows, "cc", "hex").map(r => r.hex), ["#22CC88"])
})

test("delete removes every pick of a color, starred or not", () => {
  const rows = H.removeColor(H.parseHistory(tsv), "#FF0044")
  assert.deepEqual(rows.map(r => r.hex), ["#22CC88", "#123456"])
  assert.deepEqual(H.removeColor(H.parseHistory(tsv), "#123456").map(r => r.hex),
    ["#FF0044", "#22CC88", "#FF0044"])
})

test("clear-all keeps starred rows and nothing else", () => {
  const rows = H.clearUnstarred(H.parseHistory(tsv))
  assert.deepEqual(rows.map(r => r.hex), ["#123456"])
  assert.deepEqual(H.clearUnstarred([]), [])
})

test("luminance separates light from dark for the swatch border", () => {
  assert.ok(H.relativeLuminance("#FFFFFF") > 0.9)
  assert.ok(H.relativeLuminance("#000000") < 0.01)
})
