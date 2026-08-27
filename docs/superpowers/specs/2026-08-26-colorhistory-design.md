# colorhistory — a history of colors picked with hyprpicker

Design spec — 2026-08-26

## 1. Summary

An Omarchy 4 shell plugin that records every color picked with `hyprpicker`
and gives it back to you later: a grid of swatches you can click to re-copy,
in hex, `rgb()`, or `hsl()`, with the ones you care about starred to the top.

Capture works by owning the picker rather than watching for its side effects.
The plugin ships a three-line `pick.sh` that runs `hyprpicker` itself and
appends the result to a file; a `service` entry point rebinds `SUPER+PRINT` to
it at runtime. Nothing on disk outside the plugin's own state file is ever
modified, so uninstall is `rm -rf` and a shell restart.

Storage is an append-only TSV. The shell reads it, dedups, and renders; the
shell is also the only writer for star/delete/clear, all of which funnel
through one "write the model back" path.

## 2. Decisions

Each row is a branch that was resolved during design, with the option taken
and the reason it beat the alternative.

| # | Decision | Taken | Rejected because |
|---|---|---|---|
| 1 | How a pick is recorded | Wrap `hyprpicker` in `pick.sh` | Watching the clipboard for `#RRGGBB` records every hex you copy out of a CSS file, and duplicates `omarchy.clipboard` |
| 2 | Where the rebind happens | `hyprctl keyword` from a `service` at shell start | `omarchy plugin add` has **no install hook**; editing `~/.config/hypr/bindings.lua` leaves debt after uninstall |
| 3 | The menu's `trigger.capture.color` row | Left alone | Overriding it means writing the user's `extensions/omarchy-menu.jsonc` — the disk mutation #2 exists to avoid |
| 4 | Storage format | Append-only TSV, hex only | JSON needs `jq` and a read-modify-write race on the hot path; other formats are `Qt.color()` away |
| 5 | Surfaces | `service` + `bar-widget` (revised, see §10) | The fullscreen overlay was dropped: one surface, opening from the bar like every other panel |
| 6 | Grid interaction | Copy, format cycle, delete, clear, keyboard nav | — (full version requested) |
| 7 | Retention | Dedup on read, newest first, no cap | A cap costs the deep-history search that makes type-to-filter worth having |
| 8 | Starring | Third TSV column | A separate stars file costs a second `FileView`, a second parse, and cross-file dedup |

## 3. Layout

```
io.github.arcanavox.colorhistory/     ← id is a placeholder; see §8
├── manifest.json      kinds: ["service", "bar-widget", "overlay"]
├── qmldir             so Panel/Overlay can import ColorGrid
├── Service.qml        registers both keybinds at shell start
├── Panel.qml          bar swatch + dropdown grid       (entryPoints.barWidget)
├── Overlay.qml        fullscreen grid                  (entryPoints.overlay)
├── ColorGrid.qml      the grid itself, imported by both
├── ColorHistory.js    pure functions: parse, dedup, star, delete, clear, filter
├── pick.sh            runs hyprpicker, appends the result
├── test.sh            stubs hyprpicker on PATH, asserts the TSV
├── ColorHistory.test.js
├── README.md
└── LICENSE            MIT
```

`ColorState.qml` was added during the build. Without it `Panel.qml` and
`Overlay.qml` would each carry their own `FileView` and their own copy of the
mutation calls; with it there is one reader and one writer. Correctness does not
depend on it being a true singleton — a relative-path singleton import can yield
one instance per importer, and the instances still converge through the watched
file.

`Panel.qml` extends the shell's `Panel` base type from `qs.Ui`, which supplies
both the bar item and its dropdown from a single entry point — this is how
`omarchy.audio` is built (`kinds: ["bar-widget"]`, `entryPoints.barWidget:
"Panel.qml"`). No separate `panel` kind is declared.

## 4. Capture

`pick.sh`:

1. `pkill hyprpicker && exit 0` — **preserves the toggle**. Today's binding is
   `pkill hyprpicker || hyprpicker -a`, so a second press cancels an open
   picker. Without this, a second press spawns a second picker.
2. `color=$(hyprpicker -a)` — `-a` keeps autocopy, so the hex lands on the
   clipboard exactly as it does today. No `-n`: the bar swatch updating is the
   feedback that it was recorded, and Omarchy ships no notification here.
3. Append only if `$color` matches `^#[0-9A-Fa-f]{6}$`. Esc returns an empty
   string rather than an error, and this is the boundary between a subprocess
   and a file the shell parses, so it is validated regardless of how small the
   rest of the script is.

`printf '%s\t%s\n' "$(date +%s)" "$color" >> "$HISTORY"` — a sub-4KB append is
atomic on Linux, so concurrent picks cannot interleave and no lockfile is
needed.

## 5. Storage

`~/.local/state/omarchy/color-history.tsv`, alongside the first-party
`clipboard-history.json`:

```
1756200000	#FF0044
1756200041	#22CC88	*
```

Column 3 is the star marker; **absent means unstarred**, which is why
`pick.sh` never has to know that starring exists. Read with
`FileView { watchChanges: true; atomicWrites: true }` — the pattern
`omarchy.clipboard` uses.

The shell is the only writer of stars, deletes, and clears, and all three are
the same operation: rewrite the file from the in-memory model. Clear-all is
`rows.filter(r => r.starred)`.

`pick.sh` appends while the shell rewrites, which is a lost-update race in
principle. In practice hyprpicker owns the screen while picking, so the grid
cannot be clicked at that moment. No locking; a `ponytail:` comment names the
ceiling.

Format preference lives in `~/.local/state/omarchy/color-history-format`
(`hex`|`rgb`|`hsl`), a one-line second `FileView`. Quickshell's
`PersistentProperties` survives config reloads but not restarts, and a header
line in the TSV would stop `pick.sh` from being a pure append.

## 6. Binds

`Service.qml`, on load:

```lua
hyprctl eval 'hl.unbind("SUPER + PRINT") ;
              hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("<dir>/pick.sh"),
                      { description = "Color picker" }) ;
              hl.unbind("SUPER + SHIFT + PRINT") ;
              hl.bind("SUPER + SHIFT + PRINT",
                      hl.dsp.exec_cmd("omarchy-shell shell toggle <id>"),
                      { description = "Color history" }) ;
              return "ok"'
```

**Not `hyprctl keyword`.** Omarchy drives Hyprland with the Lua config parser,
which refuses keyword outright — *"keyword can't work with non-legacy parsers.
Use eval."* — and exits 0 while doing it. The first build of this plugin used
keyword and therefore installed, enabled, and did nothing, with no error
anywhere. The service now checks that hyprctl replies `ok` and logs a warning if
it does not, because a silent failure here disables the entire plugin.

A newly installed plugin's service is mounted at the next shell start, so
`omarchy plugin add` must be followed by `omarchy restart shell` before any of
this exists.

`SUPER+SHIFT+PRINT` is free (`SUPER+CTRL+PRINT` is OCR). `bindd` carries a
description, and `omarchy-menu-keybindings` reads `hyprctl binds`, so both
appear under `SUPER+K` with their labels.

Runtime binds die with the session and are re-registered on every shell start,
so there is no persistent state to clean up. A stale bind survives until the
shell is restarted after disabling the plugin — the one accepted rough edge.

## 7. Grid

Shared by `Panel.qml` and `Overlay.qml` via `ColorGrid.qml`:

- **Order** — starred colors pinned in a section at the top, in pick-time
  order, most recent first; the timeline below, same ordering. Pin order needs
  no fourth column because star-time ordering is a distinction you would never
  notice.
- **Click** — copies in the active format, closes the surface.
- **Format cycle** — `hex` / `rgb` / `hsl` toggle; `Qt.color()` does the math.
  Type-to-filter matches the *displayed* format, not the stored hex.
- **Star** — pins; survives clear-all. A re-picked starred color stays pinned
  and does not create a second row.
- **Delete** — works on starred colors directly. Requiring unstar-first guards
  against a mistake that costs one re-pick.
- **Clear all** — no confirmation dialog. It only ever destroys unstarred rows;
  starring *is* the confirmation step.
- **Keyboard** — arrows move, Enter copies, Esc closes, typing filters.
- Colors come from the shell theme singleton. Swatches need a border, or a
  color near the theme background becomes invisible.

## 8. Deferred

- **Git and identity.** The repo is not initialized and the GitHub handle is
  unconfirmed, so the manifest ships `io.github.arcanavox.colorhistory` as a
  placeholder. It becomes the on-disk directory name at
  `omarchy plugin add` time — change it before publishing.
- **`preview.png`.** Nothing in `omarchy-plugin-catalog` reads it; it is for the
  repo README, so it waits until there is something to screenshot.
- **Render cap.** The grid renders everything. If a 3000-swatch grid ever
  stutters, add `.slice(0, 200)` — when measured, not before.
- **Colors picked outside the plugin.** A bare `hyprpicker` in a terminal, or
  the `trigger.capture.color` menu row, records nothing. Both are fixable in
  three README lines by anyone who cares.

## 9. Tests

`ClipboardHistory.js` is plain JS with pure functions, and `ColorHistory.js`
follows it, so the model is testable without a shell:

- `ColorHistory.test.js` under `node --test` (node 24 is present): dedup keeps
  the most recent, stars pin to the top, clear-all keeps starred rows, delete
  removes a starred row, filter matches the displayed format.
- `test.sh` puts a stub `hyprpicker` on `PATH` and asserts the TSV after a
  successful pick, a cancel (empty output), and a garbage return.


## 10. Revision — 2026-08-26, after first use

Three things were wrong on first run, and the surface was not what was wanted.

**`hyprctl keyword` does not work here.** Omarchy drives Hyprland with the Lua
config parser, which refuses keyword outright while exiting 0. Replaced with
`hyprctl eval` and the `hl.bind` / `hl.unbind` API Omarchy's own bindings use;
`Service.qml` now checks that hyprctl replies `ok` and warns if it does not.

**A new plugin's service is not mounted until the shell restarts.** So
`omarchy plugin add` alone leaves the plugin enabled and inert.
`omarchy restart shell` is now a required install step in the README.

**The bar widget had no `implicitWidth`.** The bar sizes each slot from its
widget's implicit size, so the widget was 0 wide and invisible. `omarchy.power`
shows the pattern: `implicitWidth: batteryPresent ? button.implicitWidth : 0`.
The same expression, keyed on an empty history, is also what gives the requested
behavior — the widget appears only once there is a color to show, and the bar
closes the gap when there is not.

**Overlay dropped; the panel is the only surface.** The history now opens from
the bar the way audio, network and power do, and `SUPER+SHIFT+PRINT` reaches it
through the Panel base's IPC target rather than summoning a separate plugin.
`kinds` is `["service", "bar-widget"]`, `Overlay.qml` is gone, and `ColorGrid`
became `ColorList`: `CursorSurface` rows, swatch on the left, value beside it,
newest at the top and starred above that.

The consequence worth knowing: the keybinding needs the widget to be in the bar,
since that is the object holding the IPC target.


## 11. Revision — 2026-08-27, marketplace review

The marketplace maintainer applied `needs-fixes` to submission #2658:

> the always-loaded ColorState FileViews materialize the predictable history and
> format files without byte or file-type bounds, while pick.sh appends through an
> ordinary redirection. A planted FIFO can block the shared shell or picker, and
> a planted symlink can redirect the append into another user file.

Both are real. The state paths are predictable and sit in a directory anything
running as the user can write, and the reader is a shell process shared by the
whole desktop — so a FIFO there is a denial of service against the bar, the lock
screen and notifications, not just this plugin.

**`safeio.py`** now performs every read, append and whole-file write:
`O_NOFOLLOW` (the final component may not be a symlink), `O_NONBLOCK` (opening a
FIFO cannot park the caller), `S_ISREG` (whatever opened must be an ordinary
file), and a 4 MiB ceiling. Writes go to a fresh file in the same directory and
are renamed over the target, so a planted symlink is replaced rather than
followed. `pick.sh` appends through it instead of `>>`. This mirrors the
`safeRead` idiom in `io.github.weedwhitesandwine.plug`.

**`FileView` is gone**, which cost the change watch. `pick.sh` now calls
`omarchy-shell <id> refresh` after appending, and the panel reloads whenever it
opens. Correctness never depends on the notification arriving — every read
re-reads the file whole.

Going async surfaced two races that `FileView` had been hiding, both caught by
driving the real component in a throwaway Quickshell instance:

- **A mutation before the first read lands** saw `rows === []` — empty because
  nothing had been read, not because the history was empty — and persisted that,
  truncating the file. Guarded by `loaded`: `save()` refuses until a read has
  answered. A dropped star is a repeatable click; a truncated history is not.
- **A reload issued just after a write** read the pre-write bytes and reverted
  the model, and the next save would have persisted the revert — resurrecting a
  deleted color. A generation counter alone did not fix this, because the stale
  read *starts* after the write is issued. Reads now wait for writes to drain
  (`writesInFlight()` / `reloadQueued`).
