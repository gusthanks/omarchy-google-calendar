import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.Ui as Ui
import "Model.js" as Model

// Google Calendar synced multi-view (Day / Week / Month / Year) popup panel
// for the Omarchy clock widget.
Ui.Panel {
  id: root
  moduleName: (hostWidget && hostWidget.moduleName) ? hostWidget.moduleName : "gusthx.clock"
  ipcTarget: (hostWidget && hostWidget.moduleName) ? hostWidget.moduleName : "gusthx.clock"
  manageIpc: false

  Commons.Translations {
    id: tr
    directory: Qt.resolvedUrl("i18n")
  }

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string gcalBinPath: (hostWidget && hostWidget.gcalBinPath)
    ? hostWidget.gcalBinPath
    : Qt.resolvedUrl("omarchy-gcal").toString().replace(/^file:\/\//, "")

  // ---- Today & WallClock
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property int nowMinutes: today.getHours() * 60 + today.getMinutes()

  // ---- Selected Date & Active View Mode ("day" | "week" | "month" | "year")
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property int selectedYear: today.getFullYear()
  property int selectedMonth: today.getMonth()
  property int selectedDay: today.getDate()
  readonly property string selectedKey: Model.dateKey(selectedYear, selectedMonth, selectedDay)
  readonly property date selectedDateObj: new Date(selectedYear, selectedMonth, selectedDay, 12)

  readonly property string viewMode: Model.normalizeViewMode(setting("defaultViewMode", "month"))
  readonly property bool autoSyncEnabled: setting("autoSync", true) !== false
  readonly property bool showBarEventBadge: (settings && "showBarEventBadge" in settings) ? Boolean(settings.showBarEventBadge) : false
  readonly property int syncIntervalMinutes: {
    var raw = Number(setting("syncIntervalMinutes", 10))
    if (isNaN(raw) || raw < 1) return 10
    return Math.min(120, Math.round(raw))
  }

  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
  readonly property bool viewingCurrentContext: {
    if (viewMode === "day") return selectedKey === todayKey
    if (viewMode === "week") return selectedKey === todayKey
    if (viewMode === "year") return viewYear === today.getFullYear()
    return viewYear === today.getFullYear() && viewMonth === today.getMonth() && selectedKey === todayKey
  }

  // ---- Year progress & Memento Mori (preserved from stock omarchy.clock)
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // ---- Google Calendar state injected from BarWidget (with local fallback)
  property var calendarPayload: Model.parseEventsPayload("")
  property bool syncing: false
  property bool addingEvent: false
  property bool isDraggingGhost: false
  property bool newEventAllDay: false
  property bool newEventAddMeet: false
  property string draftDateKey: ""
  property int draftStartMinutes: 9 * 60
  property int draftEndMinutes: 10 * 60
  property string newEventTitleText: ""
  property string newEventLocationText: ""
  property string newEventDescriptionText: ""
  property bool showingSyncSettings: false
  property bool showingSearch: false
  property string searchQuery: ""

  function toggleSearch() {
    root.showingSearch = !root.showingSearch
    if (root.showingSearch) {
      root.showingSyncSettings = false
      root.addingEvent = false
      root.searchQuery = ""
    }
  }

  readonly property var eventsByDate: calendarPayload && calendarPayload.eventsByDate
    ? calendarPayload.eventsByDate
    : ({})
  readonly property var selectedDayEvents: Model.eventsForDateKey(eventsByDate, selectedKey)

  readonly property string syncStatusLabel: {
    var src = calendarPayload ? String(calendarPayload.source || "local") : "local"
    if (src === "oauth") return tr.t("sync.statusOAuth")
    if (src === "ics") return tr.t("sync.statusIcs")
    if (src === "gcalcli") return tr.t("sync.statusGcalcli")
    return tr.t("sync.statusLocal")
  }

  // ---- Locale & Labels
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), labelLocale.firstDayOfWeek)
  readonly property var labelLocale: Qt.locale(Commons.I18n.formatLocale)
  readonly property string monthYearLabel: tr.t("clock.monthYear")
    .arg(labelLocale.standaloneMonthName(viewMonth, Locale.LongFormat))
    .arg(viewDate.toLocaleDateString(labelLocale, "yyyy"))
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)

  // ---- View Models for Month, Week, Day, Year
  readonly property var monthWeeks: Model.monthGridWithEvents(
    viewYear, viewMonth, weekStart, todayKey, selectedKey, eventsByDate
  )
  readonly property var weekData: Model.weekViewModel(
    selectedYear, selectedMonth, selectedDay, weekStart, todayKey, selectedKey, eventsByDate, nowMinutes
  )
  readonly property var dayData: Model.dayViewModel(
    selectedYear, selectedMonth, selectedDay, todayKey, nowMinutes, eventsByDate
  )
  readonly property var yearMonths: Model.yearViewModel(
    viewYear, weekStart, todayKey, selectedKey, eventsByDate
  )

  readonly property string weekRangeLabel: {
    var sDate = new Date(weekData.startYear, weekData.startMonth, weekData.startDay, 12)
    var eDate = new Date(weekData.endYear, weekData.endMonth, weekData.endDay, 12)
    var sText = sDate.toLocaleDateString(labelLocale, "d MMM")
    var eText = eDate.toLocaleDateString(labelLocale, "d MMM")
    return tr.t("nav.weekLabel")
      .arg(Commons.I18n.formatNumber(weekData.week))
      .arg(sText + " – " + eText)
  }

  readonly property string dayHeaderLabel: {
    var dText = selectedDateObj.toLocaleDateString(labelLocale, tr.t("clock.dayMonthFormat"))
    var wName = labelLocale.dayName(dayData.weekday, Locale.LongFormat)
    var rel = ""
    if (dayData.dayDiff === 0) rel = " · " + tr.t("nav.today")
    else if (dayData.dayDiff === 1) rel = " · " + tr.t("nav.tomorrow")
    else if (dayData.dayDiff === -1) rel = " · " + tr.t("nav.yesterday")
    return wName + ", " + dText + rel
  }

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int fullGridWidth: Style.space(496)
  readonly property int weekColumnWidth: Style.space(28)
  readonly property int gutterWidth: Style.space(10)
  readonly property int cellSpacing: Style.space(2)
  readonly property int cellWidth: Math.floor((fullGridWidth - weekColumnWidth - gutterWidth - 8 * cellSpacing) / 7)
  readonly property int cellHeight: Style.space(34)

  // ---- Panel Lifecycle & Navigation
  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) root.cancelEditingLife()
    if (root.addingEvent) root.cancelAddingEvent()
    if (root.showingSyncSettings) root.showingSyncSettings = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    if (root.hostWidget && typeof root.hostWidget.reloadEventsCache === "function")
      root.hostWidget.reloadEventsCache()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedYear = today.getFullYear()
    root.selectedMonth = today.getMonth()
    root.selectedDay = today.getDate()
  }

  function selectDate(year, month, day) {
    var clamped = Model.clampDay(year, month, day)
    root.selectedYear = year
    root.selectedMonth = month
    root.selectedDay = clamped
    root.viewYear = year
    root.viewMonth = month
  }

  function setViewMode(mode) {
    var normalized = Model.normalizeViewMode(mode)
    if (normalized === root.viewMode) return
    persistSettings({ defaultViewMode: normalized })
    Qt.callLater(function() {
      var content = panel.loadedContent
      if (!content) return
      if (root.addingEvent) content.eventTitleField.forceActiveFocus()
      else if (root.showingSyncSettings) content.icsUrlField.forceActiveFocus()
      else if (root.editingLife) content.bornField.forceActiveFocus()
      else content.forceActiveFocus()
    })
  }

  function cycleViewMode(direction) {
    setViewMode(Model.nextViewMode(root.viewMode, direction))
  }

  function moveMonth(delta) {
    var next = Model.stepMonthDate(viewYear, viewMonth, selectedDay, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    root.selectedYear = next.year
    root.selectedMonth = next.month
    root.selectedDay = next.day
  }

  function moveYear(delta) {
    var next = Model.stepYearDate(viewYear, viewMonth, selectedDay, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    root.selectedYear = next.year
    root.selectedMonth = next.month
    root.selectedDay = next.day
  }

  function moveDay(delta) {
    var next = Model.stepDay(selectedYear, selectedMonth, selectedDay, delta)
    selectDate(next.year, next.month, next.day)
  }

  function moveWeek(delta) {
    var next = Model.stepWeek(selectedYear, selectedMonth, selectedDay, delta)
    selectDate(next.year, next.month, next.day)
  }

  function stepActiveView(delta) {
    if (root.viewMode === "day") moveDay(delta)
    else if (root.viewMode === "week") moveWeek(delta)
    else if (root.viewMode === "year") moveYear(delta)
    else moveMonth(delta)
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function standaloneMonthShort(m) {
    return String(labelLocale.standaloneMonthName(m, Locale.ShortFormat)).toUpperCase()
  }

  function standaloneMonthLong(m) {
    return String(labelLocale.standaloneMonthName(m, Locale.LongFormat)).toUpperCase()
  }

  // ---- Memento Mori Editing
  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      var content = panel.loadedContent
      if (!content) return
      var bornField = content.bornField
      var expectancyField = content.expectancyField
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var content = panel.loadedContent
    if (!content) return
    var bornField = content.bornField
    var expectancyField = content.expectancyField
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  // ---- Google Calendar Actions (Add Event, Delete Event, Sync, Configure)
  property var locationSuggestions: []
  property bool searchingLocation: false
  property string draftMeetCode: ""
  property bool meetCopied: false
  property real selectedLocationLat: 0.0
  property real selectedLocationLon: 0.0
  property int mapZoom: 15

  Timer {
    id: copyResetTimer
    interval: 2000
    repeat: false
    onTriggered: { root.meetCopied = false }
  }

  Process {
    id: geocodeProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        root.searchingLocation = false
        try {
          var items = JSON.parse(text || "[]")
          root.locationSuggestions = Array.isArray(items) ? items : []
        } catch (e) {
          root.locationSuggestions = []
        }
      }
    }
    onExited: {
      root.searchingLocation = false
    }
  }

  Timer {
    id: locationDebounceTimer
    interval: 350
    repeat: false
    onTriggered: {
      var q = root.newEventLocationText.trim()
      if (q.length < 3) {
        root.locationSuggestions = []
        return
      }
      root.searchingLocation = true
      geocodeProc.command = [root.gcalBinPath, "geocode", q, "--limit", "4"]
      geocodeProc.running = true
    }
  }

  function applyLocationSuggestion(item) {
    if (!item) return
    root.newEventLocationText = item.full || (item.title + (item.address ? (", " + item.address) : ""))
    if (typeof item.lat === "number" && typeof item.lon === "number" && (item.lat !== 0 || item.lon !== 0)) {
      root.selectedLocationLat = item.lat
      root.selectedLocationLon = item.lon
      root.mapZoom = 15
    }
    root.locationSuggestions = []
  }

  Process {
    id: actionProc
    onExited: {
      if (root.hostWidget && typeof root.hostWidget.reloadEventsCache === "function")
        root.hostWidget.reloadEventsCache()
    }
  }

  function triggerManualSync() {
    if (root.hostWidget && typeof root.hostWidget.triggerSync === "function")
      root.hostWidget.triggerSync()
    else if (!actionProc.running) {
      actionProc.command = [root.gcalBinPath, "sync", "--quiet"]
      actionProc.running = true
    }
  }

  function startAddingEvent(presetHour) {
    var startStr = (typeof presetHour === "number" && presetHour >= 0 && presetHour <= 23)
      ? Model.pad2(presetHour) + ":00"
      : "09:00"
    var endStr = (typeof presetHour === "number" && presetHour >= 0 && presetHour <= 23)
      ? Model.pad2(Math.min(23, presetHour + 1)) + ":00"
      : "10:00"
    root.startAddingEventWithRange(root.selectedKey, startStr, endStr)
  }

  function startAddingEventWithRange(dateKey, startTimeStr, endTimeStr) {
    root.showingSyncSettings = false
    root.showingSearch = false
    if (!root.addingEvent) {
      root.newEventAllDay = false
      root.newEventAddMeet = false
      root.newEventTitleText = ""
      root.newEventLocationText = ""
      root.newEventDescriptionText = ""
      root.draftMeetCode = ""
      root.meetCopied = false
      root.selectedLocationLat = 0.0
      root.selectedLocationLon = 0.0
      root.mapZoom = 15
      root.locationSuggestions = []
    }
    root.draftDateKey = dateKey || root.selectedKey
    if (dateKey) {
      var p = Model.parseDateKey(dateKey)
      if (p) root.selectDate(p.year, p.month, p.day)
    }
    var sm = Model.parseMinutes(startTimeStr || "09:00")
    if (sm < 0) sm = 9 * 60
    var em = Model.parseMinutes(endTimeStr || "10:00")
    if (em <= sm) em = Math.min(1440, sm + 60)
    root.draftStartMinutes = sm
    root.draftEndMinutes = em
    root.addingEvent = true
    root.isDraggingGhost = false
    Qt.callLater(function() {
      var content = panel.loadedContent
      if (content && content.eventTitleField) {
        content.eventTitleField.forceActiveFocus()
      }
    })
  }

  function cancelAddingEvent() {
    root.addingEvent = false
    root.isDraggingGhost = false
    root.newEventAddMeet = false
    root.newEventTitleText = ""
    root.newEventLocationText = ""
    root.newEventDescriptionText = ""
    root.draftMeetCode = ""
    root.meetCopied = false
    root.selectedLocationLat = 0.0
    root.selectedLocationLon = 0.0
    root.mapZoom = 15
    root.locationSuggestions = []
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  function handleEventFormKey(event, prevField, nextField) {
    if (event.key === Qt.Key_Escape) {
      root.cancelAddingEvent()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitNewEvent()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      if (nextField) nextField.forceActiveFocus()
      event.accepted = true
    } else if (event.key === Qt.Key_Backtab) {
      if (prevField) prevField.forceActiveFocus()
      event.accepted = true
    }
  }

  function commitNewEvent() {
    var rawTitle = root.newEventTitleText.trim()
    var title = rawTitle !== "" ? rawTitle : tr.t("events.untitled")
    var validated = Model.validateQuickEvent({
      title: title,
      dateKey: root.draftDateKey || root.selectedKey,
      startTime: Model.formatMinutes(root.draftStartMinutes),
      endTime: Model.formatMinutes(root.draftEndMinutes),
      allDay: root.newEventAllDay,
      location: root.newEventLocationText,
      description: root.newEventDescriptionText,
      addMeet: root.newEventAddMeet
    })
    if (!validated.valid) return
    var cmd = [
      root.gcalBinPath, "add",
      "--title", validated.title,
      "--date", validated.dateKey
    ]
    if (validated.allDay) {
      cmd.push("--all-day")
    } else {
      cmd.push("--start", validated.startTime, "--end", validated.endTime)
    }
    if (validated.location !== "") {
      cmd.push("--location", validated.location)
    }
    if (validated.description !== "") {
      cmd.push("--description", validated.description)
    }
    if (validated.addMeet) {
      cmd.push("--add-meet")
      if (root.draftMeetCode) {
        cmd.push("--meet-url", "https://meet.google.com/" + root.draftMeetCode)
      }
    }
    actionProc.command = cmd
    actionProc.running = true
    var parsedDate = Model.parseDateKey(validated.dateKey)
    if (parsedDate) selectDate(parsedDate.year, parsedDate.month, parsedDate.day)
    cancelAddingEvent()
  }

  function toggleAutoSync() {
    persistSettings({ autoSync: !root.autoSyncEnabled })
  }

  function deleteEvent(eventId) {
    var cleanId = String(eventId || "").trim()
    if (!cleanId || actionProc.running) return
    actionProc.command = [root.gcalBinPath, "delete", "--id", cleanId]
    actionProc.running = true
  }

  function updateEventTime(eventId, dateKey, startTime, endTime) {
    var cleanId = String(eventId || "").trim()
    if (!cleanId || actionProc.running) return
    var cmd = [root.gcalBinPath, "update", "--id", cleanId, "--start", startTime, "--end", endTime]
    if (dateKey) cmd.push("--date", String(dateKey).trim())
    actionProc.command = cmd
    actionProc.running = true
  }

  function openExternalUrl(url) {
    var safe = Model.sanitizeHttpsUrl(url)
    if (!safe) return
    Quickshell.execDetached(["xdg-open", safe])
  }

  function toggleSyncSettings() {
    if (root.addingEvent) root.addingEvent = false
    root.showingSyncSettings = !root.showingSyncSettings
    if (root.showingSyncSettings) {
      Qt.callLater(function() {
        var content = panel.loadedContent
        if (!content) return
        content.icsUrlField.text = (root.calendarPayload && root.calendarPayload.icsUrl) ? root.calendarPayload.icsUrl : ""
        content.icsUrlField.forceActiveFocus()
      })
    } else {
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    }
  }

  function saveIcsUrl() {
    var content = panel.loadedContent
    if (!content) return
    var rawUrl = String(content.icsUrlField.text || "").trim()
    actionProc.command = [root.gcalBinPath, "set-ics", rawUrl]
    actionProc.running = true
    root.showingSyncSettings = false
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  function launchOAuthSetup() {
    Quickshell.execDetached(["omarchy-launch-tui", root.gcalBinPath, "auth"])
  }

  Timer {
    id: clock
    property int step: 60000
    property date date: new Date()
    function arm() {
      interval = Model.msUntilNextTick(Date.now(), step)
      restart()
    }
    onStepChanged: arm()
    onTriggered: {
      date = new Date()
      var dateChanged = Model.keyForDate(clock.date) !== String(root.todayKey)
      var followToday = dateChanged && root.viewingCurrentContext
      root.today = clock.date
      if (followToday) root.goToToday()
      arm()
    }
    Component.onCompleted: arm()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias bornField: bornField
      property alias expectancyField: expectancyField
      property alias eventTitleField: eventTitleInput
      property alias eventDateField: eventDateInput
      property alias eventStartField: eventStartInput
      property alias eventEndField: eventEndInput
      property alias eventLocationField: eventLocationInput
      property alias eventDescriptionField: eventDescriptionInput
      property alias icsUrlField: icsUrlField
      property alias searchField: searchField

      implicitHeight: calendarColumn.implicitHeight
      anchors.fill: parent
      blocked: root.addingEvent
        || root.isDraggingGhost
        || bornField.activeFocus
        || expectancyField.activeFocus
        || eventTitleInput.activeFocus
        || eventDateInput.activeFocus
        || eventStartInput.activeFocus
        || eventEndInput.activeFocus
        || eventLocationInput.activeFocus
        || eventDescriptionInput.activeFocus
        || icsUrlField.activeFocus
        || searchField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepActiveView(dx)
        if (dy !== 0) {
          if (root.viewMode === "day") root.moveWeek(dy)
          else if (root.viewMode === "week") root.moveMonth(dy)
          else root.moveYear(dy)
        }
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: {
        if (root.showingSearch) root.showingSearch = false
        else if (root.addingEvent) root.cancelAddingEvent()
        else if (root.showingSyncSettings) root.toggleSyncSettings()
        else if (root.editingLife) root.cancelEditingLife()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[" || t === "h") root.stepActiveView(-1)
        else if (t === "]" || t === "l") root.stepActiveView(1)
        else if (t === "j") {
          if (root.viewMode === "day") root.moveWeek(1)
          else if (root.viewMode === "week") root.moveMonth(1)
          else root.moveYear(1)
        }
        else if (t === "k") {
          if (root.viewMode === "day") root.moveWeek(-1)
          else if (root.viewMode === "week") root.moveMonth(-1)
          else root.moveYear(-1)
        }
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "/") root.toggleSearch()
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "1" || t === "d" || t === "D") root.setViewMode("day")
        else if (t === "2" || t === "w") root.setViewMode("week")
        else if (t === "W") {
          if (root.viewMode !== "week") root.setViewMode("week")
          else root.toggleWeekStart()
        }
        else if (t === "3" || t === "m" || t === "M") root.setViewMode("month")
        else if (t === "4" || t === "y" || t === "Y") root.setViewMode("year")
        else if (t === "v") root.cycleViewMode(1)
        else if (t === "V") root.cycleViewMode(-1)
        else if (t === "n" || t === "N" || t === "+") root.startAddingEvent(-1)
        else if (t === "r" || t === "R") root.triggerManualSync()
        else if (t === "s" || t === "S") root.toggleSyncSettings()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.addingEvent && !root.isDraggingGhost && (root.viewMode !== "week" && root.viewMode !== "day") && (contentHeight > height || contentWidth > width)

        Column {
          id: calendarColumn
          width: Math.max(calendarScroll.width, root.fullGridWidth)
          spacing: Style.space(8)

          // ---- Hero: Today, centered. Clicking returns to Today.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                textFormat: Text.PlainText
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 44
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.toLocaleDateString(root.labelLocale, tr.t("clock.dayMonthFormat"))
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 48
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentContext
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: tr.t("clock.backToToday")
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress rail (double-tap opens Memento Mori editor)
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(2)
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: tr.t("clock.born")
                  textFormat: Text.PlainText
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: tr.t("clock.year")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly
                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: tr.t("clock.liveTo")
                  textFormat: Text.PlainText
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly
                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Commons.I18n.formatNumber(root.today.getFullYear())
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Commons.I18n.formatNumber(root.yearDonePercent) + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento Mori rail
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: tr.t("clock.life")
                textFormat: Text.PlainText
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Commons.I18n.formatNumber(root.lifeDonePercent) + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: tr.t("clock.mementoMori")
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- View Mode Switcher (Dia | Semana | Mês | Ano) + Google Calendar Toolbar
          Item {
            width: parent.width
            height: modeBar.height + Style.space(4)

            Item {
              id: modeBar
              y: Style.space(4)
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: Style.space(26)

              // Left Group: Segmented View Mode Switcher (Day | Week | Month | Year)
              Rectangle {
                id: modeSegmentContainer
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(26)
                width: modeSegmentRow.implicitWidth + Style.space(4)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                Row {
                  id: modeSegmentRow
                  anchors.centerIn: parent
                  spacing: 0

                  Repeater {
                    id: segRepeater
                    model: [
                      { mode: "day", labelKey: "view.day", tipKey: "view.dayTooltip" },
                      { mode: "week", labelKey: "view.week", tipKey: "view.weekTooltip" },
                      { mode: "month", labelKey: "view.month", tipKey: "view.monthTooltip" },
                      { mode: "year", labelKey: "view.year", tipKey: "view.yearTooltip" }
                    ]

                    Rectangle {
                      id: segRect
                      required property var modelData
                      required property int index
                      readonly property bool isActive: root.viewMode === modelData.mode
                      width: Style.space(40)
                      height: Style.space(22)
                      radius: Math.max(2, Style.cornerRadius - 2)
                      color: isActive
                        ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)
                        : (segMouse.containsMouse
                          ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                          : "transparent")
                      border.width: isActive ? Style.spacing.hairline : 0
                      border.color: Commons.Color.accent

                      // Subtle divider line between inactive segments
                      Rectangle {
                        visible: segRect.index > 0 && !segRect.isActive && (root.viewMode !== segRepeater.model[segRect.index - 1].mode)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.spacing.hairline
                        height: Style.space(12)
                        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)
                      }

                      Text {
                        id: segLabel
                        anchors.centerIn: parent
                        text: tr.t(modelData.labelKey)
                        color: isActive
                          ? Commons.Color.accent
                          : (segMouse.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 1.4))
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: isActive
                      }

                      MouseArea {
                        id: segMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setViewMode(modelData.mode)

                        PanelToolTip {
                          visible: segMouse.containsMouse
                          text: tr.t(modelData.tipKey)
                          fontFamily: root.contentFontFamily
                        }
                      }
                    }
                  }
                }
              }

              // Right Group: Standardized Action Toolbar (Today | + Event | Divider | Sync | Search | Settings)
              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  id: todayBtn
                  height: Style.space(26)
                  text: tr.t("nav.today")
                  tooltipText: tr.t("nav.goToToday")
                  bordered: true
                  opacity: root.viewingCurrentContext ? 0.65 : 1.0
                  foreground: root.viewingCurrentContext ? root.contentForeground : Commons.Color.accent
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  onClicked: root.goToToday()
                }

                Button {
                  id: addEventBtn
                  height: Style.space(26)
                  text: tr.t("events.addShort")
                  tooltipText: tr.t("events.add")
                  selected: root.addingEvent
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  onClicked: {
                    if (root.addingEvent) root.cancelAddingEvent()
                    else root.startAddingEvent(-1)
                  }
                }

                // Subtle vertical divider between actions and utility tools
                Rectangle {
                  width: Style.spacing.hairline
                  height: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.16)
                }

                Button {
                  width: Style.space(26)
                  height: Style.space(26)
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: "󰑐"
                  iconSpinning: root.syncing
                  tooltipText: root.syncing ? tr.t("sync.syncing") : tr.t("sync.button")
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  onClicked: root.triggerManualSync()
                }

                Button {
                  width: Style.space(26)
                  height: Style.space(26)
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: "󰍉"
                  selected: root.showingSearch
                  tooltipText: tr.t("search.button")
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  onClicked: root.toggleSearch()
                }

                Button {
                  width: Style.space(26)
                  height: Style.space(26)
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: "󰒓"
                  selected: root.showingSyncSettings
                  tooltipText: tr.t("sync.settings")
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  onClicked: root.toggleSyncSettings()
                }

                Button {
                  width: Style.space(26)
                  height: Style.space(26)
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: "󰊭"
                  tooltipText: tr.t("action.openWeb")
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  onClicked: root.openExternalUrl("https://calendar.google.com/calendar/u/0/r")
                }
              }
            }
          }

          // ---- Search Drawer (when search button or '/' is active)
          Item {
            visible: root.showingSearch
            width: parent.width
            height: visible ? searchCard.height + Style.space(4) : 0

            BorderSurface {
              id: searchCard
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: searchCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              borderSpec: Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)

              Column {
                id: searchCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: searchField
                    width: parent.width - closeSearchBtn.width - Style.space(6)
                    placeholderText: tr.t("search.placeholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    onTextChanged: { root.searchQuery = text }
                  }

                  Button {
                    id: closeSearchBtn
                    iconText: "󰅖"
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(4)
                    onClicked: { root.showingSearch = false }
                  }
                }

                Text {
                  visible: root.searchQuery.trim() !== "" && searchRepeater.count === 0
                  textFormat: Text.PlainText
                  width: parent.width
                  text: tr.t("search.noResults")
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  id: searchRepeater
                  model: root.searchQuery.trim() !== ""
                    ? Model.searchEvents(root.calendarPayload ? root.calendarPayload.events : [], root.searchQuery).slice(0, 6)
                    : []

                  Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: searchRowMouse.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
                      : "transparent"

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(8)

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.startDate
                        color: Commons.Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.allDay ? tr.t("events.allDay") : (modelData.startTime || "--:--")
                        color: Qt.darker(root.contentForeground, 1.4)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width - Style.space(170)
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.neutralizeMarkup(modelData.title || tr.t("events.untitled"), 50)
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        visible: Boolean(modelData.meetLink || modelData.location)
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.meetLink ? "󰌹 Meet" : "📍"
                        color: Qt.darker(root.contentForeground, 1.6)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: searchRowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var parsed = Model.parseDateKey(modelData.startDate)
                        if (parsed) {
                          root.selectedYear = parsed.year
                          root.selectedMonth = parsed.month
                          root.selectedDay = parsed.day
                          root.selectedKey = modelData.startDate
                          root.setViewMode("day")
                          root.showingSearch = false
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Google Calendar Settings Drawer (when gear button is active)
          Item {
            visible: root.showingSyncSettings
            width: parent.width
            height: visible ? settingsCard.height + Style.space(4) : 0

            BorderSurface {
              id: settingsCard
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: settingsCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              borderSpec: Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)

              Column {
                id: settingsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(8)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: (root.calendarPayload && root.calendarPayload.connected)
                      ? "#33b679"
                      : Commons.Color.accent
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.syncStatusLabel
                      + ((root.calendarPayload && root.calendarPayload.syncedAtShort)
                        ? " · " + tr.t("sync.lastSync").arg(root.calendarPayload.syncedAtShort)
                        : "")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                Row {
                  visible: Boolean(root.calendarPayload && root.calendarPayload.lastError)
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: "󰅚"
                    color: "#e67c73"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width - Style.space(24)
                    wrapMode: Text.WordWrap
                    text: root.calendarPayload ? root.calendarPayload.lastError : ""
                    color: "#e67c73"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: tr.t("sync.icsLabel")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: icsUrlField
                    width: parent.width - saveIcsBtn.width - Style.space(6)
                    placeholderText: tr.t("sync.icsPlaceholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        root.toggleSyncSettings()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.saveIcsUrl()
                        event.accepted = true
                      }
                    }
                  }

                  Button {
                    id: saveIcsBtn
                    text: tr.t("sync.saveIcs")
                    bordered: true
                    selected: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(5)
                    onClicked: root.saveIcsUrl()
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: tr.t("sync.icsHint")
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: root.contentForeground
                  opacity: 0.12
                }

                // Periodic background refresh disclosure & toggle (per Omarchy plugin safety rules)
                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - autoSyncToggleBtn.width - Style.space(8)
                    wrapMode: Text.WordWrap
                    text: tr.t("sync.autoSyncLabel").arg(Commons.I18n.formatNumber(root.syncIntervalMinutes))
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Button {
                    id: autoSyncToggleBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.autoSyncEnabled ? tr.t("sync.autoSyncOn") : tr.t("sync.autoSyncOff")
                    selected: root.autoSyncEnabled
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: {
                      root.toggleAutoSync()
                      icsUrlField.forceActiveFocus()
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: root.contentForeground
                  opacity: 0.12
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - barBadgeToggleBtn.width - Style.space(8)
                    wrapMode: Text.WordWrap
                    text: tr.t("sync.showBarEventBadge")
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Button {
                    id: barBadgeToggleBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.showBarEventBadge ? tr.t("toggle.on") : tr.t("toggle.off")
                    selected: root.showBarEventBadge
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    onClicked: {
                      root.persistSettings({ showBarEventBadge: !root.showBarEventBadge })
                      icsUrlField.forceActiveFocus()
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.spacing.hairline
                  color: root.contentForeground
                  opacity: 0.12
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Column {
                    width: parent.width - oauthBtn.width - closeCfgBtn.width - Style.space(16)
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      text: tr.t("sync.oauthLabel")
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      wrapMode: Text.WordWrap
                      text: tr.t("sync.oauthHint")
                      color: Qt.darker(root.contentForeground, 1.6)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Button {
                    id: oauthBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: tr.t("sync.connectOAuth")
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(5)
                    onClicked: root.launchOAuthSetup()
                  }

                  Button {
                    id: closeCfgBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: tr.t("sync.closeSettings")
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(5)
                    onClicked: root.toggleSyncSettings()
                  }
                }
              }
            }
          }



          // ==================================================================
          // VIEW 1: MONTH VIEW ("month")
          // ==================================================================
          Item {
            visible: root.viewMode === "month"
            width: parent.width
            height: visible ? monthViewCol.height : 0

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: monthViewCol
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              spacing: Style.space(8)

              Item {
                width: parent.width
                height: gridColumn.height

                Column {
                  id: gridColumn
                  spacing: Style.space(3)

                  Row {
                    id: headerRow
                    spacing: root.cellSpacing

                    Rectangle {
                      width: root.weekColumnWidth
                      height: Style.space(16)
                      radius: Style.cornerRadius
                      color: weekStartMouse.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                        : "transparent"

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: tr.t("clock.weekShort")
                        color: weekStartMouse.containsMouse
                          ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                          : Qt.darker(root.contentForeground, 1.9)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                        font.bold: true
                      }

                      MouseArea {
                        id: weekStartMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleWeekStart()
                      }

                      PanelToolTip {
                        visible: weekStartMouse.containsMouse
                        text: tr.t("clock.startWeeksOn").arg(root.nextWeekStartLabel)
                        fontFamily: root.contentFontFamily
                      }
                    }

                    Item {
                      width: root.gutterWidth
                      height: Style.space(16)
                    }

                    Repeater {
                      model: root.weekdays

                      Text {
                        textFormat: Text.PlainText
                        required property var modelData
                        width: root.cellWidth
                        height: Style.space(16)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.weekdayLabel(modelData)
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                        font.bold: true
                      }
                    }
                  }

                  Repeater {
                    model: root.monthWeeks

                    Row {
                      required property var modelData
                      spacing: root.cellSpacing

                      Text {
                        textFormat: Text.PlainText
                        width: root.weekColumnWidth
                        height: root.cellHeight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Commons.I18n.formatNumber(modelData.week)
                        color: Qt.darker(root.contentForeground, 1.9)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Item {
                        width: root.gutterWidth
                        height: root.cellHeight
                      }

                      Repeater {
                        model: modelData.days

                        Rectangle {
                          required property var modelData

                          width: root.cellWidth
                          height: root.cellHeight
                          radius: Style.cornerRadius
                          color: dayCellMouse.containsMouse
                            ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                            : (modelData.selected
                              ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                              : "transparent")
                          border.width: (modelData.today || modelData.selected) ? Style.spacing.hairline : 0
                          border.color: modelData.today
                            ? Commons.Color.accent
                            : Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                          Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: modelData.hasEvents ? -Style.space(3) : 0
                            text: Commons.I18n.formatNumber(modelData.day)
                            color: modelData.selected
                              ? Style.selectedStateColor(root.contentForeground, Commons.Color.accent)
                              : (modelData.inMonth
                                ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                                : Qt.darker(root.contentForeground, 2.2))
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.body
                            font.bold: modelData.today || modelData.selected
                          }

                          // Event indicator dots
                          Row {
                            visible: modelData.hasEvents
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(4)
                            spacing: Style.space(3)

                            Repeater {
                              model: modelData.dotColors

                              Rectangle {
                                required property string modelData
                                width: Style.space(4)
                                height: Style.space(4)
                                radius: width / 2
                                color: modelData
                              }
                            }
                          }

                          MouseArea {
                            id: dayCellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectDate(modelData.year, modelData.month, modelData.day)
                            onDoubleClicked: {
                              root.selectDate(modelData.year, modelData.month, modelData.day)
                              root.setViewMode("day")
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Rectangle {
                  readonly property real gutterOffset: root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
                  x: LayoutMirroring.enabled
                    ? gridColumn.x + gridColumn.width - gutterOffset - width
                    : gridColumn.x + gutterOffset
                  y: gridColumn.y + headerRow.height + gridColumn.spacing
                  width: Style.spacing.hairline
                  height: gridColumn.height - headerRow.height - gridColumn.spacing
                  color: root.contentForeground
                  opacity: 0.1
                }
              }

              // Month stepper bar
              Item {
                width: parent.width
                height: monthLabel.implicitHeight + Style.space(10)

                Text {
                  id: monthLabel
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(200)
                  horizontalAlignment: Text.AlignHCenter
                  text: root.monthYearLabel.toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅂" : "󰅁"
                  tooltipText: tr.t("clock.previousMonth")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅁" : "󰅂"
                  tooltipText: tr.t("clock.nextMonth")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(1)
                }
              }
            }
          }

          // ==================================================================
          // VIEW 2: WEEK VIEW ("week")
          // ==================================================================
          Item {
            visible: root.viewMode === "week"
            width: parent.width
            height: visible ? weekViewCol.height : 0

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveWeek(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: weekViewCol
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              spacing: Style.space(6)

              readonly property int weekHourColWidth: Style.space(38)
              readonly property int weekColWidth: Math.floor((root.fullGridWidth - weekHourColWidth) / 7)
              readonly property int weekHourHeight: Style.space(32)

              // 1. Day headers row (SUN 1, MON 2, ...) aligned with the 7 columns
              Item {
                width: parent.width
                height: Style.space(38)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: weekViewCol.weekHourColWidth
                  anchors.right: parent.right
                  height: parent.height

                  Repeater {
                    model: root.weekData.days

                    Rectangle {
                      required property var modelData
                      width: weekViewCol.weekColWidth
                      height: parent.height
                      radius: Style.cornerRadius / 2
                      color: weekHeaderMouse.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                        : (modelData.selected
                          ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                          : "transparent")
                      border.width: (modelData.today || modelData.selected) ? Style.spacing.hairline : 0
                      border.color: modelData.today
                        ? Commons.Color.accent
                        : Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                      MouseArea {
                        id: weekHeaderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDate(modelData.year, modelData.month, modelData.day)
                        onDoubleClicked: {
                          root.selectDate(modelData.year, modelData.month, modelData.day)
                          root.setViewMode("day")
                        }
                      }

                      Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                          textFormat: Text.PlainText
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: root.weekdayLabel(modelData.weekday)
                          color: modelData.today ? Commons.Color.accent : Qt.darker(root.contentForeground, 1.5)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }

                        Text {
                          textFormat: Text.PlainText
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: Commons.I18n.formatNumber(modelData.day)
                          color: modelData.today ? Commons.Color.accent : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: modelData.today || modelData.selected
                        }
                      }
                    }
                  }
                }
              }

              // 2. All-day events row (if any day in the week has all-day events)
              Item {
                readonly property bool hasAllDay: {
                  for (var d = 0; d < root.weekData.days.length; d++) {
                    if (root.weekData.days[d].allDayEvents && root.weekData.days[d].allDayEvents.length > 0) return true
                  }
                  return false
                }
                visible: hasAllDay
                width: parent.width
                height: visible ? Style.space(26) : 0

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: weekViewCol.weekHourColWidth
                  anchors.right: parent.right
                  height: parent.height

                  Repeater {
                    model: root.weekData.days

                    Item {
                      required property var modelData
                      width: weekViewCol.weekColWidth
                      height: parent.height
                      clip: true

                      Repeater {
                        model: modelData.allDayEvents.slice(0, 1)

                        Rectangle {
                          required property var modelData
                          anchors.fill: parent
                          anchors.margins: Style.space(2)
                          radius: Math.max(2, Style.cornerRadius / 2)
                          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10)

                          Rectangle {
                            width: Style.space(3)
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: parent.radius
                            color: modelData.color || Commons.Color.accent
                          }

                          Text {
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(6)
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(2)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: modelData.title
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Math.max(9, Style.font.caption - 1)
                            font.bold: true
                          }

                          MouseArea {
                            id: weekAllDayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                              if (modelData.actionUrl !== "") root.openExternalUrl(modelData.actionUrl)
                            }
                            PanelToolTip {
                              visible: weekAllDayMouse.containsMouse
                              text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                              fontFamily: root.contentFontFamily
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // 3. Scrollable continuous 7-day timeline
              Flickable {
                id: weekTimelineFlick
                width: parent.width
                height: Style.space(240)
                contentWidth: width
                // Room above the first hour line so its label (drawn half above
                // the line) is never cut by the clip at the top.
                readonly property int topInset: Style.space(8)
                contentHeight: 24 * weekViewCol.weekHourHeight + 2 * topInset
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                function scrollToRelevantHour() {
                  var targetHour = Math.max(0, (root.weekData.firstEventHour || 8) - 1)
                  contentY = Math.max(0, Math.min(contentHeight - height, targetHour * weekViewCol.weekHourHeight))
                }

                Component.onCompleted: scrollToRelevantHour()

                Connections {
                  target: root
                  function onViewModeChanged() {
                    if (root.viewMode === "week") weekTimelineFlick.scrollToRelevantHour()
                  }
                  function onSelectedKeyChanged() {
                    if (root.viewMode === "week") weekTimelineFlick.scrollToRelevantHour()
                  }
                }

                Item {
                  id: weekCanvas
                  y: weekTimelineFlick.topInset
                  width: weekTimelineFlick.width
                  height: 24 * weekViewCol.weekHourHeight

                  // Horizontal grid lines & hour labels
                  Repeater {
                    model: 24

                    Item {
                      required property int index
                      width: weekCanvas.width
                      height: weekViewCol.weekHourHeight
                      y: index * weekViewCol.weekHourHeight

                      // Horizontal grid divider line across all 7 columns
                      Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: weekViewCol.weekHourColWidth
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Style.spacing.hairline
                        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                      }

                      // Hour label on left
                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: -Style.space(6)
                        width: weekViewCol.weekHourColWidth - Style.space(6)
                        horizontalAlignment: Text.AlignRight
                        text: Model.pad2(index) + ":00"
                        color: Qt.darker(root.contentForeground, 1.6)
                        font.family: root.contentFontFamily
                        font.pixelSize: Math.max(9, Style.font.caption - 1)
                      }
                    }
                  }

                  // 7 vertical day columns
                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: weekViewCol.weekHourColWidth
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    Repeater {
                      model: root.weekData.days

                      Item {
                        id: weekDayColItem
                        required property var modelData
                        width: weekViewCol.weekColWidth
                        height: parent.height

                        readonly property bool isCurrentDraftColumn: (root.addingEvent || root.isDraggingGhost) && root.draftDateKey === modelData.key

                        // Vertical divider line to right of day column
                        Rectangle {
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: Style.spacing.hairline
                          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                        }

                        // Background drag-to-create or click to add MouseArea
                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor

                          property real pressStartY: 0
                          property int dragAnchorMinutes: 0
                          property bool isDraggingRange: false

                          onPressed: function(mouse) {
                            pressStartY = mouse.y
                            var rawMin = Math.floor((mouse.y / weekViewCol.weekHourHeight) * 60)
                            dragAnchorMinutes = Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                            isDraggingRange = false
                          }

                          onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var diffY = mouse.y - pressStartY
                            if (!isDraggingRange && Math.abs(diffY) > 5) {
                              isDraggingRange = true
                              root.isDraggingGhost = true
                              weekTimelineFlick.interactive = false
                              root.draftDateKey = modelData.key
                              root.selectDate(modelData.year, modelData.month, modelData.day)
                            }
                            if (isDraggingRange) {
                              var currentRawMin = Math.floor((mouse.y / weekViewCol.weekHourHeight) * 60)
                              var snappedMin = Math.round(currentRawMin / 15) * 15
                              snappedMin = Math.max(0, Math.min(1440, snappedMin))

                              if (snappedMin >= dragAnchorMinutes) {
                                root.draftStartMinutes = dragAnchorMinutes
                                root.draftEndMinutes = Math.max(dragAnchorMinutes + 15, snappedMin)
                              } else {
                                root.draftStartMinutes = Math.min(dragAnchorMinutes - 15, snappedMin)
                                root.draftEndMinutes = dragAnchorMinutes
                              }
                            }
                          }

                          onReleased: function(mouse) {
                            weekTimelineFlick.interactive = true
                            root.isDraggingGhost = false
                            var dateKey = Model.dateKey(modelData.year, modelData.month, modelData.day)
                            root.selectDate(modelData.year, modelData.month, modelData.day)
                            if (isDraggingRange) {
                              // User dragged range — open options modal now
                              root.startAddingEventWithRange(dateKey, Model.formatMinutes(root.draftStartMinutes), Model.formatMinutes(root.draftEndMinutes))
                            } else {
                              // Single click on empty slot creates a 1-hour event block at that slot
                              var rawMin = (mouse && typeof mouse.y === "number") ? Math.floor((mouse.y / weekViewCol.weekHourHeight) * 60) : dragAnchorMinutes
                              var startMin = dragAnchorMinutes >= 0 ? dragAnchorMinutes : Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                              var endMin = Math.min(1440, startMin + 60)
                              root.startAddingEventWithRange(dateKey, Model.formatMinutes(startMin), Model.formatMinutes(endMin))
                            }
                            isDraggingRange = false
                          }

                          onDoubleClicked: function(mouse) {
                            weekTimelineFlick.interactive = true
                            root.isDraggingGhost = false
                            var dateKey = Model.dateKey(modelData.year, modelData.month, modelData.day)
                            root.selectDate(modelData.year, modelData.month, modelData.day)
                            var rawMin = (mouse && typeof mouse.y === "number") ? Math.floor((mouse.y / weekViewCol.weekHourHeight) * 60) : 9 * 60
                            var startMin = Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                            var endMin = Math.min(1440, startMin + 60)
                            root.startAddingEventWithRange(dateKey, Model.formatMinutes(startMin), Model.formatMinutes(endMin))
                          }
                        }

                        // Live Drag-to-Create Draft Card in Week View Column
                        Rectangle {
                          id: weekDraftCard
                          visible: weekDayColItem.isCurrentDraftColumn
                          z: 35
                          anchors.left: parent.left
                          anchors.leftMargin: 1
                          anchors.right: parent.right
                          anchors.rightMargin: 1
                          y: Math.round((root.draftStartMinutes / 60.0) * weekViewCol.weekHourHeight)
                          height: Math.max(Style.space(20), Math.round(((root.draftEndMinutes - root.draftStartMinutes) / 60.0) * weekViewCol.weekHourHeight) - 2)
                          radius: Math.max(2, Style.cornerRadius / 2)
                          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.28)
                          border.width: 1.5
                          border.color: Commons.Color.accent

                          Rectangle {
                            width: Style.space(3)
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: parent.radius
                            color: Commons.Color.accent
                          }

                          Column {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(5)
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(2)
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(2)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(2)
                            spacing: 0
                            clip: true

                            Text {
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: root.newEventTitleText !== "" ? root.newEventTitleText : tr.t("events.untitled")
                              color: root.contentForeground
                              font.family: root.contentFontFamily
                              font.pixelSize: Math.max(9, Style.font.caption - 1)
                              font.bold: true
                            }

                            Text {
                              visible: weekDraftCard.height >= Style.space(26)
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: Model.formatMinutes(root.draftStartMinutes) + " – " + Model.formatMinutes(root.draftEndMinutes)
                              color: Commons.Color.accent
                              font.family: root.contentFontFamily
                              font.pixelSize: Math.max(8, Style.font.caption - 2)
                              font.bold: true
                            }
                          }

                          // Drag card to adjust time position or shift days
                          MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: Style.space(10)
                            anchors.bottomMargin: Style.space(10)
                            hoverEnabled: true
                            cursorShape: Qt.SizeAllCursor

                            property real startCanvasY: 0
                            property int startMinVal: 0
                            property int endMinVal: 0

                            onPressed: function(mouse) {
                              weekTimelineFlick.interactive = false
                              root.isDraggingGhost = true
                              startCanvasY = mapToItem(weekCanvas, 0, mouse.y).y
                              startMinVal = root.draftStartMinutes
                              endMinVal = root.draftEndMinutes
                            }

                            onPositionChanged: function(mouse) {
                              if (!pressed) return
                              var currY = mapToItem(weekCanvas, 0, mouse.y).y
                              var deltaMin = Math.round((currY - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                              var duration = endMinVal - startMinVal
                              var candStart = Math.max(0, Math.min(1440 - duration, startMinVal + deltaMin))
                              root.draftStartMinutes = candStart
                              root.draftEndMinutes = candStart + duration

                              // Check if dragged horizontally to another day column
                              var currX = mapToItem(weekCanvas, mouse.x, 0).x - weekViewCol.weekHourColWidth
                              if (currX >= 0) {
                                var colIdx = Math.floor(currX / weekViewCol.weekColWidth)
                                if (colIdx >= 0 && colIdx < root.weekData.days.length) {
                                  var targetDay = root.weekData.days[colIdx]
                                  if (targetDay && targetDay.key !== root.draftDateKey) {
                                    root.draftDateKey = targetDay.key
                                    root.selectDate(targetDay.year, targetDay.month, targetDay.day)
                                  }
                                }
                              }
                            }

                            onReleased: function() {
                              weekTimelineFlick.interactive = true
                              root.isDraggingGhost = false
                            }
                          }

                          // Top resize handle with visible pill indicator
                          Item {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Style.space(10)
                            z: 40

                            Rectangle {
                              anchors.horizontalCenter: parent.horizontalCenter
                              anchors.top: parent.top
                              anchors.topMargin: Style.space(2)
                              width: Style.space(20)
                              height: Style.space(3)
                              radius: height / 2
                              color: Commons.Color.accent
                              opacity: 0.85
                            }

                            MouseArea {
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.SizeVerCursor

                              property real startCanvasY: 0
                              property int startMinVal: 0

                              onPressed: function(mouse) {
                                weekTimelineFlick.interactive = false
                                root.isDraggingGhost = true
                                startCanvasY = mapToItem(weekCanvas, 0, mouse.y).y
                                startMinVal = root.draftStartMinutes
                              }

                              onPositionChanged: function(mouse) {
                                if (!pressed) return
                                var currY = mapToItem(weekCanvas, 0, mouse.y).y
                                var deltaMin = Math.round((currY - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                var cand = Math.max(0, Math.min(root.draftEndMinutes - 15, startMinVal + deltaMin))
                                root.draftStartMinutes = cand
                              }

                              onReleased: function() {
                                weekTimelineFlick.interactive = true
                                root.isDraggingGhost = false
                              }
                            }
                          }

                          // Bottom resize handle with visible pill indicator
                          Item {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Style.space(10)
                            z: 40

                            Rectangle {
                              anchors.horizontalCenter: parent.horizontalCenter
                              anchors.bottom: parent.bottom
                              anchors.bottomMargin: Style.space(2)
                              width: Style.space(20)
                              height: Style.space(3)
                              radius: height / 2
                              color: Commons.Color.accent
                              opacity: 0.85
                            }

                            MouseArea {
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.SizeVerCursor

                              property real startCanvasY: 0
                              property int endMinVal: 0

                              onPressed: function(mouse) {
                                weekTimelineFlick.interactive = false
                                root.isDraggingGhost = true
                                startCanvasY = mapToItem(weekCanvas, 0, mouse.y).y
                                endMinVal = root.draftEndMinutes
                              }

                              onPositionChanged: function(mouse) {
                                if (!pressed) return
                                var currY = mapToItem(weekCanvas, 0, mouse.y).y
                                var deltaMin = Math.round((currY - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                var cand = Math.max(root.draftStartMinutes + 15, Math.min(1440, endMinVal + deltaMin))
                                root.draftEndMinutes = cand
                              }

                              onReleased: function() {
                                weekTimelineFlick.interactive = true
                                root.isDraggingGhost = false
                              }
                            }
                          }

                          // Floating live badge for week view draft
                          Rectangle {
                            z: 50
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -Style.space(22)
                            width: weekDraftBadgeText.implicitWidth + Style.space(8)
                            height: Style.space(18)
                            radius: Style.cornerRadius / 2
                            color: Qt.rgba(0, 0, 0, 0.88)
                            border.width: 1
                            border.color: Commons.Color.accent

                            Text {
                              id: weekDraftBadgeText
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: Model.formatMinutes(root.draftStartMinutes) + " – " + Model.formatMinutes(root.draftEndMinutes)
                              color: Commons.Color.accent
                              font.family: root.contentFontFamily
                              font.pixelSize: Math.max(8, Style.font.caption - 1)
                              font.bold: true
                            }
                          }
                        }

                        // Red / Accent "Now" line across today column (Google Calendar signature)
                        Item {
                          visible: modelData.today === true
                          z: 20
                          anchors.left: parent.left
                          anchors.right: parent.right
                          y: Math.round((root.nowMinutes / 60.0) * weekViewCol.weekHourHeight) - 1

                          Rectangle {
                            id: weekNowDot
                            width: Style.space(7)
                            height: Style.space(7)
                            radius: width / 2
                            color: Commons.Color.accent
                            anchors.left: parent.left
                            anchors.leftMargin: -width / 2
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Rectangle {
                            anchors.left: weekNowDot.right
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 2
                            color: Commons.Color.accent
                          }
                        }

                        // Proportional Timed Events Layer
                        Item {
                          anchors.fill: parent
                          anchors.margins: 1
                          z: 10

                          Repeater {
                            model: modelData.timedEvents

                            Item {
                              id: weekEventCard
                              required property var modelData

                              readonly property int totalCols: Math.max(1, modelData.totalCols || 1)
                              readonly property int colIndex: modelData.colIndex || 0
                              readonly property real evColWidth: (parent.width - 2) / totalCols

                              property real dragCanvasOffsetX: 0

                              x: (colIndex * evColWidth + 1) + (isDraggingCard ? dragCanvasOffsetX : 0)
                              width: Math.max(12, evColWidth - 2)

                              property int liveStartMinutes: modelData.effectiveStartMinutes
                              property int liveEndMinutes: modelData.effectiveEndMinutes
                              property bool isDraggingBottom: false
                              property bool isDraggingTop: false
                              property bool isDraggingCard: false
                              property real dragStartY: 0
                              property int initialStartMinutes: 0
                              property int initialEndMinutes: 0
                              property string targetDateKey: modelData.startDate

                              z: (isDraggingBottom || isDraggingTop || isDraggingCard) ? 40 : 10
                              y: Math.round((liveStartMinutes / 60.0) * weekViewCol.weekHourHeight)
                              height: Math.max(Style.space(18), Math.round(((liveEndMinutes - liveStartMinutes) / 60.0) * weekViewCol.weekHourHeight) - 2)

                              readonly property color cardColor: modelData.color || Commons.Color.accent

                              // Card surface
                              Rectangle {
                                anchors.fill: parent
                                radius: Math.max(2, Style.cornerRadius / 2)
                                color: (isDraggingBottom || isDraggingTop || isDraggingCard || weekCardMouse.containsMouse)
                                  ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.32)
                                  : Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.18)
                                border.width: (isDraggingBottom || isDraggingTop || isDraggingCard || weekCardMouse.containsMouse) ? 1.5 : 1
                                border.color: (isDraggingBottom || isDraggingTop || isDraggingCard) ? Commons.Color.accent : cardColor

                                // Solid left strip
                                Rectangle {
                                  width: Style.space(3)
                                  anchors.left: parent.left
                                  anchors.top: parent.top
                                  anchors.bottom: parent.bottom
                                  radius: parent.radius
                                  color: weekEventCard.cardColor
                                }

                                Column {
                                  anchors.left: parent.left
                                  anchors.leftMargin: Style.space(5)
                                  anchors.right: parent.right
                                  anchors.rightMargin: Style.space(2)
                                  anchors.top: parent.top
                                  anchors.topMargin: Style.space(2)
                                  anchors.bottom: parent.bottom
                                  anchors.bottomMargin: Style.space(2)
                                  spacing: 0
                                  clip: true

                                  Text {
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.title
                                    color: root.contentForeground
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Math.max(9, Style.font.caption - 1)
                                    font.bold: true
                                  }

                                  Text {
                                    visible: weekEventCard.height >= Style.space(28)
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: Model.formatMinutes(weekEventCard.liveStartMinutes) + " – " + Model.formatMinutes(weekEventCard.liveEndMinutes)
                                    color: Qt.darker(root.contentForeground, 1.35)
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Math.max(8, Style.font.caption - 2)
                                  }

                                  Text {
                                    visible: Boolean(modelData.meetLink) && weekEventCard.height >= Style.space(42)
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: "󰕧 Meet"
                                    color: Commons.Color.accent
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Math.max(8, Style.font.caption - 2)
                                  }

                                  Text {
                                    visible: Boolean(modelData.location) && weekEventCard.height >= Style.space(54)
                                    textFormat: Text.PlainText
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: "📍 " + modelData.location
                                    color: Qt.darker(root.contentForeground, 1.5)
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Math.max(8, Style.font.caption - 2)
                                  }
                                }

                                MouseArea {
                                  id: weekCardMouse
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  anchors.top: parent.top
                                  anchors.bottom: parent.bottom
                                  anchors.bottomMargin: Style.space(8)
                                  hoverEnabled: true
                                  cursorShape: weekEventCard.isDraggingCard ? Qt.ClosedHandCursor : (modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.OpenHandCursor)

                                  property real startCanvasX: 0
                                  property real startCanvasY: 0
                                  property real pressStartY: 0
                                  property bool dragStarted: false

                                  onPressed: function(mouse) {
                                    pressStartY = mouse.y
                                    var pt = mapToItem(weekCanvas, mouse.x, mouse.y)
                                    startCanvasX = pt.x
                                    startCanvasY = pt.y
                                    weekEventCard.dragCanvasOffsetX = 0
                                    weekEventCard.initialStartMinutes = weekEventCard.liveStartMinutes
                                    weekEventCard.initialEndMinutes = weekEventCard.liveEndMinutes
                                    weekEventCard.targetDateKey = modelData.startDate
                                    dragStarted = false
                                  }

                                  onPositionChanged: function(mouse) {
                                    if (!pressed) return
                                    var diffY = mouse.y - pressStartY
                                    if (!dragStarted && (Math.abs(diffY) > 5 || Math.abs(mouse.x) > 5)) {
                                      dragStarted = true
                                      weekEventCard.isDraggingCard = true
                                      weekTimelineFlick.interactive = false
                                    }
                                    if (weekEventCard.isDraggingCard) {
                                      var currPos = mapToItem(weekCanvas, mouse.x, mouse.y)
                                      weekEventCard.dragCanvasOffsetX = currPos.x - startCanvasX
                                      var deltaMin = Math.round((currPos.y - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                      var duration = weekEventCard.initialEndMinutes - weekEventCard.initialStartMinutes
                                      var candStart = Math.max(0, Math.min(1440 - duration, weekEventCard.initialStartMinutes + deltaMin))
                                      weekEventCard.liveStartMinutes = candStart
                                      weekEventCard.liveEndMinutes = candStart + duration

                                      var colX = currPos.x - weekViewCol.weekHourColWidth
                                      if (colX >= 0) {
                                        var colIdx = Math.floor(colX / weekViewCol.weekColWidth)
                                        if (colIdx >= 0 && colIdx < root.weekData.days.length) {
                                          var tDay = root.weekData.days[colIdx]
                                          if (tDay) weekEventCard.targetDateKey = tDay.key
                                        }
                                      }
                                    }
                                  }

                                  onReleased: function() {
                                    weekTimelineFlick.interactive = true
                                    if (weekEventCard.isDraggingCard) {
                                      weekEventCard.isDraggingCard = false
                                      weekEventCard.dragCanvasOffsetX = 0
                                      if (weekEventCard.liveStartMinutes !== modelData.effectiveStartMinutes ||
                                          weekEventCard.liveEndMinutes !== modelData.effectiveEndMinutes ||
                                          weekEventCard.targetDateKey !== modelData.startDate) {
                                        root.updateEventTime(modelData.id, weekEventCard.targetDateKey, Model.formatMinutes(weekEventCard.liveStartMinutes), Model.formatMinutes(weekEventCard.liveEndMinutes))
                                      }
                                    }
                                    dragStarted = false
                                  }

                                  onDoubleClicked: function(mouse) {
                                    if (!weekEventCard.isDraggingCard) {
                                      var pk = Model.parseDateKey(modelData.startDate)
                                      if (pk) root.selectDate(pk.year, pk.month, pk.day)
                                      root.setViewMode("day")
                                    }
                                  }

                                  PanelToolTip {
                                    visible: weekCardMouse.containsMouse && !weekEventCard.isDraggingBottom && !weekEventCard.isDraggingTop && !weekEventCard.isDraggingCard
                                    text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                                    fontFamily: root.contentFontFamily
                                  }
                                }

                                // Top resize handle
                                Item {
                                  anchors.top: parent.top
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  height: Style.space(8)
                                  z: 25

                                  MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.SizeVerCursor
                                    property real startCanvasY: 0
                                    onPressed: function(mouse) {
                                      weekTimelineFlick.interactive = false
                                      weekEventCard.isDraggingTop = true
                                      startCanvasY = mapToItem(weekCanvas, 0, mouse.y).y
                                      weekEventCard.initialStartMinutes = weekEventCard.liveStartMinutes
                                    }
                                    onPositionChanged: function(mouse) {
                                      if (!weekEventCard.isDraggingTop) return
                                      var currY = mapToItem(weekCanvas, 0, mouse.y).y
                                      var deltaMin = Math.round((currY - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                      var candidate = Math.max(0, Math.min(weekEventCard.liveEndMinutes - 15, weekEventCard.initialStartMinutes + deltaMin))
                                      weekEventCard.liveStartMinutes = candidate
                                    }
                                    onReleased: function() {
                                      weekTimelineFlick.interactive = true
                                      if (weekEventCard.isDraggingTop) {
                                        weekEventCard.isDraggingTop = false
                                        if (weekEventCard.liveStartMinutes !== modelData.effectiveStartMinutes) {
                                          root.updateEventTime(modelData.id, modelData.startDate, Model.formatMinutes(weekEventCard.liveStartMinutes), Model.formatMinutes(weekEventCard.liveEndMinutes))
                                        }
                                      }
                                    }
                                  }
                                }

                                // Bottom resize handle
                                Item {
                                  anchors.bottom: parent.bottom
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  height: Style.space(8)
                                  z: 25

                                  MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.SizeVerCursor
                                    property real startCanvasY: 0
                                    onPressed: function(mouse) {
                                      weekTimelineFlick.interactive = false
                                      weekEventCard.isDraggingBottom = true
                                      startCanvasY = mapToItem(weekCanvas, 0, mouse.y).y
                                      weekEventCard.initialEndMinutes = weekEventCard.liveEndMinutes
                                    }
                                    onPositionChanged: function(mouse) {
                                      if (!weekEventCard.isDraggingBottom) return
                                      var currY = mapToItem(weekCanvas, 0, mouse.y).y
                                      var deltaMin = Math.round((currY - startCanvasY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                      var candidate = Math.max(weekEventCard.liveStartMinutes + 15, Math.min(1440, weekEventCard.initialEndMinutes + deltaMin))
                                      weekEventCard.liveEndMinutes = candidate
                                    }
                                    onReleased: function() {
                                      weekTimelineFlick.interactive = true
                                      if (weekEventCard.isDraggingBottom) {
                                        weekEventCard.isDraggingBottom = false
                                        if (weekEventCard.liveEndMinutes !== modelData.effectiveEndMinutes) {
                                          root.updateEventTime(modelData.id, modelData.startDate, Model.formatMinutes(weekEventCard.liveStartMinutes), Model.formatMinutes(weekEventCard.liveEndMinutes))
                                        }
                                      }
                                    }
                                  }
                                }

                                // Floating badge while dragging in Week View
                                Rectangle {
                                  visible: weekEventCard.isDraggingBottom || weekEventCard.isDraggingTop || weekEventCard.isDraggingCard
                                  z: 50
                                  anchors.horizontalCenter: parent.horizontalCenter
                                  anchors.top: weekEventCard.isDraggingTop ? parent.top : undefined
                                  anchors.bottom: !weekEventCard.isDraggingTop ? parent.bottom : undefined
                                  anchors.topMargin: weekEventCard.isDraggingTop ? -Style.space(22) : 0
                                  anchors.bottomMargin: !weekEventCard.isDraggingTop ? -Style.space(22) : 0
                                  width: weekLiveBadgeText.implicitWidth + Style.space(12)
                                  height: Style.space(20)
                                  radius: Style.cornerRadius / 2
                                  color: Qt.rgba(0, 0, 0, 0.85)
                                  border.width: 1
                                  border.color: Commons.Color.accent

                                  Text {
                                    id: weekLiveBadgeText
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: (weekEventCard.targetDateKey !== modelData.startDate ? (weekEventCard.targetDateKey + " ") : "") + Model.formatMinutes(weekEventCard.liveStartMinutes) + " – " + Model.formatMinutes(weekEventCard.liveEndMinutes)
                                    color: Commons.Color.accent
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // 4. Week stepper bar
              Item {
                width: parent.width
                height: weekLabel.implicitHeight + Style.space(10)

                Text {
                  id: weekLabel
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: root.weekRangeLabel.toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅂" : "󰅁"
                  tooltipText: tr.t("nav.previousWeek")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveWeek(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅁" : "󰅂"
                  tooltipText: tr.t("nav.nextWeek")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveWeek(1)
                }
              }
            }
          }

          // ==================================================================
          // VIEW 3: DAY VIEW ("day")
          // ==================================================================
          Item {
            visible: root.viewMode === "day"
            width: parent.width
            height: visible ? dayViewCol.height : 0

            Column {
              id: dayViewCol
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              spacing: Style.space(8)

              // Day navigation header
              Item {
                width: parent.width
                height: dayNavLabel.implicitHeight + Style.space(10)

                Text {
                  id: dayNavLabel
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: root.dayHeaderLabel.toUpperCase()
                  color: root.dayData.isToday ? Commons.Color.accent : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                  font.bold: true
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅂" : "󰅁"
                  tooltipText: tr.t("nav.previousDay")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveDay(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅁" : "󰅂"
                  tooltipText: tr.t("nav.nextDay")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveDay(1)
                }
              }

              // All-day events banner in Day View
              Column {
                visible: root.dayData.allDayEvents.length > 0
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.dayData.allDayEvents

                  Rectangle {
                    required property var modelData
                    readonly property bool hasDescription: Boolean(modelData.description && String(modelData.description).length > 0)
                    width: parent.width
                    height: hasDescription ? Style.space(42) : Style.space(28)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.07)

                    Rectangle {
                      width: Style.space(4)
                      height: parent.height
                      radius: Style.cornerRadius
                      color: modelData.color || Commons.Color.accent
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      text: tr.t("events.allDay").toUpperCase()
                      color: Qt.darker(root.contentForeground, 1.4)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Column {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(96)
                      anchors.right: dayAllDayActions.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.title + (modelData.location ? " · " + modelData.location : "")
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        visible: parent.parent.hasDescription
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.description || ""
                        color: Qt.darker(root.contentForeground, 1.45)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: dayAllDayCardMouse
                      anchors.left: parent.left
                      anchors.right: dayAllDayActions.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      hoverEnabled: true
                      cursorShape: modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: { if (modelData.actionUrl !== "") root.openExternalUrl(modelData.actionUrl) }

                      PanelToolTip {
                        visible: dayAllDayCardMouse.containsMouse
                        text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                        fontFamily: root.contentFontFamily
                      }
                    }

                    Row {
                      id: dayAllDayActions
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      PanelActionButton {
                        visible: modelData.actionUrl !== ""
                        iconText: "󰌹"
                        tooltipText: tr.t("events.openLink")
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: root.openExternalUrl(modelData.actionUrl)
                      }

                      PanelActionButton {
                        iconText: "󰆴"
                        tooltipText: tr.t("events.delete")
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: root.deleteEvent(modelData.id)
                      }
                    }
                  }
                }
              }

              // Scrollable continuous hourly timeline for Day View
              Flickable {
                id: dayTimelineFlick
                width: parent.width
                height: Style.space(280)
                contentWidth: width
                // Room above the first hour line so its label (drawn half above
                // the line) is never cut by the clip at the top.
                readonly property int topInset: Style.space(8)
                contentHeight: 24 * dayHourHeight + 2 * topInset
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                readonly property int dayHourHeight: Style.space(42)
                readonly property int dayHourColWidth: Style.space(48)

                function scrollToRelevantHour() {
                  var targetHour = Math.max(0, (root.dayData.firstEventHour || 8) - 1)
                  contentY = Math.max(0, Math.min(contentHeight - height, targetHour * dayHourHeight))
                }

                Component.onCompleted: scrollToRelevantHour()

                Connections {
                  target: root
                  function onViewModeChanged() {
                    if (root.viewMode === "day") dayTimelineFlick.scrollToRelevantHour()
                  }
                  function onSelectedKeyChanged() {
                    if (root.viewMode === "day") dayTimelineFlick.scrollToRelevantHour()
                  }
                }

                Item {
                  id: dayCanvas
                  y: dayTimelineFlick.topInset
                  width: dayTimelineFlick.width
                  height: 24 * dayTimelineFlick.dayHourHeight

                  readonly property bool isCurrentDraftDay: (root.addingEvent || root.isDraggingGhost) && root.draftDateKey === root.dayData.key

                  // 1. Hourly grid lines & hour labels
                  Repeater {
                    model: 24

                    Item {
                      required property int index
                      width: dayCanvas.width
                      height: dayTimelineFlick.dayHourHeight
                      y: index * dayTimelineFlick.dayHourHeight

                      // Horizontal grid divider
                      Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: dayTimelineFlick.dayHourColWidth
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Style.spacing.hairline
                        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                      }

                      // Subtle half-hour dashed line
                      Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: dayTimelineFlick.dayHourColWidth + Style.space(8)
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: Math.floor(dayTimelineFlick.dayHourHeight / 2)
                        height: Style.spacing.hairline
                        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                      }

                      // Hour label
                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: -Style.space(6)
                        width: dayTimelineFlick.dayHourColWidth - Style.space(8)
                        horizontalAlignment: Text.AlignRight
                        text: Model.pad2(index) + ":00"
                        color: (root.dayData.isToday && Math.floor(root.nowMinutes / 60) === index)
                          ? Commons.Color.accent
                          : Qt.darker(root.contentForeground, 1.6)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: root.dayData.isToday && Math.floor(root.nowMinutes / 60) === index
                      }
                    }
                  }

                  // 2. Background drag-to-create or click to add MouseArea
                  MouseArea {
                    id: dayBgMouse
                    anchors.left: parent.left
                    anchors.leftMargin: dayTimelineFlick.dayHourColWidth
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    property real pressStartY: 0
                    property int dragAnchorMinutes: 0
                    property bool isDraggingRange: false

                    onPressed: function(mouse) {
                      pressStartY = mouse.y
                      var rawMin = Math.floor((mouse.y / dayTimelineFlick.dayHourHeight) * 60)
                      dragAnchorMinutes = Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                      isDraggingRange = false
                    }

                    onPositionChanged: function(mouse) {
                      if (!pressed) return
                      var diffY = mouse.y - pressStartY
                      if (!isDraggingRange && Math.abs(diffY) > 5) {
                        isDraggingRange = true
                        root.isDraggingGhost = true
                        dayTimelineFlick.interactive = false
                        root.draftDateKey = root.selectedKey
                      }
                      if (isDraggingRange) {
                        var currentRawMin = Math.floor((mouse.y / dayTimelineFlick.dayHourHeight) * 60)
                        var snappedMin = Math.round(currentRawMin / 15) * 15
                        snappedMin = Math.max(0, Math.min(1440, snappedMin))

                        if (snappedMin >= dragAnchorMinutes) {
                          root.draftStartMinutes = dragAnchorMinutes
                          root.draftEndMinutes = Math.max(dragAnchorMinutes + 15, snappedMin)
                        } else {
                          root.draftStartMinutes = Math.min(dragAnchorMinutes - 15, snappedMin)
                          root.draftEndMinutes = dragAnchorMinutes
                        }
                      }
                    }

                    onReleased: function(mouse) {
                      dayTimelineFlick.interactive = true
                      root.isDraggingGhost = false
                      if (isDraggingRange) {
                        // User dragged range — open options modal now
                        root.startAddingEventWithRange(root.selectedKey, Model.formatMinutes(root.draftStartMinutes), Model.formatMinutes(root.draftEndMinutes))
                      } else {
                        // Single click creates 1-hour block at clicked time
                        var rawMin = (mouse && typeof mouse.y === "number") ? Math.floor((mouse.y / dayTimelineFlick.dayHourHeight) * 60) : dragAnchorMinutes
                        var startMin = dragAnchorMinutes >= 0 ? dragAnchorMinutes : Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                        var endMin = Math.min(1440, startMin + 60)
                        root.startAddingEventWithRange(root.selectedKey, Model.formatMinutes(startMin), Model.formatMinutes(endMin))
                      }
                      isDraggingRange = false
                    }

                    onDoubleClicked: function(mouse) {
                      dayTimelineFlick.interactive = true
                      root.isDraggingGhost = false
                      var rawMin = (mouse && typeof mouse.y === "number") ? Math.floor((mouse.y / dayTimelineFlick.dayHourHeight) * 60) : 9 * 60
                      var startMin = Math.max(0, Math.min(1380, Math.floor(rawMin / 15) * 15))
                      var endMin = Math.min(1440, startMin + 60)
                      root.startAddingEventWithRange(root.selectedKey, Model.formatMinutes(startMin), Model.formatMinutes(endMin))
                    }
                  }

                  // Live Drag-to-Create Draft Card in Day View
                  Rectangle {
                    id: dayDraftCard
                    visible: dayCanvas.isCurrentDraftDay
                    z: 35
                    anchors.left: parent.left
                    anchors.leftMargin: dayTimelineFlick.dayHourColWidth + Style.space(2)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(4)
                    y: Math.round((root.draftStartMinutes / 60.0) * dayTimelineFlick.dayHourHeight)
                    height: Math.max(Style.space(22), Math.round(((root.draftEndMinutes - root.draftStartMinutes) / 60.0) * dayTimelineFlick.dayHourHeight) - 2)
                    radius: Math.max(3, Style.cornerRadius / 2)
                    color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
                    border.width: 1.5
                    border.color: Commons.Color.accent

                    // Left Accent Strip
                    Rectangle {
                      width: Style.space(4)
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      radius: parent.radius
                      color: Commons.Color.accent
                    }

                    Column {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(3)
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(3)
                      spacing: Style.space(1)
                      clip: true

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.newEventTitleText !== "" ? root.newEventTitleText : tr.t("events.untitled")
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: Model.formatMinutes(root.draftStartMinutes) + " – " + Model.formatMinutes(root.draftEndMinutes)
                        color: Commons.Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Math.max(9, Style.font.caption - 1)
                        font.bold: true
                      }
                    }

                    // Card body drag to shift time
                    MouseArea {
                      anchors.fill: parent
                      anchors.topMargin: Style.space(10)
                      anchors.bottomMargin: Style.space(10)
                      hoverEnabled: true
                      cursorShape: Qt.SizeAllCursor

                      property real startCanvasY: 0
                      property int startMinVal: 0
                      property int endMinVal: 0

                      onPressed: function(mouse) {
                        dayTimelineFlick.interactive = false
                        root.isDraggingGhost = true
                        startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                        startMinVal = root.draftStartMinutes
                        endMinVal = root.draftEndMinutes
                      }

                      onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var currY = mapToItem(dayCanvas, 0, mouse.y).y
                        var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                        var duration = endMinVal - startMinVal
                        var candStart = Math.max(0, Math.min(1440 - duration, startMinVal + deltaMin))
                        root.draftStartMinutes = candStart
                        root.draftEndMinutes = candStart + duration
                      }

                      onReleased: function() {
                        dayTimelineFlick.interactive = true
                        root.isDraggingGhost = false
                      }
                    }

                    // Top resize handle with visible pill indicator
                    Item {
                      anchors.top: parent.top
                      anchors.left: parent.left
                      anchors.right: parent.right
                      height: Style.space(10)
                      z: 40

                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Style.space(2)
                        width: Style.space(24)
                        height: Style.space(3)
                        radius: height / 2
                        color: Commons.Color.accent
                        opacity: 0.85
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor

                        property real startCanvasY: 0
                        property int startMinVal: 0

                        onPressed: function(mouse) {
                          dayTimelineFlick.interactive = false
                          root.isDraggingGhost = true
                          startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                          startMinVal = root.draftStartMinutes
                        }

                        onPositionChanged: function(mouse) {
                          if (!pressed) return
                          var currY = mapToItem(dayCanvas, 0, mouse.y).y
                          var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                          var cand = Math.max(0, Math.min(root.draftEndMinutes - 15, startMinVal + deltaMin))
                          root.draftStartMinutes = cand
                        }

                        onReleased: function() {
                          dayTimelineFlick.interactive = true
                          root.isDraggingGhost = false
                        }
                      }
                    }

                    // Bottom resize handle with visible pill indicator
                    Item {
                      anchors.bottom: parent.bottom
                      anchors.left: parent.left
                      anchors.right: parent.right
                      height: Style.space(10)
                      z: 40

                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(2)
                        width: Style.space(24)
                        height: Style.space(3)
                        radius: height / 2
                        color: Commons.Color.accent
                        opacity: 0.85
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeVerCursor

                        property real startCanvasY: 0
                        property int endMinVal: 0

                        onPressed: function(mouse) {
                          dayTimelineFlick.interactive = false
                          root.isDraggingGhost = true
                          startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                          endMinVal = root.draftEndMinutes
                        }

                        onPositionChanged: function(mouse) {
                          if (!pressed) return
                          var currY = mapToItem(dayCanvas, 0, mouse.y).y
                          var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                          var cand = Math.max(root.draftStartMinutes + 15, Math.min(1440, endMinVal + deltaMin))
                          root.draftEndMinutes = cand
                        }

                        onReleased: function() {
                          dayTimelineFlick.interactive = true
                          root.isDraggingGhost = false
                        }
                      }
                    }

                    // Floating live badge attached to draft card
                    Rectangle {
                      z: 50
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: -Style.space(24)
                      width: dayDraftBadgeText.implicitWidth + Style.space(12)
                      height: Style.space(20)
                      radius: Style.cornerRadius / 2
                      color: Qt.rgba(0, 0, 0, 0.88)
                      border.width: 1
                      border.color: Commons.Color.accent

                      Text {
                        id: dayDraftBadgeText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: Model.formatMinutes(root.draftStartMinutes) + " – " + Model.formatMinutes(root.draftEndMinutes)
                        color: Commons.Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  // 3. Current Time Red / Accent Line (when isToday)
                  Item {
                    visible: root.dayData.isToday
                    z: 20
                    anchors.left: parent.left
                    anchors.leftMargin: dayTimelineFlick.dayHourColWidth - Style.space(5)
                    anchors.right: parent.right
                    y: Math.round((root.nowMinutes / 60.0) * dayTimelineFlick.dayHourHeight) - 1

                    Rectangle {
                      id: dayNowDot
                      width: Style.space(9)
                      height: Style.space(9)
                      radius: width / 2
                      color: Commons.Color.accent
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                      anchors.left: dayNowDot.right
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      height: 2
                      color: Commons.Color.accent
                    }
                  }

                  // 4. Proportional Timed Event Blocks
                  Item {
                    id: dayEventsLayer
                    anchors.left: parent.left
                    anchors.leftMargin: dayTimelineFlick.dayHourColWidth + Style.space(2)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(4)
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    z: 10

                    Repeater {
                      model: root.dayData.timedEvents

                      Item {
                        id: dayEventCard
                        required property var modelData

                        readonly property int totalCols: Math.max(1, modelData.totalCols || 1)
                        readonly property int colIndex: modelData.colIndex || 0
                        readonly property real colWidth: (dayEventsLayer.width - (totalCols - 1) * Style.space(4)) / totalCols

                        x: colIndex * (colWidth + Style.space(4))
                        width: Math.max(Style.space(40), colWidth)

                        property int liveStartMinutes: modelData.effectiveStartMinutes
                        property int liveEndMinutes: modelData.effectiveEndMinutes
                        property bool isDraggingBottom: false
                        property bool isDraggingTop: false
                        property bool isDraggingCard: false
                        property real dragStartY: 0
                        property int initialStartMinutes: 0
                        property int initialEndMinutes: 0

                        z: (isDraggingBottom || isDraggingTop || isDraggingCard) ? 40 : 10
                        y: Math.round((liveStartMinutes / 60.0) * dayTimelineFlick.dayHourHeight)
                        height: Math.max(Style.space(24), Math.round(((liveEndMinutes - liveStartMinutes) / 60.0) * dayTimelineFlick.dayHourHeight) - 2)

                        readonly property color cardColor: modelData.color || Commons.Color.accent

                        // Card Surface
                        Rectangle {
                          id: dayCardBg
                          anchors.fill: parent
                          radius: Math.max(3, Style.cornerRadius / 2)
                          color: (isDraggingBottom || isDraggingTop || isDraggingCard)
                            ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.32)
                            : (dayCardMouse.containsMouse
                              ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.24)
                              : Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.16))
                          border.width: (isDraggingBottom || isDraggingTop || isDraggingCard || dayCardMouse.containsMouse) ? 1.5 : 1
                          border.color: (isDraggingBottom || isDraggingTop || isDraggingCard) ? Commons.Color.accent : cardColor

                          // Solid left accent bar
                          Rectangle {
                            width: Style.space(4)
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: parent.radius
                            color: dayEventCard.cardColor
                          }

                          // Card Content
                          Column {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(8)
                            anchors.right: dayEventActions.left
                            anchors.rightMargin: Style.space(4)
                            anchors.top: parent.top
                            anchors.topMargin: compact ? Style.space(1) : Style.space(3)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: compact ? 0 : Style.space(4)
                            spacing: Style.space(1)
                            clip: true

                            // Short cards (under ~45 min) get one "09:00 · Title" line
                            // instead of a time row that pushes the title out of view.
                            readonly property bool compact: dayEventCard.height < Style.space(32)

                            Text {
                              visible: !parent.compact
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: Model.formatMinutes(dayEventCard.liveStartMinutes) + " – " + Model.formatMinutes(dayEventCard.liveEndMinutes)
                              color: Qt.darker(root.contentForeground, 1.3)
                              font.family: root.contentFontFamily
                              font.pixelSize: Math.max(9, Style.font.caption - 1)
                              font.bold: true
                            }

                            Text {
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: parent.compact
                                ? Model.formatMinutes(dayEventCard.liveStartMinutes) + " · " + modelData.title
                                : modelData.title
                              color: root.contentForeground
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.bodySmall
                              font.bold: true
                            }

                            Text {
                              visible: Boolean(modelData.meetLink) && dayEventCard.height >= Style.space(42)
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: "󰕧 Meet"
                              color: Commons.Color.accent
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }

                            Text {
                              visible: Boolean(modelData.location) && dayEventCard.height >= Style.space(52)
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: "📍 " + modelData.location
                              color: Qt.darker(root.contentForeground, 1.45)
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                            }

                            Text {
                              visible: Boolean(modelData.description) && dayEventCard.height >= Style.space(72)
                              textFormat: Text.PlainText
                              width: parent.width
                              elide: Text.ElideRight
                              text: modelData.description
                              color: Qt.darker(root.contentForeground, 1.5)
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          // Actions: Meet link & delete button
                          Row {
                            id: dayEventActions
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(4)
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(2)
                            spacing: Style.space(2)
                            z: 15

                            PanelActionButton {
                              visible: modelData.actionUrl !== "" && dayEventCard.height >= Style.space(26)
                              iconText: modelData.meetLink ? "󰕧" : "󰌹"
                              tooltipText: modelData.meetLink ? "Google Meet" : tr.t("events.openLink")
                              foreground: root.contentForeground
                              fontFamily: root.contentFontFamily
                              onClicked: root.openExternalUrl(modelData.actionUrl)
                            }

                            PanelActionButton {
                              visible: dayEventCard.height >= Style.space(26)
                              iconText: "󰆴"
                              tooltipText: tr.t("events.delete")
                              foreground: root.contentForeground
                              fontFamily: root.contentFontFamily
                              onClicked: root.deleteEvent(modelData.id)
                            }
                          }

                          // Card Drag/Click MouseArea (between top and bottom handles)
                          MouseArea {
                            id: dayCardMouse
                            anchors.left: parent.left
                            anchors.right: dayEventActions.left
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(8)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(10)
                            hoverEnabled: true
                            cursorShape: dayEventCard.isDraggingCard ? Qt.ClosedHandCursor : (modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.OpenHandCursor)

                            property real startCanvasY: 0
                            property real pressStartY: 0
                            property bool dragStarted: false

                            onPressed: function(mouse) {
                              pressStartY = mouse.y
                              startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                              dayEventCard.initialStartMinutes = dayEventCard.liveStartMinutes
                              dayEventCard.initialEndMinutes = dayEventCard.liveEndMinutes
                              dragStarted = false
                            }

                            onPositionChanged: function(mouse) {
                              if (!pressed) return
                              var diffY = mouse.y - pressStartY
                              if (!dragStarted && Math.abs(diffY) > 5) {
                                dragStarted = true
                                dayEventCard.isDraggingCard = true
                                dayTimelineFlick.interactive = false
                              }
                              if (dayEventCard.isDraggingCard) {
                                var currY = mapToItem(dayCanvas, 0, mouse.y).y
                                var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                                var duration = dayEventCard.initialEndMinutes - dayEventCard.initialStartMinutes
                                var candStart = Math.max(0, Math.min(1440 - duration, dayEventCard.initialStartMinutes + deltaMin))
                                dayEventCard.liveStartMinutes = candStart
                                dayEventCard.liveEndMinutes = candStart + duration
                              }
                            }

                            onReleased: function() {
                              dayTimelineFlick.interactive = true
                              if (dayEventCard.isDraggingCard) {
                                dayEventCard.isDraggingCard = false
                                if (dayEventCard.liveStartMinutes !== modelData.effectiveStartMinutes || dayEventCard.liveEndMinutes !== modelData.effectiveEndMinutes) {
                                  root.updateEventTime(modelData.id, root.dayData.key, Model.formatMinutes(dayEventCard.liveStartMinutes), Model.formatMinutes(dayEventCard.liveEndMinutes))
                                }
                              }
                              dragStarted = false
                            }

                            onDoubleClicked: function(mouse) {
                              if (!dayEventCard.isDraggingCard && modelData.actionUrl !== "") {
                                root.openExternalUrl(modelData.actionUrl)
                              }
                            }

                            PanelToolTip {
                              visible: dayCardMouse.containsMouse && !dayEventCard.isDraggingBottom && !dayEventCard.isDraggingTop && !dayEventCard.isDraggingCard
                              text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                              fontFamily: root.contentFontFamily
                            }
                          }

                          // Top Resize Handle
                          Item {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Style.space(8)
                            z: 25

                            MouseArea {
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.SizeVerCursor
                              property real startCanvasY: 0
                              onPressed: function(mouse) {
                                dayTimelineFlick.interactive = false
                                dayEventCard.isDraggingTop = true
                                startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                                dayEventCard.initialStartMinutes = dayEventCard.liveStartMinutes
                              }
                              onPositionChanged: function(mouse) {
                                if (!dayEventCard.isDraggingTop) return
                                var currY = mapToItem(dayCanvas, 0, mouse.y).y
                                var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                                var candidate = Math.max(0, Math.min(dayEventCard.liveEndMinutes - 15, dayEventCard.initialStartMinutes + deltaMin))
                                dayEventCard.liveStartMinutes = candidate
                              }
                              onReleased: function() {
                                dayTimelineFlick.interactive = true
                                if (dayEventCard.isDraggingTop) {
                                  dayEventCard.isDraggingTop = false
                                  if (dayEventCard.liveStartMinutes !== modelData.effectiveStartMinutes) {
                                    root.updateEventTime(modelData.id, root.dayData.key, Model.formatMinutes(dayEventCard.liveStartMinutes), Model.formatMinutes(dayEventCard.liveEndMinutes))
                                  }
                                }
                              }
                            }
                          }

                          // Bottom Resize Handle
                          Item {
                            id: dayBottomHandle
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Style.space(10)
                            z: 25

                            // Visual drag grip pill on hover or dragging
                            Rectangle {
                              anchors.horizontalCenter: parent.horizontalCenter
                              anchors.bottom: parent.bottom
                              anchors.bottomMargin: Style.space(2)
                              width: Style.space(22)
                              height: 2
                              radius: 1
                              color: (dayBottomMouse.containsMouse || dayEventCard.isDraggingBottom)
                                ? Commons.Color.accent
                                : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
                            }

                            MouseArea {
                              id: dayBottomMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.SizeVerCursor
                              property real startCanvasY: 0
                              onPressed: function(mouse) {
                                dayTimelineFlick.interactive = false
                                dayEventCard.isDraggingBottom = true
                                startCanvasY = mapToItem(dayCanvas, 0, mouse.y).y
                                dayEventCard.initialEndMinutes = dayEventCard.liveEndMinutes
                              }
                              onPositionChanged: function(mouse) {
                                if (!dayEventCard.isDraggingBottom) return
                                var currY = mapToItem(dayCanvas, 0, mouse.y).y
                                var deltaMin = Math.round((currY - startCanvasY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                                var candidate = Math.max(dayEventCard.liveStartMinutes + 15, Math.min(1440, dayEventCard.initialEndMinutes + deltaMin))
                                dayEventCard.liveEndMinutes = candidate
                              }
                              onReleased: function() {
                                dayTimelineFlick.interactive = true
                                if (dayEventCard.isDraggingBottom) {
                                  dayEventCard.isDraggingBottom = false
                                  if (dayEventCard.liveEndMinutes !== modelData.effectiveEndMinutes) {
                                    root.updateEventTime(modelData.id, root.dayData.key, Model.formatMinutes(dayEventCard.liveStartMinutes), Model.formatMinutes(dayEventCard.liveEndMinutes))
                                  }
                                }
                              }
                            }
                          }

                          // Floating live time badge when resizing or moving
                          Rectangle {
                            visible: dayEventCard.isDraggingBottom || dayEventCard.isDraggingTop || dayEventCard.isDraggingCard
                            z: 50
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: dayEventCard.isDraggingTop ? parent.top : undefined
                            anchors.bottom: !dayEventCard.isDraggingTop ? parent.bottom : undefined
                            anchors.topMargin: dayEventCard.isDraggingTop ? -Style.space(26) : 0
                            anchors.bottomMargin: !dayEventCard.isDraggingTop ? -Style.space(26) : 0
                            width: dayLiveBadgeText.implicitWidth + Style.space(12)
                            height: Style.space(22)
                            radius: Style.cornerRadius / 2
                            color: Qt.rgba(0, 0, 0, 0.85)
                            border.width: 1
                            border.color: Commons.Color.accent

                            Text {
                              id: dayLiveBadgeText
                              textFormat: Text.PlainText
                              anchors.centerIn: parent
                              text: Model.formatMinutes(dayEventCard.liveStartMinutes) + " – " + Model.formatMinutes(dayEventCard.liveEndMinutes)
                              color: Commons.Color.accent
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ==================================================================
          // VIEW 4: YEAR VIEW ("year")
          // ==================================================================
          Item {
            visible: root.viewMode === "year"
            width: parent.width
            height: visible ? yearViewCol.height : 0

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveYear(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: yearViewCol
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              spacing: Style.space(6)

              // Year stepper bar (top of year grid)
              Item {
                width: parent.width
                height: yearNavLabel.implicitHeight + Style.space(8)

                Text {
                  id: yearNavLabel
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(140)
                  horizontalAlignment: Text.AlignHCenter
                  text: Commons.I18n.formatNumber(root.viewYear)
                  color: Qt.darker(root.contentForeground, 1.3)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                  font.bold: true
                }

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅂" : "󰅁"
                  tooltipText: tr.t("nav.previousYear")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveYear(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅁" : "󰅂"
                  tooltipText: tr.t("nav.nextYear")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveYear(1)
                }
              }

              Grid {
                id: yearGrid
                width: parent.width
                columns: 3
                columnSpacing: Style.space(8)
                rowSpacing: Style.space(8)

                Repeater {
                  model: root.yearMonths

                  Rectangle {
                    required property var modelData
                    readonly property int cardWidth: Math.floor((root.fullGridWidth - 2 * Style.space(8)) / 3)
                    readonly property int miniCellW: Math.floor((cardWidth - Style.space(12)) / 7)
                    readonly property int miniCellH: Style.space(11)

                    width: cardWidth
                    height: miniMonthCol.implicitHeight + Style.space(6)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                    border.width: (modelData.month === root.today.getMonth() && modelData.year === root.today.getFullYear())
                      ? Style.spacing.hairline
                      : 0
                    border.color: Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                    Column {
                      id: miniMonthCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(4)
                      spacing: Style.space(1)

                      // Mini-month header (clicking jumps to that Month view)
                      Rectangle {
                        width: parent.width
                        height: Style.space(18)
                        radius: Style.cornerRadius
                        color: miniHeaderMouse.containsMouse
                          ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                          : "transparent"

                        Text {
                          textFormat: Text.PlainText
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(2)
                          anchors.verticalCenter: parent.verticalCenter
                          text: root.standaloneMonthLong(modelData.month)
                          color: miniHeaderMouse.containsMouse
                            ? Commons.Color.accent
                            : root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          font.letterSpacing: 0.5
                        }

                        Text {
                          visible: modelData.totalEvents > 0
                          textFormat: Text.PlainText
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(2)
                          anchors.verticalCenter: parent.verticalCenter
                          text: Commons.I18n.formatNumber(modelData.totalEvents) + " 󰃭"
                          color: Commons.Color.accent
                          font.family: root.contentFontFamily
                          font.pixelSize: Math.max(9, Style.font.caption - 2)
                          font.bold: true
                        }

                        MouseArea {
                          id: miniHeaderMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            root.selectDate(modelData.year, modelData.month, 1)
                            root.setViewMode("month")
                          }
                        }
                      }

                      // 6x7 mini day cells
                      Repeater {
                        model: modelData.weeks

                        Row {
                          required property var modelData
                          spacing: 0

                          Repeater {
                            model: modelData.days

                            Rectangle {
                              required property var modelData
                              width: miniCellW
                              height: miniCellH
                              radius: Math.max(2, Style.cornerRadius / 2)
                              color: !modelData.inMonth
                                ? "transparent"
                                : (modelData.today
                                  ? Commons.Color.accent
                                  : (modelData.selected
                                    ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                                    : (modelData.hasEvents
                                      ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18)
                                      : "transparent")))

                              Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: modelData.inMonth ? Commons.I18n.formatNumber(modelData.day) : ""
                                color: modelData.today
                                  ? Commons.Color.background
                                  : (modelData.hasEvents
                                    ? Commons.Color.accent
                                    : (modelData.inMonth
                                      ? root.contentForeground
                                      : "transparent"))
                                font.family: root.contentFontFamily
                                font.pixelSize: Math.max(9, Style.font.caption - 2)
                                font.bold: modelData.today || modelData.hasEvents || modelData.selected
                              }

                              MouseArea {
                                enabled: modelData.inMonth
                                anchors.fill: parent
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                  root.selectDate(modelData.year, modelData.month, modelData.day)
                                  root.setViewMode("day")
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ==================================================================
          // SELECTED DAY AGENDA DRAWER (shown under Month and Week views)
          // ==================================================================
          Item {
            visible: root.viewMode === "month"
            width: parent.width
            height: visible ? agendaBlock.height : 0

            Column {
              id: agendaBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              spacing: Style.space(6)

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.contentForeground
                opacity: 0.12
              }

              // Agenda section header for the selected day
              Item {
                width: parent.width
                height: Style.space(22)

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.dayHeaderLabel.toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: tr.tn("events.count", root.selectedDayEvents.length).arg(
                    Commons.I18n.formatNumber(root.selectedDayEvents.length)
                  )
                  color: root.selectedDayEvents.length > 0
                    ? Commons.Color.accent
                    : Qt.darker(root.contentForeground, 1.7)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.selectedDayEvents.length > 0
                }
              }

              // Empty state when selected day has no events
              Text {
                visible: root.selectedDayEvents.length === 0
                textFormat: Text.PlainText
                width: parent.width
                topPadding: Style.space(4)
                bottomPadding: Style.space(4)
                horizontalAlignment: Text.AlignHCenter
                text: tr.t("events.noEvents")
                color: Qt.darker(root.contentForeground, 1.8)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // List of events for the selected day
              Column {
                visible: root.selectedDayEvents.length > 0
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.selectedDayEvents.slice(0, 6)

                  Rectangle {
                    required property var modelData
                    readonly property bool hasDescription: Boolean(modelData.description && String(modelData.description).length > 0)
                    width: agendaBlock.width
                    height: hasDescription ? Style.space(44) : Style.space(32)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

                    Rectangle {
                      width: Style.space(4)
                      height: parent.height
                      radius: Style.cornerRadius
                      color: modelData.color || Commons.Color.accent
                    }

                    Text {
                      id: agendaTimeLabel
                      textFormat: Text.PlainText
                      width: Style.space(86)
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.allDay
                        ? tr.t("events.allDay")
                        : (modelData.startTime + (modelData.endTime ? "–" + modelData.endTime : ""))
                      color: Qt.darker(root.contentForeground, 1.35)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Column {
                      anchors.left: agendaTimeLabel.right
                      anchors.leftMargin: Style.space(6)
                      anchors.right: agendaRowActions.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.title + (modelData.location ? " · " + modelData.location : "")
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        visible: parent.parent.hasDescription
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.description || ""
                        color: Qt.darker(root.contentForeground, 1.45)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: agendaRowMouse
                      anchors.left: parent.left
                      anchors.right: agendaRowActions.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      hoverEnabled: true
                      cursorShape: modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: { if (modelData.actionUrl !== "") root.openExternalUrl(modelData.actionUrl) }
                      onDoubleClicked: root.setViewMode("day")

                      PanelToolTip {
                        visible: agendaRowMouse.containsMouse
                        text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                        fontFamily: root.contentFontFamily
                      }
                    }

                    Row {
                      id: agendaRowActions
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      PanelActionButton {
                        visible: modelData.actionUrl !== ""
                        iconText: "󰌹"
                        tooltipText: tr.t("events.openLink")
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: root.openExternalUrl(modelData.actionUrl)
                      }

                      PanelActionButton {
                        iconText: "󰆴"
                        tooltipText: tr.t("events.delete")
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: root.deleteEvent(modelData.id)
                      }
                    }
                  }
                }

                Button {
                  visible: root.selectedDayEvents.length > 6
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: tr.t("events.moreInDayView").arg(
                    Commons.I18n.formatNumber(root.selectedDayEvents.length - 6)
                  )
                  bordered: true
                  foreground: root.contentForeground
                  accent: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(10)
                  verticalPadding: Style.space(4)
                  onClicked: root.setViewMode("day")
                }
              }
            }
          }
        }

      // ==================================================================
      // FLOATING GOOGLE CALENDAR EVENT CREATION MODAL OVERLAY
      // ==================================================================
      Item {
        id: eventModalContainer
        anchors.fill: parent
        z: 120
        visible: root.addingEvent && !root.isDraggingGhost

        BorderSurface {
          id: eventModalCard
          property real cardX: {
            if (root.viewMode === "week") {
              var p = Model.parseDateKey(root.draftDateKey)
              var dayIdx = p ? (new Date(p.year, p.month, p.day, 12)).getDay() : 0
              if (dayIdx >= 3) return Style.space(12)
              return Math.max(Style.space(12), parent.width - width - Style.space(12))
            }
            return Math.max(Style.space(12), Math.floor((parent.width - width) / 2))
          }
          property real cardY: Math.max(Style.space(24), Math.min(Style.space(72), Math.floor((parent.height - implicitHeight) / 2)))
          x: cardX
          y: cardY
          width: Math.min(Style.space(350), parent.width - Style.space(24))
          implicitHeight: eventModalCol.implicitHeight + Style.space(22)
          radius: Style.cornerRadius * 1.5
          color: Qt.rgba(0.12, 0.13, 0.15, 0.97)
          borderSpec: Border.controlSpec("active", root.contentForeground, Commons.Color.accent)

          Column {
            id: eventModalCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(8)

            // 1. Header with drag grip icon and close button
            Row {
              width: parent.width

              Item {
                width: parent.width - Style.space(28)
                height: Style.space(24)

                MouseArea {
                  id: modalHeaderDrag
                  anchors.fill: parent
                  cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  property real startMouseX: 0
                  property real startMouseY: 0
                  property real startCardX: 0
                  property real startCardY: 0

                  onPressed: function(mouse) {
                    startMouseX = mouse.x
                    startMouseY = mouse.y
                    startCardX = eventModalCard.x
                    startCardY = eventModalCard.y
                  }

                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var newX = startCardX + (mouse.x - startMouseX)
                    var newY = startCardY + (mouse.y - startMouseY)
                    eventModalCard.cardX = Math.max(Style.space(4), Math.min(eventModalContainer.width - eventModalCard.width - Style.space(4), newX))
                    eventModalCard.cardY = Math.max(Style.space(4), Math.min(eventModalContainer.height - eventModalCard.height - Style.space(4), newY))
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  text: "󰍜"
                  color: Qt.darker(root.contentForeground, 1.8)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(24)
                height: Style.space(24)
                iconText: "󰅖"
                bordered: false
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.cancelAddingEvent()
              }
            }

            // 2. Event Title Input Field
            TextField {
              id: eventTitleInput
              width: parent.width
              placeholderText: tr.t("form.titlePlaceholder")
              text: root.newEventTitleText
              onTextChanged: { root.newEventTitleText = text }
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              verticalPadding: Style.space(4)
              horizontalPadding: Style.space(2)
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelAddingEvent(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitNewEvent(); event.accepted = true }
                else if (event.key === Qt.Key_Tab) { eventStartInput.forceActiveFocus(); event.accepted = true }
              }
            }

            Rectangle {
              width: parent.width
              height: 2
              color: eventTitleInput.activeFocus ? Commons.Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.2)
            }

            // 3. Type Selector Pill
            Row {
              spacing: Style.space(6)

              Rectangle {
                height: Style.space(24)
                width: eventPillText.implicitWidth + Style.space(18)
                radius: height / 2
                color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
                border.width: 1
                border.color: Commons.Color.accent

                Text {
                  id: eventPillText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: tr.t("events.event")
                  color: Commons.Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // 4. Date & Time Row (with clock icon)
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                text: "󰥔"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Column {
                width: parent.width - Style.space(32)
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: {
                    var p = Model.parseDateKey(root.draftDateKey || root.selectedKey)
                    var dObj = p ? new Date(p.year, p.month, p.day, 12) : root.selectedDateObj
                    var dStr = dObj.toLocaleDateString(root.labelLocale, tr.t("clock.dayMonthFormat"))
                    if (root.newEventAllDay) return dStr + " · " + tr.t("events.allDay")
                    return dStr + "  " + Model.formatMinutes(root.draftStartMinutes) + " – " + Model.formatMinutes(root.draftEndMinutes)
                  }
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Row {
                  spacing: Style.space(6)

                  TextField {
                    id: eventDateInput
                    width: Style.space(88)
                    text: root.draftDateKey || root.selectedKey
                    onEditingFinished: {
                      if (Model.parseDateKey(text)) root.draftDateKey = text
                    }
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) { root.cancelAddingEvent(); event.accepted = true }
                      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitNewEvent(); event.accepted = true }
                    }
                  }

                  TextField {
                    id: eventStartInput
                    width: Style.space(52)
                    visible: !root.newEventAllDay
                    text: Model.formatMinutes(root.draftStartMinutes)
                    onEditingFinished: {
                      var m = Model.parseMinutes(text)
                      if (m >= 0) {
                        root.draftStartMinutes = m
                        if (root.draftEndMinutes <= m) root.draftEndMinutes = Math.min(1440, m + 60)
                      }
                    }
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) { root.cancelAddingEvent(); event.accepted = true }
                      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitNewEvent(); event.accepted = true }
                    }
                  }

                  Text {
                    visible: !root.newEventAllDay
                    anchors.verticalCenter: parent.verticalCenter
                    text: "–"
                    color: Qt.darker(root.contentForeground, 1.5)
                  }

                  TextField {
                    id: eventEndInput
                    width: Style.space(52)
                    visible: !root.newEventAllDay
                    text: Model.formatMinutes(root.draftEndMinutes)
                    onEditingFinished: {
                      var m = Model.parseMinutes(text)
                      if (m > root.draftStartMinutes) root.draftEndMinutes = m
                    }
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) { root.cancelAddingEvent(); event.accepted = true }
                      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitNewEvent(); event.accepted = true }
                    }
                  }

                  Button {
                    text: tr.t("form.allDay")
                    selected: root.newEventAllDay
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(2)
                    onClicked: { root.newEventAllDay = !root.newEventAllDay }
                  }
                }
              }
            }

            // 5. Google Meet Video Conferencing Row
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "󰕧"
                color: root.newEventAddMeet ? Commons.Color.accent : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Button {
                visible: !root.newEventAddMeet
                text: tr.t("form.addMeet")
                bordered: true
                selected: false
                foreground: root.contentForeground
                accent: Commons.Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(12)
                verticalPadding: Style.space(5)
                onClicked: {
                  if (!root.draftMeetCode) root.draftMeetCode = Model.generateMeetCode()
                  root.newEventAddMeet = true
                }
              }

              Row {
                visible: root.newEventAddMeet
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Rectangle {
                  height: Style.space(28)
                  width: Math.min(eventModalCard.width - Style.space(130), meetLabelText.implicitWidth + Style.space(20))
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18)
                  border.width: 1
                  border.color: Commons.Color.accent

                  Text {
                    id: meetLabelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.draftMeetCode ? ("meet.google.com/" + root.draftMeetCode) : "Google Meet"
                    color: Commons.Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(28)
                  text: root.meetCopied ? tr.t("form.copied") : tr.t("form.copyLink")
                  iconText: root.meetCopied ? "󰄬" : "󰆏"
                  tooltipText: tr.t("form.copyLink")
                  bordered: true
                  selected: root.meetCopied
                  accent: Commons.Color.accent
                  foreground: root.meetCopied ? Commons.Color.accent : root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(2)
                  onClicked: {
                    var code = root.draftMeetCode || Model.generateMeetCode()
                    root.draftMeetCode = code
                    Quickshell.execDetached(["wl-copy", "--", "https://meet.google.com/" + code])
                    root.meetCopied = true
                    copyResetTimer.restart()
                  }
                }

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(24)
                  height: Style.space(24)
                  iconText: "󰅖"
                  tooltipText: tr.t("form.removeMeet")
                  bordered: false
                  foreground: root.contentForeground
                  onClicked: {
                    root.newEventAddMeet = false
                    root.draftMeetCode = ""
                    root.meetCopied = false
                  }
                }
              }
            }

            // 6. Location Row with Google Maps integration
            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍎"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              TextField {
                id: eventLocationInput
                width: parent.width - Style.space(64)
                placeholderText: tr.t("form.addLocation")
                text: root.newEventLocationText
                onTextChanged: {
                  root.newEventLocationText = text
                  if (text.trim().length === 0) {
                    root.selectedLocationLat = 0.0
                    root.selectedLocationLon = 0.0
                    root.locationSuggestions = []
                  } else if (text.trim().length >= 3) {
                    locationDebounceTimer.restart()
                  } else {
                    root.locationSuggestions = []
                  }
                }
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (root.locationSuggestions.length > 0) {
                      root.locationSuggestions = []
                      event.accepted = true
                    } else {
                      root.cancelAddingEvent()
                      event.accepted = true
                    }
                  }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.locationSuggestions.length > 0) {
                      root.applyLocationSuggestion(root.locationSuggestions[0])
                      event.accepted = true
                    } else {
                      root.commitNewEvent()
                      event.accepted = true
                    }
                  }
                  else if (event.key === Qt.Key_Tab) {
                    root.locationSuggestions = []
                    eventDescriptionInput.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(26)
                height: Style.space(26)
                horizontalPadding: 0
                verticalPadding: 0
                iconText: "󰊭"
                iconSize: Style.space(13)
                tooltipText: tr.t("form.viewOnMaps")
                bordered: true
                foreground: root.contentForeground
                accent: Commons.Color.accent
                onClicked: {
                  var q = root.newEventLocationText.trim()
                  var url = q ? ("https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(q)) : "https://maps.google.com"
                  root.openExternalUrl(url)
                }
              }
            }

            // 6b. Location Suggestions Dropdown
            Column {
              width: parent.width - Style.space(32)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(2)
              visible: root.locationSuggestions.length > 0

              Repeater {
                model: root.locationSuggestions
                delegate: Rectangle {
                  width: parent.width
                  height: Style.space(34)
                  radius: Style.space(4)
                  color: locItemArea.containsMouse ? Style.pressedFillFor(root.contentForeground, Commons.Color.accent) : Commons.Color.surface
                  border.color: locItemArea.containsMouse ? Commons.Color.accent : Commons.Color.dimmedForeground
                  border.width: 1

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: "󰍎"
                      font.pixelSize: Style.font.caption
                      color: Commons.Color.accent
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      width: parent.width - Style.space(24)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      Text {
                        text: modelData.title || ""
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        text: modelData.address || ""
                        color: Commons.Color.dimmedForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Math.max(9, Style.font.caption - 2)
                        elide: Text.ElideRight
                        width: parent.width
                        visible: (modelData.address || "").length > 0
                      }
                    }
                  }

                  MouseArea {
                    id: locItemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.applyLocationSuggestion(modelData)
                    }
                  }
                }
              }
            }

            // 6c. Embedded Google Maps Preview Card with CartoDB/OSM Tiles & Map Controls
            Rectangle {
              id: mapPreviewCard
              visible: (root.selectedLocationLat !== 0.0 || root.selectedLocationLon !== 0.0) && root.locationSuggestions.length === 0
              width: parent.width - Style.space(32)
              anchors.horizontalCenter: parent.horizontalCenter
              height: Style.space(120)
              radius: Style.cornerRadius
              clip: true
              color: "#18181b"
              border.width: 1
              border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.45)

              // Map Tiles Layer (3x3 grid centered on target lat/lon)
              Item {
                id: mapTilesLayer
                anchors.fill: parent

                readonly property var centerTile: Model.latLonToTile(root.selectedLocationLat, root.selectedLocationLon, root.mapZoom)

                Grid {
                  anchors.centerIn: parent
                  columns: 3
                  rows: 3
                  spacing: 0

                  Repeater {
                    model: [
                      { dx: -1, dy: -1 }, { dx: 0, dy: -1 }, { dx: 1, dy: -1 },
                      { dx: -1, dy:  0 }, { dx: 0, dy:  0 }, { dx: 1, dy:  0 },
                      { dx: -1, dy:  1 }, { dx: 0, dy:  1 }, { dx: 1, dy:  1 }
                    ]

                    Image {
                      width: 140
                      height: 140
                      fillMode: Image.Stretch
                      source: {
                        var ct = mapTilesLayer.centerTile
                        return Model.getTileUrl(ct.z, ct.x + modelData.dx, ct.y + modelData.dy)
                      }
                      asynchronous: true
                      cache: true
                    }
                  }
                }
              }

              // Subtle contrast overlay
              Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.15)
              }

              // Central Marker Pin
              Item {
                anchors.centerIn: parent
                width: Style.space(26)
                height: Style.space(26)

                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: width / 2
                  color: Qt.rgba(0, 0, 0, 0.7)
                  border.width: 1.5
                  border.color: Commons.Color.accent

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰍎"
                    font.pixelSize: Style.font.caption + 2
                    color: Commons.Color.accent
                  }
                }
              }

              // Top header overlay badge with location title
              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                height: Style.space(22)
                color: Qt.rgba(0, 0, 0, 0.75)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(5)

                  Text {
                    text: "󰊭"
                    font.pixelSize: Style.font.caption
                    color: Commons.Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: tr.t("form.mapsLabel")
                    font.family: root.contentFontFamily
                    font.pixelSize: Math.max(9, Style.font.caption - 1)
                    font.bold: true
                    color: Commons.Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "• " + root.newEventLocationText
                    font.family: root.contentFontFamily
                    font.pixelSize: Math.max(9, Style.font.caption - 2)
                    color: root.contentForeground
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(110)
                  }
                }
              }

              // Bottom control actions overlay (Zoom in/out, Open in Maps, Clear)
              Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(4)
                spacing: Style.space(4)

                Button {
                  width: Style.space(22)
                  height: Style.space(22)
                  text: "–"
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: 0
                  verticalPadding: 0
                  onClicked: {
                    if (root.mapZoom > 3) root.mapZoom--
                  }
                }

                Button {
                  width: Style.space(22)
                  height: Style.space(22)
                  text: "+"
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: 0
                  verticalPadding: 0
                  onClicked: {
                    if (root.mapZoom < 18) root.mapZoom++
                  }
                }

                Button {
                  height: Style.space(22)
                  iconText: "󰊭"
                  text: tr.t("form.viewOnMaps")
                  bordered: true
                  accent: Commons.Color.accent
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Math.max(9, Style.font.caption - 2)
                  horizontalPadding: Style.space(6)
                  verticalPadding: 0
                  onClicked: {
                    var q = root.newEventLocationText.trim()
                    var url = q ? ("https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(q)) : "https://maps.google.com"
                    root.openExternalUrl(url)
                  }
                }

                Button {
                  width: Style.space(22)
                  height: Style.space(22)
                  iconText: "󰅖"
                  tooltipText: tr.t("form.clearLocation")
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: 0
                  verticalPadding: 0
                  onClicked: {
                    root.newEventLocationText = ""
                    root.selectedLocationLat = 0.0
                    root.selectedLocationLon = 0.0
                    root.locationSuggestions = []
                  }
                }
              }
            }

            // 7. Description Row
            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "󰎞"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              TextField {
                id: eventDescriptionInput
                width: parent.width - Style.space(32)
                placeholderText: tr.t("form.addDescription")
                text: root.newEventDescriptionText
                onTextChanged: { root.newEventDescriptionText = text }
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.cancelAddingEvent(); event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitNewEvent(); event.accepted = true }
                }
              }
            }

            // 8. Action Footer (Cancel & Save)
            Row {
              anchors.right: parent.right
              spacing: Style.space(10)
              topPadding: Style.space(4)

              Button {
                text: tr.t("form.cancel")
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(12)
                verticalPadding: Style.space(6)
                onClicked: root.cancelAddingEvent()
              }

              Button {
                text: tr.t("form.save")
                selected: true
                bordered: true
                foreground: root.contentForeground
                accent: Commons.Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(18)
                verticalPadding: Style.space(6)
                onClicked: root.commitNewEvent()
              }
            }
          }
        }
      }
    }
  }
}
}
