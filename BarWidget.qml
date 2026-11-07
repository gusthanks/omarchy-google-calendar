import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui
import "Model.js" as Model

// Date/time label for the bar, and the host for the Google Calendar synced
// multi-view (Day / Week / Month / Year) calendar popup.
Ui.BarWidget {
  id: root
  moduleName: (settings && settings.id) ? settings.id : "omarchy-google-calendar"

  Commons.Translations {
    id: tr
    directory: Qt.resolvedUrl("i18n")
  }

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd dd MMM h:mm AP")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))
  readonly property string activeFormat: configuredFormat
  readonly property bool showsSeconds: Model.clockNeedsSeconds(activeFormat)

  // ---- Google Calendar state & upcoming event summary for the top bar
  readonly property string gcalBinPath: {
    var custom = setting("gcalBinPath", "")
    if (custom !== "") return custom
    return Qt.resolvedUrl("omarchy-gcal").toString().replace(/^file:\/\//, "")
  }
  readonly property string gcalCachePath: Quickshell.env("HOME") + "/.local/state/omarchy/gcal/events.json"
  readonly property bool autoSyncEnabled: setting("autoSync", true) !== false
  readonly property int syncIntervalMinutes: Math.max(1, parseInt(setting("syncIntervalMinutes", 10), 10) || 10)
  readonly property bool showBarEventBadge: setting("showBarEventBadge", false) === true
  readonly property bool notificationsEnabled: setting("notificationsEnabled", true) !== false
  readonly property int notifyBeforeMinutes: Math.max(0, parseInt(setting("notifyBeforeMinutes", 10), 10) || 10)

  property var calendarPayload: Model.parseEventsPayload("")
  property bool syncing: false
  property var notifiedEventKeys: ({})

  readonly property var upcomingSummary: Model.upcomingEventSummary(calendarPayload.eventsByDate, displayDate, 720)
  readonly property string baseDisplayText: formatted(displayDate)
  readonly property string displayText: {
    if (vertical) return baseDisplayText
    if (showBarEventBadge && upcomingSummary.barBadgeText !== "")
      return baseDisplayText + "  󰃭 " + Model.neutralizeMarkup(upcomingSummary.barBadgeText, 24)
    return baseDisplayText
  }
  readonly property var verticalLines: displayText.split("\n")

  function checkMeetingNotifications() {
    if (!root.notificationsEnabled || root.notifyBeforeMinutes < 0) return
    var todayKey = Model.keyForDate(root.displayDate)
    var todayEvents = Model.eventsForDateKey(root.calendarPayload ? root.calendarPayload.eventsByDate : null, todayKey)
    var nowMinutes = root.displayDate.getHours() * 60 + root.displayDate.getMinutes()

    var updatedKeys = null
    for (var i = 0; i < todayEvents.length; i++) {
      var ev = todayEvents[i]
      if (ev.allDay) continue
      var eff = Model.effectiveMinutesForDate(ev, todayKey)
      var diff = eff.startMinutes - nowMinutes
      if (diff >= 0 && diff <= root.notifyBeforeMinutes) {
        var notifKey = String(ev.id || (ev.startDate + "_" + ev.startTime + "_" + ev.title))
        if (root.notifiedEventKeys[notifKey]) continue

        if (!updatedKeys) updatedKeys = Object.assign({}, root.notifiedEventKeys)
        updatedKeys[notifKey] = true

        var title = tr.t("notify.upcomingMeeting")
          .arg(Commons.I18n.formatNumber(diff))
          .arg(ev.startTime)
        var body = Model.neutralizeMarkup(ev.title, 80)
        if (ev.location) body += "\n📍 " + Model.neutralizeMarkup(ev.location, 80)
        else if (ev.meetLink) body += "\n󰌹 " + Model.neutralizeMarkup(ev.meetLink, 80)

        var meetUrl = ev.actionUrl || ev.meetLink || ev.htmlLink || ""
        var cmd = ["omarchy-notification-send", "--app-name", "Google Calendar", "-g", "󰸗", "-u", "normal", title, body]
        if (meetUrl !== "") {
          cmd.push("--exec", "omarchy-launch-browser", meetUrl)
        }
        Quickshell.execDetached(cmd)
      }
    }
    if (updatedKeys) {
      root.notifiedEventKeys = updatedKeys
    }
  }

  readonly property string barTooltipText: {
    var baseTip = I18n.t("clock.toggleFormat")
    if (upcomingSummary.activeEvent) {
      var actLine = tr.t("events.happeningNow").arg(
        Model.neutralizeMarkup(upcomingSummary.activeEvent.title, 48)
      )
      return Model.neutralizeMarkup(actLine + " · " + baseTip, 180)
    }
    if (upcomingSummary.nextEvent) {
      var timePrefix = upcomingSummary.nextIsTomorrow ? (tr.t("nav.tomorrow") + " ") : ""
      var nxtLine = tr.t("events.upcoming").arg(
        timePrefix + upcomingSummary.nextEvent.startTime + " " + Model.neutralizeMarkup(upcomingSummary.nextEvent.title, 48)
      )
      return Model.neutralizeMarkup(nxtLine + " · " + baseTip, 180)
    }
    if (upcomingSummary.todayCount > 0) {
      var cntLine = tr.tn("events.count", upcomingSummary.todayCount).arg(
        Commons.I18n.formatNumber(upcomingSummary.todayCount)
      )
      return Model.neutralizeMarkup(cntLine + " · " + baseTip, 180)
    }
    return Model.neutralizeMarkup(baseTip, 180)
  }

  property FileView eventsCacheFile: FileView {
    path: root.gcalCachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.calendarPayload = Model.parseEventsPayload(text())
      root.injectPanel()
    }
    onLoadFailed: {
      root.calendarPayload = Model.parseEventsPayload("")
      root.injectPanel()
    }
  }

  Process {
    id: bgSyncProc
    command: [root.gcalBinPath, "sync", "--quiet"]
    onStarted: {
      root.syncing = true
      root.injectPanel()
    }
    onExited: {
      root.syncing = false
      eventsCacheFile.reload()
      root.injectPanel()
    }
  }

  Timer {
    id: syncTimer
    interval: root.syncIntervalMinutes * 60 * 1000
    running: root.autoSyncEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.triggerSync()
  }

  function triggerSync() {
    if (!bgSyncProc.running) {
      bgSyncProc.running = true
    }
  }

  function reloadEventsCache() {
    eventsCacheFile.reload()
  }

  function refresh() {
    displayDate = new Date()
    eventsCacheFile.reload()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  readonly property var formatLocale: Qt.locale(I18n.formatLocale)

  function formatted(date) {
    var week = Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())
    week = week.split("").map(function(digit) { return I18n.formatNumber(digit) }).join("")
    return date.toLocaleString(root.formatLocale, activeFormat.replace(/ww/g, week))
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  function setViewMode(mode) {
    if (panelLoader.item && panelLoader.item.setViewMode) panelLoader.item.setViewMode(mode)
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("moduleName" in target && root.moduleName !== "") target.moduleName = root.moduleName
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("calendarPayload" in target) target.calendarPayload = root.calendarPayload
    if ("syncing" in target) target.syncing = root.syncing
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onModuleNameChanged: injectPanel()
  onSettingsChanged: injectPanel()

  WallClock {
    id: clock
    step: root.showsSeconds ? 1000 : 60000
    onDateChanged: {
      root.displayDate = date
      root.checkMeetingNotifications()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  ShellIpc {
    target: root.moduleName

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function setViewMode(mode: string): void { root.setViewMode(mode) }
    function syncCalendar(): void { root.triggerSync() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  ShellIpc {
    target: "omarchy.clock"
    enabled: root.moduleName !== "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function setViewMode(mode: string): void { root.setViewMode(mode) }
    function syncCalendar(): void { root.triggerSync() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  ShellIpc {
    target: "omarchy-google-calendar"
    enabled: root.moduleName !== "omarchy-google-calendar" && root.moduleName !== "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function setViewMode(mode: string): void { root.setViewMode(mode) }
    function syncCalendar(): void { root.triggerSync() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.barTooltipText
    pressFeedbackButtons: Qt.NoButton

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.togglePanel()
    }

    // Subtle accent dot in the top-right corner of the clock slot when there
    // are events scheduled today and the text badge is not already shown.
    Rectangle {
      visible: root.upcomingSummary.hasEventsToday && (root.vertical || root.upcomingSummary.barBadgeText === "")
      width: Style.space(5)
      height: Style.space(5)
      radius: width / 2
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(5)
      anchors.rightMargin: Style.space(4)
      color: Commons.Color.accent
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
