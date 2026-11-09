import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "plugin" as Plugin
import "plugin/Model.js" as Model

// Isolated dev harness. Runs in its own Quickshell instance (see dev/run.sh),
// never inside the live Omarchy shell, with MOCK events and a mock helper:
// it never reads your calendar, tokens or config, and never syncs.
//
// MODE (env):
//   preview  a window with the panel to click around in
//   panel    the panel in VIEW (day|week|month|year)  -> $OUT (png)
//   settings the panel with the sync settings drawer -> $OUT
//   event    the panel with the new-event drawer     -> $OUT
//   bar      the bar widget on a bar-like strip      -> $OUT
ShellRoot {
  id: shell

  readonly property string mode: Quickshell.env("MODE") || "preview"
  readonly property string out: Quickshell.env("OUT") || ""
  readonly property string view: Quickshell.env("VIEW") || "month"
  readonly property string mockBin: Quickshell.env("MOCK_GCAL") || ""
  readonly property string stateDir: Quickshell.env("OMARCHY_GCAL_STATE_DIR") || ""
  readonly property bool capturing: mode !== "preview"

  FileView {
    id: eventsFile
    path: shell.stateDir !== "" ? shell.stateDir + "/events.json" : ""
    blockLoading: true
    printErrors: false
  }
  readonly property var payload: Model.parseEventsPayload(eventsFile.text())

  // What the bar widget hands its panel, minus anything that runs a process.
  QtObject {
    id: mockHost
    readonly property string moduleName: "gusthx.clock"
    readonly property string gcalBinPath: shell.mockBin
    function triggerSync() {}
    function reloadEventsCache() {}
  }

  readonly property var panelSettings: ({
    id: "gusthx.clock",
    defaultViewMode: shell.view,
    autoSync: false,
    notificationsEnabled: false,
    gcalBinPath: shell.mockBin,
    birthYear: 1990,
    lifeExpectancy: 85
  })

  function save(item, path, done) {
    item.grabToImage(function(r) {
      r.saveToFile(path)
      if (done) done()
    }, Qt.size(item.width * 2, item.height * 2))
  }

  // The KeyboardPanel stand-in (dev/stubs) inside Panel.qml: the item that
  // has the card's size.
  function cardOf(panelItem) {
    if (!panelItem) return null
    for (var i = 0; i < panelItem.children.length; i++)
      if (panelItem.children[i].loadedContent !== undefined) return panelItem.children[i]
    return null
  }

  Component {
    id: panelScene
    Item {
      id: scene
      readonly property Item card: shell.cardOf(calPanel)
      width: card ? card.width : 10
      height: card ? card.height : 10

      Plugin.Panel {
        id: calPanel
        hostWidget: mockHost
        settings: shell.panelSettings
        calendarPayload: shell.payload
        Component.onCompleted: {
          open()
          if (shell.mode === "settings") Qt.callLater(toggleSyncSettings)
          else if (shell.mode === "event") Qt.callLater(function() { startAddingEvent(14) })
        }
      }
    }
  }

  Component {
    id: barScene
    Rectangle {
      width: barWidget.implicitWidth + 160
      height: Commons.Style.bar.sizeHorizontal + 16
      color: Commons.Color.background
      Plugin.BarWidget {
        id: barWidget
        anchors.centerIn: parent
        height: Commons.Style.bar.sizeHorizontal
        settings: ({
          id: "gusthx.clock",
          autoSync: false,
          notificationsEnabled: false,
          showBarEventBadge: true,
          gcalBinPath: shell.mockBin,
          format: "ddd d MMM HH:mm"
        })
      }
    }
  }

  Component {
    id: stageComponent
    Rectangle {
      color: shell.capturing ? Commons.Color.background : "transparent"
      width: loader.item ? loader.item.width + (shell.capturing ? 24 : 0) : 10
      height: loader.item ? loader.item.height + (shell.capturing ? 24 : 0) : 10
      Component.onCompleted: shell.stage = this
      Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: shell.mode === "bar" ? barScene : panelScene
      }
    }
  }
  property Item stage: null

  FloatingWindow {
    visible: true
    title: "gusthx.clock dev"
    implicitWidth: offLoader.item ? offLoader.item.width : 10
    implicitHeight: offLoader.item ? offLoader.item.height : 10
    color: Commons.Color.background
    Loader { id: offLoader; sourceComponent: stageComponent }
  }

  // One-shot captures: let layout and fonts settle, grab at 2x, quit.
  Timer {
    running: shell.capturing
    interval: 2000
    onTriggered: shell.save(shell.stage, shell.out, function() { Qt.quit() })
  }
}
