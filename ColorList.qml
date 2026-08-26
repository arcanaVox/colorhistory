import QtQuick
import qs.Commons
import qs.Ui
import "."

// The history, as rows: swatch on the left, the value beside it, newest at the
// top and starred colors above that. Rows follow the shell's CursorSurface
// contract, so the highlight behaves the way it does in the audio and network
// panels — one cursor on screen, driven by keyboard and mouse alike.
Item {
  id: root

  property color foreground: Color.foreground
  property color background: Color.background
  property string fontFamily: Style.font.family
  property real maxListHeight: Style.space(260)
  property bool showHints: true

  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var entries: []

  readonly property int count: entries.length
  readonly property var selectedEntry: selectedIndex >= 0 && selectedIndex < entries.length
    ? entries[selectedIndex] : null

  implicitHeight: column.implicitHeight

  signal closeRequested()

  function refresh() {
    var next = ColorState.display(root.filterText)
    root.entries = next
    if (root.selectedIndex >= next.length) root.selectedIndex = Math.max(0, next.length - 1)
    if (root.selectedIndex < 0) root.selectedIndex = 0
    Qt.callLater(function() {
      if (list.count > 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function reset() {
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.refresh()
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.refresh()
  }

  function move(delta) {
    if (root.count === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? root.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + root.count) % root.count
    }
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function copySelected() {
    if (!root.selectedEntry) return
    ColorState.copy(root.selectedEntry.hex)
    root.closeRequested()
  }

  function starSelected() {
    if (!root.selectedEntry) return
    ColorState.toggleStar(root.selectedEntry.hex)
    root.refresh()
  }

  function removeSelected() {
    if (!root.selectedEntry) return
    ColorState.removeColor(root.selectedEntry.hex)
    root.refresh()
  }

  function clearAll() {
    ColorState.clearUnstarred()
    root.selectedIndex = 0
    root.refresh()
  }

  // Returns true when the key was ours, so the host keeps the keys it needs
  // (Tab for panel switching) instead of losing them.
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.filterText) root.setFilter("")
      else root.closeRequested()
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      root.setFilter(root.filterText.slice(0, -1))
      return true
    }
    if (event.key === Qt.Key_Up) { root.move(-1); return true }
    if (event.key === Qt.Key_Down) { root.move(1); return true }
    if (event.key === Qt.Key_PageUp) { root.move(-5); return true }
    if (event.key === Qt.Key_PageDown) { root.move(5); return true }
    if (event.key === Qt.Key_Home) { root.cursorActive = true; root.selectedIndex = 0; root.refresh(); return true }
    if (event.key === Qt.Key_End) { root.cursorActive = true; root.selectedIndex = root.count - 1; root.refresh(); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.cursorActive) root.copySelected()
      else if (root.count > 0) { root.cursorActive = true; root.selectedIndex = 0 }
      return true
    }
    if (event.key === Qt.Key_Delete) {
      if (event.modifiers & Qt.ShiftModifier) root.clearAll()
      else root.removeSelected()
      return true
    }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) { root.starSelected(); return true }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
      ColorState.cycleFormat()
      root.refresh()
      return true
    }
    // Printable characters filter. Ctrl-modified keys are left alone so the
    // host keeps its own shortcuts.
    if (!(event.modifiers & Qt.ControlModifier) && event.text
        && event.text.length === 1 && event.text.charCodeAt(0) >= 32
        && event.text.charCodeAt(0) !== 127) {
      root.setFilter(root.filterText + event.text)
      return true
    }
    return false
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: ColorState
    function onRowsChanged() { root.refresh() }
    function onFormatChanged() { root.refresh() }
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.spacing.md

    // ---------- Header: filter · format chip · clear ----------
    Item {
      width: parent.width
      height: Style.space(22)

      Text {
        anchors.left: parent.left
        anchors.right: formatChip.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: root.filterText || "Colors"
        color: root.foreground
        opacity: root.filterText ? 1 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Rectangle {
        id: formatChip
        anchors.right: clearChip.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        width: formatText.implicitWidth + Style.spacing.md * 2
        height: parent.height
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
        color: formatMouse.containsMouse ? Style.hoverFill : Style.normalFill

        Text {
          id: formatText
          anchors.centerIn: parent
          text: ColorState.format
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: formatMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { ColorState.cycleFormat(); root.refresh() }
        }
      }

      Rectangle {
        id: clearChip
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: height
        height: parent.height
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
        color: clearMouse.containsMouse ? Style.hoverFill : Style.normalFill

        Text {
          anchors.centerIn: parent
          text: "󰩹"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearAll()
        }
      }
    }

    // ---------- Rows ----------
    ListView {
      id: list
      width: parent.width
      height: Math.min(contentHeight, root.maxListHeight)
      model: root.entries
      clip: true
      spacing: Style.spacing.xxs
      boundsBehavior: Flickable.StopAtBounds

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index

        width: list.width
        implicitHeight: rowInner.implicitHeight + Style.spacing.lg
        hasCursor: root.cursorActive && root.selectedIndex === index
        foreground: root.foreground

        Row {
          id: rowInner
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(26)
            height: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(3)
            color: row.modelData.hex
            // A swatch close to the panel background would be an invisible hole
            // without this, so the outline takes whichever of the theme's own
            // colors contrasts with the swatch itself.
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(ColorState.isLight(row.modelData.hex)
              ? root.background : root.foreground, 0.45)
          }

          Text {
            width: parent.width - Style.space(26) - Style.space(8) - starMark.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: starMark
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12)
            horizontalAlignment: Text.AlignHCenter
            text: row.modelData.starred ? "★" : ""
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onEntered: { root.cursorActive = true; root.selectedIndex = row.index }
          onClicked: function(mouse) {
            root.cursorActive = true
            root.selectedIndex = row.index
            if (mouse.button === Qt.RightButton) root.starSelected()
            else root.copySelected()
          }
        }
      }
    }

    // ---------- Hints ----------
    Text {
      width: parent.width
      visible: root.showHints && root.count > 0
      text: "click copy · right-click star · del remove"
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
