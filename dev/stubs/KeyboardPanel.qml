import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Dev-only stand-in for Ui.KeyboardPanel (a layer-shell PanelWindow, which
// Qt's offscreen platform cannot create). dev/run.sh swaps it into a shadow
// copy of Omarchy's Ui module for captures and the preview, so Panel.qml's
// content renders as a plain item: same card, padding, border and lazy
// content as the real one, minus screen placement and focus handling.
// `dev/run.sh check` compiles Panel.qml against the real KeyboardPanel.
BorderSurface {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property bool centerOnBar: false
  property var focusTarget: null
  property bool popoutSwitching: false
  property int margin: Style.gapsOut
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property Component content: null
  property bool contentRequested: false

  readonly property Item loadedContent: contentLoader.item
  readonly property real loadedContentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function ensureContent() {
    if (content) contentRequested = true
    return contentLoader.item
  }
  function fittedContentWidth(width, cap) {
    var w = Math.max(1, Number(width) || 1)
    if (cap !== undefined && Number(cap) > 0) w = Math.min(w, Number(cap))
    return Math.round(w)
  }
  function fittedContentHeight(implicitHeight, cap) {
    var h = Math.max(verticalContentInset, (Number(implicitHeight) || 0) + verticalContentInset)
    if (cap !== undefined && Number(cap) > 0) h = Math.min(h, Number(cap))
    return Math.round(h)
  }
  function cappedContentHeight(height) { return Math.round(Math.max(padding * 2, Number(height) || padding * 2)) }
  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }
  function beginFocusPrime() {}

  width: contentWidth
  height: contentHeight
  visible: open
  color: Commons.Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  padding: Style.spacing.popupPadding
  radius: Style.cornerRadius

  Item {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.topMargin: root.contentTopInset
    anchors.leftMargin: root.contentLeftInset
    width: root.contentWidth - root.contentLeftInset - root.contentRightInset
    height: root.contentHeight - root.contentTopInset - root.contentBottomInset

    Loader {
      id: contentLoader
      anchors.fill: parent
      focus: true
      active: !!root.content && (root.open || root.contentRequested)
      sourceComponent: root.content
    }
  }
}
