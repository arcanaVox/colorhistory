# Color History

Keeps every color you pick with `hyprpicker`, ready to copy back as hex, `rgb()`
or `hsl()`. An Omarchy 4 shell plugin.

`SUPER+PRINT` picks a color exactly as it did before — the hex still lands on
your clipboard — and now also records it.

Once you have picked something, a swatch of that color appears in the bar next
to wifi and sound. Click it (or press `SUPER+SHIFT+PRINT`) and the history drops
down from the bar like those panels do: newest first, one row per color, swatch
on the left and the value beside it. With no history the widget hides itself
entirely, and the bar closes the gap.

## Install

```bash
omarchy plugin add https://github.com/<you>/colorhistory.git --enable
omarchy restart shell
```

The restart is not optional. Services are mounted when the shell starts, so a
freshly installed plugin's keybindings do not exist until it comes back up —
`omarchy plugin add` alone leaves you with a plugin that is enabled and inert.

Check it took:

```bash
hyprctl binds -j | jq -r '.[] | select(.description|test("Color")) | .description'
# Color picker
# Color history
```

## Using it

| | |
|---|---|
| `SUPER+PRINT` | Pick a color. Press again to cancel. |
| `SUPER+SHIFT+PRINT` | Open the panel. Same as clicking the bar swatch. |
| `enter` / click | Copy the selected color in the active format, and close. |
| `ctrl+s` / right-click | Star a color. Starred colors pin to the top and survive a clear. |
| `del` | Remove the selected color. |
| `shift+del` | Clear everything except starred colors. No confirmation — starring is the confirmation. |
| `ctrl+f` | Cycle hex → rgb → hsl. The format chip does the same. |
| type | Filter, matching the format as displayed: `255` finds things while `rgb` is active. |
| `esc` | Clear the filter, or close. |
| `tab` | Move to the next bar panel, as everywhere else in the bar. |

## Where things live

`~/.local/state/omarchy/color-history.tsv`, one line per pick:

```
1756200000	#FF0044
1756200041	#22CC88	*
```

Append-only from the picker's side; a third column marks a star. The format
preference sits next to it in `color-history-format`. Delete either file to
start over — nothing else on your system is touched.

The bar widget is the panel: `SUPER+SHIFT+PRINT` reaches it over IPC, so the
widget has to be placed in your bar for the keybinding to have anything to open.
`omarchy plugin add --enable` puts it there; `omarchy plugin disable` takes it
out again.

## What it does not catch

Colors picked by running `hyprpicker` yourself in a terminal, or from the
Omarchy menu's **Capture → Color** row, are not recorded. Only the keybinding
routes through this plugin.

To record the menu row too, reuse its id in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"trigger.capture.color": {
  "icon": "󰃉",
  "label": "Color",
  "action": "~/.config/omarchy/plugins/io.github.arcanavox.colorhistory/pick.sh"
}
```

## Keybindings

The plugin registers its two binds through `hyprctl eval` when the shell
starts, rather than editing `~/.config/hypr/bindings.lua`. (`hyprctl keyword`
is refused under Omarchy's Lua config parser — "keyword can't work with
non-legacy parsers" — and it exits 0 while refusing, so anything built on it
fails silently.) Nothing is written to your config,
and removing the plugin needs no cleanup — but the binds do stay live until the
next shell restart after you disable it.

To put them somewhere else, unbind and rebind in your own `bindings.lua`; your
config loads after the plugin, so it wins:

```lua
hl.unbind("SUPER + PRINT")
o.bind("SUPER + F12", "Color picker", "~/.config/omarchy/plugins/io.github.arcanavox.colorhistory/pick.sh")
```

## Tests

```bash
./test.sh        # pick.sh against a stubbed hyprpicker
node --test      # the parse/dedup/star/format model
```
