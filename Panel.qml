import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "."

// Bar item plus the panel that drops from it — the shape omarchy.audio,
// omarchy.network and omarchy.power use, so this opens and behaves like the
// wifi and sound panels next to it.
//
// The widget only exists while there is something to show. omarchy.power hides
// itself the same way when there is no battery: zero implicit size collapses
// the bar slot, because the bar sizes each slot from its widget's implicitWidth.
Panel {
  id: root
  moduleName: "io.github.arcanavox.colorhistory"
  ipcTarget: "io.github.arcanavox.colorhistory"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits — the base's handler has no refresh, and pick.sh needs one to tell
  // a running shell that it just appended a color.
  manageIpc: false

  implicitWidth: ColorState.empty ? 0 : button.implicitWidth
  implicitHeight: ColorState.empty ? 0 : button.implicitHeight
  visible: !ColorState.empty

  // Reload on open as well as on pick.sh's callback, so the panel is correct
  // even when that callback never arrived — the shell was not running, the
  // widget was not in the bar, or the file was edited by hand.
  onOpenedChanged: if (opened) { ColorState.reload(); list.reset() }

  IpcHandler {
    target: "io.github.arcanavox.colorhistory"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { ColorState.reload() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃉"
    iconComponent: ColorState.empty ? null : swatchIcon
    tooltipText: ColorState.empty ? "" : ColorState.label(ColorState.lastColor)
    onPressed: root.toggle()
  }

  // The bar icon is the last color you picked.
  Component {
    id: swatchIcon

    Rectangle {
      anchors.centerIn: parent
      width: parent.width
      height: parent.height * 0.8
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(3)
      color: ColorState.lastColor || "transparent"
      // Without the outline a picked color close to the bar background is an
      // invisible hole where the widget should be.
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(root.barForeground, 0.5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && !ColorState.empty
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(list.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // Tab belongs to the bar, which cycles between open panels with it.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          event.accepted = true
          return
        }
        if (list.handleKey(event)) event.accepted = true
      }

      ColorList {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        foreground: root.bar ? root.bar.foreground : Color.foreground
        background: Color.popups.background
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onCloseRequested: root.close()
      }
    }
  }
}
