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
//   gif      scripted tour of the views, one png per state -> $OUT/NNNN.png + $OUT/list.txt
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
    readonly property string moduleName: "gusthx.google-calendar"
    readonly property string gcalBinPath: shell.mockBin
    function triggerSync() {}
    function reloadEventsCache() {}
  }

  readonly property var panelSettings: ({
    id: "gusthx.google-calendar",
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

      readonly property var panel: calPanel
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
          id: "gusthx.google-calendar",
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
  property var sceneLoader: null

  // GIF: one frame per state of a scripted tour, each held for its own time
  // (an ffmpeg concat list), so the machine renders ~10 frames instead of
  // ~100 near-identical ones. The panel's height changes with the view: a
  // first pass walks the tour without grabbing to find the tallest state,
  // the second grabs every state on a frame of that fixed size, the panel
  // pinned to its top.
  property int gifHeight: 10
  readonly property int gifSettle: 700
  Component {
    id: gifStage
    Rectangle {
      color: Commons.Color.background
      width: gifLoader.item ? gifLoader.item.width + 24 : 10
      height: shell.gifHeight
      clip: true
      Component.onCompleted: shell.stage = this
      Loader {
        id: gifLoader
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        sourceComponent: panelScene
        Component.onCompleted: shell.sceneLoader = gifLoader
      }
    }
  }

  property var gifToday: null
  // [action, seconds on screen]. The GIF loops back to the first state, so
  // the tour does not return to the Week view itself. ffmpeg's concat list
  // repeats the last frame (see below), which shows it twice as long: ~10 s
  // in all.
  readonly property var gifTour: [
    [function(p) { p.cancelAddingEvent(); p.setViewMode("week"); p.selectDate(gifToday.y, gifToday.m, gifToday.d) }, 1.8],
    [function(p) { p.setViewMode("day") }, 1.3],
    [function(p) { p.startAddingEvent(14) }, 0.6],
    [function(p) { p.newEventTitleText = "Coffee with the team" }, 1.5],
    [function(p) { p.cancelAddingEvent(); p.setViewMode("month") }, 1.4],
    [function(p) { p.moveDay(1) }, 0.6],
    [function(p) { p.moveDay(1) }, 1.0],
    [function(p) { p.setViewMode("year") }, 1.0]
  ]
  property int gifPass: 0   // 0 measuring, 1 grabbing
  property int gifIndex: 0
  property string gifList: ""
  function gifPanel() { return sceneLoader && sceneLoader.item ? sceneLoader.item.panel : null }
  function gifFile(i) { return ("000" + i).slice(-4) + ".png" }
  FileView { id: listFile; path: shell.mode === "gif" ? shell.out + "/list.txt" : ""; printErrors: false; blockWrites: true }
  function gifStart() {
    var p = gifPanel()
    if (!p) { console.warn("GIF no panel"); Qt.quit(); return }
    gifToday = { y: p.selectedYear, m: p.selectedMonth, d: p.selectedDay }
    gifPass = 0; gifIndex = 0
    gifTour[0][0](p)
    gifTimer.restart()
  }
  Timer {
    id: gifTimer
    interval: shell.gifSettle
    onTriggered: {
      var p = shell.gifPanel()
      if (shell.gifPass === 0) {
        shell.gifHeight = Math.max(shell.gifHeight, shell.sceneLoader.item.height + 24)
        shell.gifIndex++
        if (shell.gifIndex >= shell.gifTour.length) { shell.gifPass = 1; shell.gifIndex = 0 }
        shell.gifTour[shell.gifIndex][0](p)
        gifTimer.restart()
        return
      }
      var i = shell.gifIndex
      shell.stage.grabToImage(function(r) {
        r.saveToFile(shell.out + "/" + shell.gifFile(i))
        shell.gifList += "file '" + shell.gifFile(i) + "'\nduration " + shell.gifTour[i][1] + "\n"
        shell.gifIndex++
        if (shell.gifIndex >= shell.gifTour.length) {
          // The concat demuxer drops the last duration unless the file repeats.
          listFile.setText(shell.gifList + "file '" + shell.gifFile(i) + "'\n")
          Qt.quit()
        } else {
          shell.gifTour[shell.gifIndex][0](p)
          gifTimer.restart()
        }
      }, Qt.size(shell.stage.width * 1.5, shell.stage.height * 1.5))
    }
  }

  FloatingWindow {
    visible: true
    title: "gusthx.google-calendar dev"
    implicitWidth: offLoader.item ? offLoader.item.width : 10
    implicitHeight: offLoader.item ? offLoader.item.height : 10
    color: Commons.Color.background
    Loader { id: offLoader; sourceComponent: shell.mode === "gif" ? gifStage : stageComponent }
  }

  // Captures: let layout and fonts settle, then grab at 2x and quit (or start the GIF).
  Timer {
    running: shell.capturing
    interval: 2000
    onTriggered: shell.mode === "gif" ? shell.gifStart() : shell.save(shell.stage, shell.out, function() { Qt.quit() })
  }
}
