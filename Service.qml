import QtQuick
import Quickshell
import Quickshell.Io

// Owns the keybindings.
//
// `omarchy plugin add` clones, validates and enables — it never runs a line of
// plugin code, so there is no install hook to write ~/.config/hypr/bindings.lua
// from. The binds are registered here instead, at shell start: nothing on disk
// to keep idempotent, nothing to clean up on uninstall, and they re-register on
// every shell start.
//
// They go in through `hyprctl eval`, not `hyprctl keyword`. Omarchy configures
// Hyprland with the Lua parser, and keyword is refused outright there —
// "keyword can't work with non-legacy parsers. Use eval." — while still exiting
// 0, so a keyword-based version fails silently and completely. The Lua API is
// the same one Omarchy's own bindings use: hl.unbind(keys) and hl.bind(keys,
// dispatcher, opts).
//
// Disabling the plugin leaves the binds live until the shell restarts. That is
// the one accepted rough edge: the honest alternatives are guessing at what
// SUPER+PRINT was bound to before, or running `hyprctl reload` on every shell
// shutdown.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.arcanavox.colorhistory"
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

  // The command lands inside a Lua string literal.
  function luaString(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
  }

  function bindLua(keys, description, command) {
    return 'hl.unbind(' + luaString(keys) + ') ; '
      + 'hl.bind(' + luaString(keys) + ', hl.dsp.exec_cmd(' + luaString(command) + '), '
      + '{ description = ' + luaString(description) + ' })'
  }

  // Unbind before binding: Hyprland stacks a second handler on a key rather
  // than replacing the first, so binding alone would open two pickers per
  // press. The description is what omarchy-menu-keybindings shows under
  // SUPER+K, which reads `hyprctl binds`.
  readonly property string bindScript:
    bindLua("SUPER + PRINT", "Color picker", root.pluginDir + "/pick.sh") + ' ; '
    + bindLua("SUPER + SHIFT + PRINT", "Color history",
        "omarchy-shell " + root.pluginId + " toggle") + ' ; '
    + 'return "ok"'

  Process {
    id: bindProc
    command: ["hyprctl", "eval", root.bindScript]
    stdout: StdioCollector {
      waitForEnd: true
      // hyprctl exits 0 even when it refuses the request, so the reply text is
      // the only thing that says whether the binds actually exist. Without this
      // check the plugin installs, enables, and quietly does nothing.
      onStreamFinished: {
        var reply = String(text || "").trim()
        if (reply !== "ok")
          console.warn("colorhistory: keybindings not registered — hyprctl said: " + reply)
      }
    }
  }

  Component.onCompleted: bindProc.running = true
}
