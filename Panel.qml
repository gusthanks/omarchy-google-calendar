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
  moduleName: (hostWidget && hostWidget.moduleName) ? hostWidget.moduleName : "omarchy-google-calendar"
  ipcTarget: (hostWidget && hostWidget.moduleName) ? hostWidget.moduleName : "omarchy.clock"
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
  property bool newEventAllDay: false
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
  readonly property string monthYearLabel: Commons.I18n.t("clock.monthYear")
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
    var dText = selectedDateObj.toLocaleDateString(labelLocale, Commons.I18n.t("clock.dayMonthFormat"))
    var wName = labelLocale.dayName(dayData.weekday, Locale.LongFormat)
    var rel = ""
    if (dayData.dayDiff === 0) rel = " · " + tr.t("nav.today")
    else if (dayData.dayDiff === 1) rel = " · " + tr.t("nav.tomorrow")
    else if (dayData.dayDiff === -1) rel = " · " + tr.t("nav.yesterday")
    return wName + ", " + dText + rel
  }

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)
  readonly property int fullGridWidth: weekColumnWidth + cellSpacing + gutterWidth + cellSpacing + 7 * cellWidth + 6 * cellSpacing

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
    root.showingSyncSettings = false
    root.addingEvent = true
    root.newEventAllDay = false
    Qt.callLater(function() {
      var content = panel.loadedContent
      if (!content) return
      content.eventTitleField.text = ""
      content.eventDateField.text = root.selectedKey
      if (typeof presetHour === "number" && presetHour >= 0 && presetHour <= 23) {
        content.eventStartField.text = Model.pad2(presetHour) + ":00"
        content.eventEndField.text = Model.pad2(Math.min(23, presetHour + 1)) + ":00"
      } else {
        content.eventStartField.text = "09:00"
        content.eventEndField.text = "10:00"
      }
      content.eventLocationField.text = ""
      content.eventDescriptionField.text = ""
      content.eventTitleField.forceActiveFocus()
    })
  }

  function cancelAddingEvent() {
    root.addingEvent = false
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
    var content = panel.loadedContent
    if (!content) return
    var validated = Model.validateQuickEvent({
      title: content.eventTitleField.text,
      dateKey: content.eventDateField.text || root.selectedKey,
      startTime: content.eventStartField.text,
      endTime: content.eventEndField.text,
      allDay: root.newEventAllDay,
      location: content.eventLocationField.text,
      description: content.eventDescriptionField.text
    })
    if (!validated.valid) {
      content.eventTitleField.forceActiveFocus()
      return
    }
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
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias bornField: bornField
      property alias expectancyField: expectancyField
      property alias eventTitleField: eventTitleField
      property alias eventDateField: eventDateField
      property alias eventStartField: eventStartField
      property alias eventEndField: eventEndField
      property alias eventLocationField: eventLocationField
      property alias eventDescriptionField: eventDescriptionField
      property alias icsUrlField: icsUrlField
      property alias searchField: searchField

      implicitHeight: calendarColumn.implicitHeight
      anchors.fill: parent
      blocked: bornField.activeFocus
        || expectancyField.activeFocus
        || eventTitleField.activeFocus
        || eventDateField.activeFocus
        || eventStartField.activeFocus
        || eventEndField.activeFocus
        || eventLocationField.activeFocus
        || eventDescriptionField.activeFocus
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
        interactive: contentHeight > height || contentWidth > width

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
                text: root.today.toLocaleDateString(root.labelLocale, Commons.I18n.t("clock.dayMonthFormat"))
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
                text: Commons.I18n.t("clock.backToToday")
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
                  text: Commons.I18n.t("clock.born")
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
                  placeholderText: Commons.I18n.t("clock.year")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly
                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: Commons.I18n.t("clock.liveTo")
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
                text: Commons.I18n.t("clock.life")
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
                  text: "Memento Mori"
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
                        text: Model.neutralizeMarkup(modelData.title || "(Sem título)", 50)
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

          // ---- Quick-Add Event Drawer (when + Evento is active)
          Item {
            visible: root.addingEvent
            width: parent.width
            height: visible ? addEventCard.height + Style.space(4) : 0

            BorderSurface {
              id: addEventCard
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.fullGridWidth
              height: addEventCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
              borderSpec: Border.controlSpec("normal", root.contentForeground, Commons.Color.accent)

              Column {
                id: addEventCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: tr.t("form.newEvent")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  font.bold: true
                }

                TextField {
                  id: eventTitleField
                  width: parent.width
                  placeholderText: tr.t("form.titlePlaceholder")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalPadding: Style.space(4)
                  Keys.onPressed: function(event) {
                    root.handleEventFormKey(event, eventDescriptionField, eventDateField)
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: eventDateField
                    width: Style.space(106)
                    placeholderText: tr.t("form.datePlaceholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      root.handleEventFormKey(
                        event,
                        eventTitleField,
                        root.newEventAllDay ? eventLocationField : eventStartField
                      )
                    }
                  }

                  Button {
                    text: tr.t("form.allDay")
                    selected: root.newEventAllDay
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                      root.newEventAllDay = !root.newEventAllDay
                      if (root.newEventAllDay) eventLocationField.forceActiveFocus()
                      else eventStartField.forceActiveFocus()
                    }
                  }

                  TextField {
                    id: eventStartField
                    visible: !root.newEventAllDay
                    width: Style.space(68)
                    placeholderText: tr.t("form.startPlaceholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      root.handleEventFormKey(event, eventDateField, eventEndField)
                    }
                  }

                  Text {
                    visible: !root.newEventAllDay
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "–"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  TextField {
                    id: eventEndField
                    visible: !root.newEventAllDay
                    width: Style.space(68)
                    placeholderText: tr.t("form.endPlaceholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      root.handleEventFormKey(event, eventStartField, eventLocationField)
                    }
                  }
                }

                TextField {
                  id: eventLocationField
                  width: parent.width
                  placeholderText: tr.t("form.locationPlaceholder")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalPadding: Style.space(4)
                  Keys.onPressed: function(event) {
                    root.handleEventFormKey(
                      event,
                      root.newEventAllDay ? eventDateField : eventEndField,
                      eventDescriptionField
                    )
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: eventDescriptionField
                    width: parent.width - saveEvBtn.width - cancelEvBtn.width - Style.space(12)
                    placeholderText: tr.t("form.descriptionPlaceholder")
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalPadding: Style.space(4)
                    Keys.onPressed: function(event) {
                      root.handleEventFormKey(event, eventLocationField, eventTitleField)
                    }
                  }

                  Button {
                    id: saveEvBtn
                    text: tr.t("form.save")
                    bordered: true
                    selected: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(5)
                    onClicked: root.commitNewEvent()
                  }

                  Button {
                    id: cancelEvBtn
                    text: tr.t("form.cancel")
                    bordered: true
                    foreground: root.contentForeground
                    accent: Commons.Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(5)
                    onClicked: root.cancelAddingEvent()
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
                        text: Commons.I18n.t("clock.weekShort")
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
                        text: Commons.I18n.t("clock.startWeeksOn").arg(root.nextWeekStartLabel)
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
                  tooltipText: Commons.I18n.t("clock.previousMonth")
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Commons.I18n.rightToLeft ? "󰅁" : "󰅂"
                  tooltipText: Commons.I18n.t("clock.nextMonth")
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
              readonly property int weekHourHeight: Style.space(40)

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
                height: Style.space(340)
                contentWidth: width
                contentHeight: 24 * weekViewCol.weekHourHeight
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

                        // Vertical divider line to right of day column
                        Rectangle {
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: Style.spacing.hairline
                          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                        }

                        // Background click-to-add MouseArea
                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: function(mouse) {
                            var clickedHour = Math.floor(mouse.y / weekViewCol.weekHourHeight)
                            root.selectDate(modelData.year, modelData.month, modelData.day)
                            root.startAddingEvent(clickedHour)
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

                              x: colIndex * evColWidth + 1
                              width: Math.max(12, evColWidth - 2)

                              property int liveStartMinutes: modelData.effectiveStartMinutes
                              property int liveEndMinutes: modelData.effectiveEndMinutes
                              property bool isDraggingBottom: false
                              property real dragStartY: 0
                              property int initialEndMinutes: 0

                              y: Math.round((liveStartMinutes / 60.0) * weekViewCol.weekHourHeight)
                              height: Math.max(Style.space(18), Math.round(((liveEndMinutes - liveStartMinutes) / 60.0) * weekViewCol.weekHourHeight) - 2)

                              readonly property color cardColor: modelData.color || Commons.Color.accent

                              // Card surface
                              Rectangle {
                                anchors.fill: parent
                                radius: Math.max(2, Style.cornerRadius / 2)
                                color: (isDraggingBottom || weekCardMouse.containsMouse)
                                  ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.32)
                                  : Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.18)
                                border.width: (isDraggingBottom || weekCardMouse.containsMouse) ? 1.5 : 1
                                border.color: isDraggingBottom ? Commons.Color.accent : cardColor

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
                                  cursorShape: modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                  onClicked: {
                                    if (modelData.actionUrl !== "") root.openExternalUrl(modelData.actionUrl)
                                  }

                                  PanelToolTip {
                                    visible: weekCardMouse.containsMouse && !weekEventCard.isDraggingBottom
                                    text: Model.formatEventTooltip(modelData, tr.t("events.allDay"))
                                    fontFamily: root.contentFontFamily
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
                                    onPressed: function(mouse) {
                                      weekEventCard.isDraggingBottom = true
                                      weekEventCard.dragStartY = mouse.y
                                      weekEventCard.initialEndMinutes = weekEventCard.liveEndMinutes
                                    }
                                    onPositionChanged: function(mouse) {
                                      if (!weekEventCard.isDraggingBottom) return
                                      var deltaMin = Math.round((mouse.y - weekEventCard.dragStartY) / (weekViewCol.weekHourHeight / 60.0) / 15.0) * 15
                                      var candidate = Math.max(weekEventCard.liveStartMinutes + 15, Math.min(1440, weekEventCard.initialEndMinutes + deltaMin))
                                      weekEventCard.liveEndMinutes = candidate
                                    }
                                    onReleased: function() {
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
                                  visible: weekEventCard.isDraggingBottom
                                  z: 50
                                  anchors.horizontalCenter: parent.horizontalCenter
                                  anchors.bottom: parent.bottom
                                  anchors.bottomMargin: -Style.space(22)
                                  width: weekLiveBadgeText.implicitWidth + Style.space(10)
                                  height: Style.space(20)
                                  radius: Style.cornerRadius / 2
                                  color: Qt.rgba(0, 0, 0, 0.85)
                                  border.width: 1
                                  border.color: Commons.Color.accent

                                  Text {
                                    id: weekLiveBadgeText
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: Model.formatMinutes(weekEventCard.liveStartMinutes) + " – " + Model.formatMinutes(weekEventCard.liveEndMinutes)
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
                height: Style.space(340)
                contentWidth: width
                contentHeight: 24 * dayHourHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                readonly property int dayHourHeight: Style.space(46)
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
                  width: dayTimelineFlick.width
                  height: 24 * dayTimelineFlick.dayHourHeight

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

                  // 2. Background click-to-add MouseArea
                  MouseArea {
                    anchors.left: parent.left
                    anchors.leftMargin: dayTimelineFlick.dayHourColWidth
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      var clickedHour = Math.floor(mouse.y / dayTimelineFlick.dayHourHeight)
                      root.startAddingEvent(clickedHour)
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
                        property real dragStartY: 0
                        property int initialStartMinutes: 0
                        property int initialEndMinutes: 0

                        y: Math.round((liveStartMinutes / 60.0) * dayTimelineFlick.dayHourHeight)
                        height: Math.max(Style.space(24), Math.round(((liveEndMinutes - liveStartMinutes) / 60.0) * dayTimelineFlick.dayHourHeight) - 2)

                        readonly property color cardColor: modelData.color || Commons.Color.accent

                        // Card Surface
                        Rectangle {
                          id: dayCardBg
                          anchors.fill: parent
                          radius: Math.max(3, Style.cornerRadius / 2)
                          color: (isDraggingBottom || isDraggingTop)
                            ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.32)
                            : (dayCardMouse.containsMouse
                              ? Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.24)
                              : Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.16))
                          border.width: (isDraggingBottom || isDraggingTop || dayCardMouse.containsMouse) ? 1.5 : 1
                          border.color: (isDraggingBottom || isDraggingTop) ? Commons.Color.accent : cardColor

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
                            anchors.topMargin: Style.space(3)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(4)
                            spacing: Style.space(1)
                            clip: true

                            Text {
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
                              text: modelData.title
                              color: root.contentForeground
                              font.family: root.contentFontFamily
                              font.pixelSize: Style.font.bodySmall
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
                              iconText: "󰌹"
                              tooltipText: tr.t("events.openLink")
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

                          // Card Click MouseArea (between top and bottom handles)
                          MouseArea {
                            id: dayCardMouse
                            anchors.left: parent.left
                            anchors.right: dayEventActions.left
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(8)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Style.space(10)
                            hoverEnabled: true
                            cursorShape: modelData.actionUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                              if (modelData.actionUrl !== "") root.openExternalUrl(modelData.actionUrl)
                            }

                            PanelToolTip {
                              visible: dayCardMouse.containsMouse && !dayEventCard.isDraggingBottom && !dayEventCard.isDraggingTop
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
                              onPressed: function(mouse) {
                                dayEventCard.isDraggingTop = true
                                dayEventCard.dragStartY = mouse.y
                                dayEventCard.initialStartMinutes = dayEventCard.liveStartMinutes
                              }
                              onPositionChanged: function(mouse) {
                                if (!dayEventCard.isDraggingTop) return
                                var deltaMin = Math.round((mouse.y - dayEventCard.dragStartY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                                var candidate = Math.max(0, Math.min(dayEventCard.liveEndMinutes - 15, dayEventCard.initialStartMinutes + deltaMin))
                                dayEventCard.liveStartMinutes = candidate
                              }
                              onReleased: function() {
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
                              onPressed: function(mouse) {
                                dayEventCard.isDraggingBottom = true
                                dayEventCard.dragStartY = mouse.y
                                dayEventCard.initialEndMinutes = dayEventCard.liveEndMinutes
                              }
                              onPositionChanged: function(mouse) {
                                if (!dayEventCard.isDraggingBottom) return
                                var deltaMin = Math.round((mouse.y - dayEventCard.dragStartY) / (dayTimelineFlick.dayHourHeight / 60.0) / 15.0) * 15
                                var candidate = Math.max(dayEventCard.liveStartMinutes + 15, Math.min(1440, dayEventCard.initialEndMinutes + deltaMin))
                                dayEventCard.liveEndMinutes = candidate
                              }
                              onReleased: function() {
                                if (dayEventCard.isDraggingBottom) {
                                  dayEventCard.isDraggingBottom = false
                                  if (dayEventCard.liveEndMinutes !== modelData.effectiveEndMinutes) {
                                    root.updateEventTime(modelData.id, root.dayData.key, Model.formatMinutes(dayEventCard.liveStartMinutes), Model.formatMinutes(dayEventCard.liveEndMinutes))
                                  }
                                }
                              }
                            }
                          }

                          // Floating live time badge when resizing
                          Rectangle {
                            visible: dayEventCard.isDraggingBottom || dayEventCard.isDraggingTop
                            z: 50
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: dayEventCard.isDraggingTop ? parent.top : undefined
                            anchors.bottom: dayEventCard.isDraggingBottom ? parent.bottom : undefined
                            anchors.topMargin: dayEventCard.isDraggingTop ? -Style.space(26) : 0
                            anchors.bottomMargin: dayEventCard.isDraggingBottom ? -Style.space(26) : 0
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
            visible: root.viewMode === "month" || root.viewMode === "week"
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
      }
    }
  }
}
