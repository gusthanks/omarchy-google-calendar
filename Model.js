// Pure date, format, view-mode, and Google Calendar event math for the clock
// widget and its multi-view (Day / Week / Month / Year) calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node.

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

var VIEW_MODES = ["day", "week", "month", "year"]

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

var DEFAULT_EVENT_COLOR = "#039be5"

function clockNeedsSeconds(format) {
  var text = String(format === undefined || format === null ? "" : format)
  return /s/.test(text.replace(/'[^']*'?/g, ""))
}

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function parseDateKey(key) {
  var text = String(key === undefined || key === null ? "" : key).replace(/^\s+|\s+$/g, "")
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text)
  if (!match) return null
  var year = parseInt(match[1], 10)
  var month = parseInt(match[2], 10) - 1
  var day = parseInt(match[3], 10)
  if (month < 0 || month > 11 || day < 1 || day > 31) return null
  var check = new Date(Date.UTC(year, month, day))
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month || check.getUTCDate() !== day)
    return null
  return {
    year: year,
    month: month,
    day: day,
    weekday: check.getUTCDay(),
    key: dateKey(year, month, day)
  }
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(Number(year), Number(month) + 1, 0)).getUTCDate()
}

function clampDay(year, month, day) {
  var maxDay = daysInMonth(year, month)
  return Math.max(1, Math.min(maxDay, Math.round(Number(day) || 1)))
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

var DEFAULT_LIFE_EXPECTANCY = 90

function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(Date.UTC(year, month, 1)).getUTCDay() - start + 7) % 7
  var cursor = new Date(Date.UTC(year, month, 1 - leading))
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getUTCFullYear()
      var cellMonth = cursor.getUTCMonth()
      var cellDay = cursor.getUTCDate()
      var weekday = cursor.getUTCDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setUTCDate(cursor.getUTCDate() + 1)
    }
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function msUntilNextTick(nowMs, step) {
  return step - nowMs % step
}

function stepMonth(year, month, delta) {
  var target = new Date(Date.UTC(year, Number(month) + Number(delta), 1))
  return { year: target.getUTCFullYear(), month: target.getUTCMonth() }
}

// ---- Security & Sanitization Helpers ----

// Neutralizes markup-shaped input so strings passed to any shared shell
// tooltip or notification sink cannot be interpreted as Qt RichText/HTML.
function neutralizeMarkup(value, maxLen) {
  var limit = (typeof maxLen === "number" && maxLen > 0) ? maxLen : 240
  var text = String(value === undefined || value === null ? "" : value)
  // Strip control characters except newline/tab
  text = text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
  // Strip HTML/XML-like tags completely and replace residual angle brackets
  text = text.replace(/<\/?[a-zA-Z!/?][^>]*>/g, "")
  text = text.replace(/</g, "‹").replace(/>/g, "›")
  text = text.replace(/^\s+|\s+$/g, "")
  if (text.length > limit)
    text = text.substr(0, limit - 1) + "…"
  return text
}

function sanitizeHexColor(value, fallback) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (/^#[0-9a-fA-F]{6}$/.test(text)) return text.toLowerCase()
  return fallback || DEFAULT_EVENT_COLOR
}

function sanitizeHttpsUrl(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (text.indexOf("https://") !== 0) return ""
  if (/[\s<>"'`\x00-\x1f]/.test(text)) return ""
  return text.length <= 500 ? text : ""
}

function parseMinutes(hhmm) {
  var text = String(hhmm === undefined || hhmm === null ? "" : hhmm).replace(/^\s+|\s+$/g, "")
  var match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(text)
  if (!match) return -1
  return parseInt(match[1], 10) * 60 + parseInt(match[2], 10)
}

function formatMinutes(totalMinutes) {
  var clamped = Math.max(0, Math.min(1439, Math.round(Number(totalMinutes) || 0)))
  var h = Math.floor(clamped / 60)
  var m = clamped % 60
  return pad2(h) + ":" + pad2(m)
}

function sanitizeEvent(raw) {
  if (!raw || typeof raw !== "object") return null
  var startParsed = parseDateKey(raw.startDate || raw.dateKey)
  if (!startParsed) return null
  var endParsed = parseDateKey(raw.endDate || raw.endDateKey) || startParsed
  var startKey = startParsed.key
  var endKey = endParsed.key < startKey ? startKey : endParsed.key

  var allDay = Boolean(raw.allDay)
  var startTime = ""
  var endTime = ""
  var startMinutes = 0
  var endMinutes = 1440

  if (!allDay) {
    var sm = parseMinutes(raw.startTime)
    var em = parseMinutes(raw.endTime)
    if (sm >= 0) {
      startMinutes = sm
      startTime = formatMinutes(sm)
      if (em > sm) {
        endMinutes = em
        endTime = formatMinutes(em)
      } else if (em >= 0 && endKey > startKey) {
        endMinutes = em
        endTime = formatMinutes(em)
      } else {
        endMinutes = Math.min(1439, sm + 60)
        endTime = formatMinutes(endMinutes)
      }
    } else {
      allDay = true
    }
  }

  var id = neutralizeMarkup(raw.id || "", 128)
  if (!id) id = "ev:" + startKey + ":" + neutralizeMarkup(raw.title || "untitled", 32)

  var title = neutralizeMarkup(raw.title || "(Sem título)", 200) || "(Sem título)"
  var location = neutralizeMarkup(raw.location || "", 240)
  var description = neutralizeMarkup(raw.description || "", 600)
  var calendarName = neutralizeMarkup(raw.calendarName || "Google Calendar", 80)
  var htmlLink = sanitizeHttpsUrl(raw.htmlLink)
  var meetLink = sanitizeHttpsUrl(raw.meetLink)
  var actionUrl = meetLink || htmlLink

  return {
    id: id,
    remoteId: neutralizeMarkup(raw.remoteId || "", 128),
    calendarId: neutralizeMarkup(raw.calendarId || "primary", 80),
    calendarName: calendarName,
    title: title,
    startDate: startKey,
    endDate: endKey,
    startTime: startTime,
    endTime: endTime,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    allDay: allDay,
    location: location,
    description: description,
    htmlLink: htmlLink,
    meetLink: meetLink,
    actionUrl: actionUrl,
    color: sanitizeHexColor(raw.color, DEFAULT_EVENT_COLOR),
    source: neutralizeMarkup(raw.source || "local", 24)
  }
}

function compareEvents(a, b) {
  if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
  if (a.startMinutes !== b.startMinutes) return a.startMinutes - b.startMinutes
  if (a.endMinutes !== b.endMinutes) return a.endMinutes - b.endMinutes
  return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0)
}

function indexEventsByDate(events) {
  var map = {}
  if (!Array.isArray(events)) return map

  var count = Math.min(events.length, 2000)
  for (var i = 0; i < count; i++) {
    var ev = sanitizeEvent(events[i])
    if (!ev) continue
    var start = parseDateKey(ev.startDate)
    var end = parseDateKey(ev.endDate) || start
    if (!start) continue

    var cursor = new Date(Date.UTC(start.year, start.month, start.day))
    var endUtc = Date.UTC(end.year, end.month, end.day)
    var span = 0
    while (cursor.getTime() <= endUtc && span < 366) {
      var k = dateKey(cursor.getUTCFullYear(), cursor.getUTCMonth(), cursor.getUTCDate())
      if (!map[k]) map[k] = []
      map[k].push(ev)
      cursor.setUTCDate(cursor.getUTCDate() + 1)
      span++
    }
  }

  for (var dKey in map) {
    map[dKey].sort(compareEvents)
  }
  return map
}

function parseEventsPayload(rawText) {
  var empty = {
    source: "local",
    connected: false,
    syncedAt: "",
    syncedAtShort: "",
    icsUrl: "",
    hasOAuthCredentials: false,
    hasOAuthToken: false,
    lastError: "",
    events: [],
    eventsByDate: {}
  }
  var text = String(rawText === undefined || rawText === null ? "" : rawText).replace(/^\s+|\s+$/g, "")
  if (!text || text.length > 5 * 1024 * 1024) return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return empty
    var rawList = Array.isArray(parsed.events) ? parsed.events.slice(0, 2000) : []
    var cleanList = []
    for (var i = 0; i < rawList.length; i++) {
      var item = sanitizeEvent(rawList[i])
      if (item) cleanList.push(item)
    }
    var byDate = indexEventsByDate(cleanList)
    var source = neutralizeMarkup(parsed.source || "local", 24)
    return {
      source: source,
      connected: Boolean(parsed.connected),
      syncedAt: neutralizeMarkup(parsed.syncedAt || "", 40),
      syncedAtShort: neutralizeMarkup(parsed.syncedAtShort || "", 16),
      icsUrl: sanitizeHttpsUrl(parsed.icsUrl || ""),
      hasOAuthCredentials: Boolean(parsed.hasOAuthCredentials),
      hasOAuthToken: Boolean(parsed.hasOAuthToken),
      lastError: neutralizeMarkup(parsed.lastError || "", 160),
      events: cleanList,
      eventsByDate: byDate
    }
  } catch (e) {
    return empty
  }
}

// ---- Multi-View Mode & Date Stepping Math ----

function normalizeViewMode(mode) {
  var text = String(mode === undefined || mode === null ? "" : mode).replace(/^\s+|\s+$/g, "").toLowerCase()
  return VIEW_MODES.indexOf(text) !== -1 ? text : "month"
}

function nextViewMode(current, direction) {
  var mode = normalizeViewMode(current)
  var idx = VIEW_MODES.indexOf(mode)
  var delta = Number(direction) < 0 ? -1 : 1
  return VIEW_MODES[(idx + delta + VIEW_MODES.length) % VIEW_MODES.length]
}

function stepDay(year, month, day, delta) {
  var d = new Date(Date.UTC(Number(year), Number(month), Number(day) + Math.round(Number(delta) || 0)))
  var y = d.getUTCFullYear()
  var m = d.getUTCMonth()
  var dom = d.getUTCDate()
  return {
    year: y,
    month: m,
    day: dom,
    weekday: d.getUTCDay(),
    key: dateKey(y, m, dom)
  }
}

function stepWeek(year, month, day, delta) {
  return stepDay(year, month, day, Math.round(Number(delta) || 0) * 7)
}

function stepMonthDate(year, month, day, delta) {
  var nextMonth = stepMonth(year, month, delta)
  var clamped = clampDay(nextMonth.year, nextMonth.month, day)
  var d = new Date(Date.UTC(nextMonth.year, nextMonth.month, clamped))
  return {
    year: nextMonth.year,
    month: nextMonth.month,
    day: clamped,
    weekday: d.getUTCDay(),
    key: dateKey(nextMonth.year, nextMonth.month, clamped)
  }
}

function stepYearDate(year, month, day, delta) {
  var targetYear = Math.round(Number(year)) + Math.round(Number(delta) || 0)
  var targetMonth = Math.round(Number(month))
  var clamped = clampDay(targetYear, targetMonth, day)
  var d = new Date(Date.UTC(targetYear, targetMonth, clamped))
  return {
    year: targetYear,
    month: targetMonth,
    day: clamped,
    weekday: d.getUTCDay(),
    key: dateKey(targetYear, targetMonth, clamped)
  }
}

function stepByViewMode(viewMode, year, month, day, delta) {
  var mode = normalizeViewMode(viewMode)
  if (mode === "day") return stepDay(year, month, day, delta)
  if (mode === "week") return stepWeek(year, month, day, delta)
  if (mode === "year") return stepYearDate(year, month, day, delta)
  return stepMonthDate(year, month, day, delta)
}

// ---- Enriched Grid Builders for Month, Week, Day, and Year Views ----

function eventsForDateKey(eventsByDate, key) {
  if (!eventsByDate || typeof eventsByDate !== "object") return []
  var list = eventsByDate[String(key || "")]
  return Array.isArray(list) ? list : []
}

function dotColorsForEvents(events, maxDots) {
  var limit = maxDots || 3
  var colors = []
  if (!Array.isArray(events)) return colors
  for (var i = 0; i < events.length && colors.length < limit; i++) {
    var c = (events[i] && events[i].color) ? events[i].color : DEFAULT_EVENT_COLOR
    colors.push(c)
  }
  return colors
}

function monthGridWithEvents(year, month, weekStart, todayKey, selectedKey, eventsByDate) {
  var baseWeeks = monthGrid(year, month, weekStart, todayKey)
  var sel = String(selectedKey || "")
  var outWeeks = []

  for (var w = 0; w < baseWeeks.length; w++) {
    var row = baseWeeks[w]
    var days = []
    for (var d = 0; d < row.days.length; d++) {
      var cell = row.days[d]
      var evs = eventsForDateKey(eventsByDate, cell.key)
      days.push({
        key: cell.key,
        year: cell.year,
        month: cell.month,
        day: cell.day,
        weekday: cell.weekday,
        inMonth: cell.inMonth,
        weekend: cell.weekend,
        today: cell.today,
        selected: cell.key === sel,
        events: evs,
        eventCount: evs.length,
        hasEvents: evs.length > 0,
        dotColors: dotColorsForEvents(evs, 3)
      })
    }
    outWeeks.push({
      week: row.week,
      days: days
    })
  }
  return outWeeks
}

function weekViewModel(year, month, day, weekStart, todayKey, selectedKey, eventsByDate, nowMinutes) {
  var start = normalizedWeekStart(weekStart, 1)
  var target = new Date(Date.UTC(Number(year), Number(month), Number(day)))
  var leading = (target.getUTCDay() - start + 7) % 7
  var cursor = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), target.getUTCDate() - leading))
  var today = String(todayKey || "")
  var sel = String(selectedKey || "")
  var nowMins = typeof nowMinutes === "number" ? nowMinutes : -1

  var days = []
  var thursday = null
  var totalEvents = 0
  var firstEventHour = 8

  for (var i = 0; i < 7; i++) {
    var cy = cursor.getUTCFullYear()
    var cm = cursor.getUTCMonth()
    var cd = cursor.getUTCDate()
    var wd = cursor.getUTCDay()
    var key = dateKey(cy, cm, cd)
    if (wd === 4) thursday = { year: cy, month: cm, day: cd }

    var evs = eventsForDateKey(eventsByDate, key)
    var allDayList = []
    var timedList = []
    for (var j = 0; j < evs.length; j++) {
      var ev = evs[j]
      if (ev.allDay) {
        allDayList.push(ev)
      } else {
        var eff = effectiveMinutesForDate(ev, key)
        var copy = {}
        for (var k in ev) copy[k] = ev[k]
        copy.effectiveStartMinutes = eff.startMinutes
        copy.effectiveEndMinutes = eff.endMinutes
        copy.timeLabel = eff.timeLabel
        copy.durationMinutes = Math.max(15, eff.endMinutes - eff.startMinutes)
        copy.isHappeningNow = (key === today) && nowMins >= eff.startMinutes && nowMins < eff.endMinutes
        copy.isPast = (key === today) && nowMins >= eff.endMinutes
        timedList.push(copy)
      }
    }
    var laidOutTimed = layoutTimedEvents(timedList)
    if (laidOutTimed.length > 0) {
      var earliest = Math.floor(laidOutTimed[0].effectiveStartMinutes / 60)
      if (earliest < firstEventHour) firstEventHour = earliest
    }
    totalEvents += evs.length

    days.push({
      key: key,
      year: cy,
      month: cm,
      day: cd,
      weekday: wd,
      weekend: wd === 0 || wd === 6,
      today: key === today,
      selected: key === sel,
      events: evs,
      allDayEvents: allDayList,
      timedEvents: laidOutTimed,
      eventCount: evs.length,
      hasEvents: evs.length > 0,
      dotColors: dotColorsForEvents(evs, 3)
    })
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  }

  var anchor = thursday || days[0]
  return {
    week: isoWeek(anchor.year, anchor.month, anchor.day),
    startKey: days[0].key,
    endKey: days[6].key,
    startYear: days[0].year,
    startMonth: days[0].month,
    startDay: days[0].day,
    endYear: days[6].year,
    endMonth: days[6].month,
    endDay: days[6].day,
    totalEvents: totalEvents,
    firstEventHour: firstEventHour,
    days: days
  }
}

function layoutTimedEvents(timedEvents) {
  if (!timedEvents || timedEvents.length === 0) return []
  var list = timedEvents.slice()

  // Sort by start time ascending, then duration descending
  list.sort(function(a, b) {
    if (a.effectiveStartMinutes !== b.effectiveStartMinutes)
      return a.effectiveStartMinutes - b.effectiveStartMinutes
    var durA = (a.effectiveEndMinutes || 0) - (a.effectiveStartMinutes || 0)
    var durB = (b.effectiveEndMinutes || 0) - (b.effectiveStartMinutes || 0)
    if (durA !== durB) return durB - durA
    return (a.title || "") < (b.title || "") ? -1 : 1
  })

  // Partition into overlapping clusters
  var clusters = []
  var currentCluster = []
  var clusterMaxEnd = -1

  for (var i = 0; i < list.length; i++) {
    var ev = list[i]
    var start = ev.effectiveStartMinutes
    var end = Math.max(start + 15, ev.effectiveEndMinutes)
    if (currentCluster.length === 0 || start < clusterMaxEnd) {
      currentCluster.push(ev)
      if (end > clusterMaxEnd) clusterMaxEnd = end
    } else {
      clusters.push(currentCluster)
      currentCluster = [ev]
      clusterMaxEnd = end
    }
  }
  if (currentCluster.length > 0) {
    clusters.push(currentCluster)
  }

  // Assign columns within each cluster using interval coloring
  for (var c = 0; c < clusters.length; c++) {
    var cluster = clusters[c]
    var colEnds = []
    for (var j = 0; j < cluster.length; j++) {
      var cev = cluster[j]
      var cStart = cev.effectiveStartMinutes
      var cEnd = Math.max(cStart + 15, cev.effectiveEndMinutes)
      var placedCol = -1
      for (var col = 0; col < colEnds.length; col++) {
        if (colEnds[col] <= cStart) {
          placedCol = col
          colEnds[col] = cEnd
          break
        }
      }
      if (placedCol === -1) {
        placedCol = colEnds.length
        colEnds.push(cEnd)
      }
      cev.colIndex = placedCol
    }
    var numCols = Math.max(1, colEnds.length)
    for (var k = 0; k < cluster.length; k++) {
      cluster[k].totalCols = numCols
    }
  }

  return list
}

function effectiveMinutesForDate(ev, key) {
  if (!ev || ev.allDay) {
    return {
      startMinutes: 0,
      endMinutes: 1440,
      timeLabel: ""
    }
  }
  var dKey = String(key || "")
  if (ev.endDate > ev.startDate) {
    if (dKey === ev.startDate) {
      return {
        startMinutes: ev.startMinutes,
        endMinutes: 1440,
        timeLabel: ev.startTime + " – 24:00"
      }
    }
    if (dKey === ev.endDate) {
      var endM = ev.endMinutes > 0 ? ev.endMinutes : 1440
      return {
        startMinutes: 0,
        endMinutes: endM,
        timeLabel: "00:00 – " + (ev.endTime || "24:00")
      }
    }
    return {
      startMinutes: 0,
      endMinutes: 1440,
      timeLabel: "00:00 – 24:00"
    }
  }
  return {
    startMinutes: ev.startMinutes,
    endMinutes: ev.endMinutes,
    timeLabel: ev.startTime + (ev.endTime ? " – " + ev.endTime : "")
  }
}

function formatEventTooltip(ev, allDayLabel) {
  if (!ev || typeof ev !== "object") return ""
  var parts = []
  var timePart = ev.allDay
    ? neutralizeMarkup(allDayLabel || "Dia inteiro", 40)
    : (ev.timeLabel || (ev.startTime + (ev.endTime ? " – " + ev.endTime : "")))
  if (timePart) parts.push("[" + neutralizeMarkup(timePart, 32) + "] " + neutralizeMarkup(ev.title || "", 120))
  else parts.push(neutralizeMarkup(ev.title || "", 120))
  if (ev.location) parts.push("📍 " + neutralizeMarkup(ev.location, 100))
  if (ev.meetLink) parts.push("󰕧 Meet")
  if (ev.description) parts.push(neutralizeMarkup(ev.description, 160))
  if (ev.calendarName) parts.push("(" + neutralizeMarkup(ev.calendarName, 50) + ")")
  return neutralizeMarkup(parts.join(" · "), 300)
}

function dayViewModel(year, month, day, todayKey, nowMinutes, eventsByDate) {
  var d = new Date(Date.UTC(Number(year), Number(month), Number(day)))
  var cy = d.getUTCFullYear()
  var cm = d.getUTCMonth()
  var cd = d.getUTCDate()
  var wd = d.getUTCDay()
  var key = dateKey(cy, cm, cd)
  var today = String(todayKey || "")
  var isToday = key === today
  var nowMins = typeof nowMinutes === "number" ? nowMinutes : -1

  var dayDiff = null
  var todayParsed = parseDateKey(today)
  if (todayParsed) {
    dayDiff = Math.round((Date.UTC(cy, cm, cd) - Date.UTC(todayParsed.year, todayParsed.month, todayParsed.day)) / MS_PER_DAY)
  }

  var rawEvents = eventsForDateKey(eventsByDate, key)
  var allDayEvents = []
  var timedEvents = []

  for (var i = 0; i < rawEvents.length; i++) {
    var ev = rawEvents[i]
    if (ev.allDay) {
      allDayEvents.push(ev)
    } else {
      var eff = effectiveMinutesForDate(ev, key)
      var active = isToday && nowMins >= eff.startMinutes && nowMins < eff.endMinutes
      var past = isToday && nowMins >= eff.endMinutes
      var copy = {}
      for (var k in ev) copy[k] = ev[k]
      copy.effectiveStartMinutes = eff.startMinutes
      copy.effectiveEndMinutes = eff.endMinutes
      copy.timeLabel = eff.timeLabel
      copy.durationMinutes = Math.max(15, eff.endMinutes - eff.startMinutes)
      copy.isHappeningNow = active
      copy.isPast = past
      timedEvents.push(copy)
    }
  }

  var laidOut = layoutTimedEvents(timedEvents)

  var firstEventHour = 8
  if (laidOut.length > 0) {
    firstEventHour = Math.max(0, Math.min(23, Math.floor(laidOut[0].effectiveStartMinutes / 60)))
  } else if (isToday && nowMins >= 0) {
    firstEventHour = Math.max(0, Math.min(23, Math.floor(nowMins / 60)))
  }

  var slots = []
  for (var h = 0; h < 24; h++) {
    var slotStart = h * 60
    var slotEnd = (h + 1) * 60
    var slotEvents = []
    for (var j = 0; j < laidOut.length; j++) {
      var tev = laidOut[j]
      if (tev.effectiveStartMinutes >= slotStart && tev.effectiveStartMinutes < slotEnd) {
        slotEvents.push(tev)
      }
    }
    slots.push({
      hour: h,
      label: pad2(h) + ":00",
      isCurrentHour: isToday && nowMins >= slotStart && nowMins < slotEnd,
      events: slotEvents,
      hasEvents: slotEvents.length > 0
    })
  }

  return {
    key: key,
    year: cy,
    month: cm,
    day: cd,
    weekday: wd,
    week: isoWeek(cy, cm, cd),
    isToday: isToday,
    dayDiff: dayDiff,
    allDayEvents: allDayEvents,
    timedEvents: laidOut,
    firstEventHour: firstEventHour,
    allEvents: rawEvents,
    eventCount: rawEvents.length,
    slots: slots
  }
}

function yearViewModel(year, weekStart, todayKey, selectedKey, eventsByDate) {
  var y = Math.round(Number(year))
  var sel = String(selectedKey || "")
  var months = []

  for (var m = 0; m < 12; m++) {
    var baseWeeks = monthGrid(y, m, weekStart, todayKey)
    var weeks = []
    var monthTotalEvents = 0
    var busyDaysCount = 0

    for (var w = 0; w < baseWeeks.length; w++) {
      var days = []
      for (var d = 0; d < baseWeeks[w].days.length; d++) {
        var cell = baseWeeks[w].days[d]
        var evs = cell.inMonth ? eventsForDateKey(eventsByDate, cell.key) : []
        if (cell.inMonth && evs.length > 0) {
          monthTotalEvents += evs.length
          busyDaysCount++
        }
        days.push({
          key: cell.key,
          year: cell.year,
          month: cell.month,
          day: cell.day,
          weekday: cell.weekday,
          inMonth: cell.inMonth,
          weekend: cell.weekend,
          today: cell.inMonth && cell.today,
          selected: cell.inMonth && (cell.key === sel),
          eventCount: evs.length,
          hasEvents: cell.inMonth && (evs.length > 0),
          primaryColor: evs.length > 0 ? evs[0].color : ""
        })
      }
      weeks.push({
        week: baseWeeks[w].week,
        days: days
      })
    }

    months.push({
      year: y,
      month: m,
      totalEvents: monthTotalEvents,
      busyDaysCount: busyDaysCount,
      weeks: weeks
    })
  }
  return months
}

// ---- Bar Upcoming Event Indicator & Tooltip Summary ----

function upcomingEventSummary(eventsByDate, nowDate, maxHorizonMinutes) {
  var horizon = typeof maxHorizonMinutes === "number" && maxHorizonMinutes > 0 ? maxHorizonMinutes : 720
  var now = nowDate instanceof Date ? nowDate : new Date()
  var todayKey = keyForDate(now)
  var nowMinutes = now.getHours() * 60 + now.getMinutes()
  var todayEvents = eventsForDateKey(eventsByDate, todayKey)

  var activeEvent = null
  var nextEvent = null
  var minutesUntilNext = -1

  for (var i = 0; i < todayEvents.length; i++) {
    var ev = todayEvents[i]
    if (ev.allDay) continue
    var eff = effectiveMinutesForDate(ev, todayKey)
    if (nowMinutes >= eff.startMinutes && nowMinutes < eff.endMinutes) {
      if (!activeEvent) activeEvent = ev
      continue
    }
    if (eff.startMinutes > nowMinutes) {
      var diff = eff.startMinutes - nowMinutes
      if (diff <= horizon && (nextEvent === null || diff < minutesUntilNext)) {
        nextEvent = ev
        minutesUntilNext = diff
      }
    }
  }

  var nextIsTomorrow = false
  if (!activeEvent && nextEvent === null) {
    var tomorrowDate = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate() + 1))
    var tomorrowKey = dateKey(tomorrowDate.getUTCFullYear(), tomorrowDate.getUTCMonth(), tomorrowDate.getUTCDate())
    var tomorrowEvents = eventsForDateKey(eventsByDate, tomorrowKey)
    for (var j = 0; j < tomorrowEvents.length; j++) {
      var tev = tomorrowEvents[j]
      if (tev.allDay) continue
      var teff = effectiveMinutesForDate(tev, tomorrowKey)
      var tdiff = (1440 - nowMinutes) + teff.startMinutes
      if (tdiff <= horizon && (nextEvent === null || tdiff < minutesUntilNext)) {
        nextEvent = tev
        minutesUntilNext = tdiff
        nextIsTomorrow = true
      }
    }
  }

  var badgeText = ""
  var focusEvent = activeEvent || nextEvent
  if (activeEvent) {
    badgeText = neutralizeMarkup(activeEvent.title, 22)
  } else if (nextEvent && (minutesUntilNext <= 180 || nextIsTomorrow)) {
    var prefix = nextIsTomorrow ? "→ " : ""
    badgeText = prefix + nextEvent.startTime + " " + neutralizeMarkup(nextEvent.title, 18)
  }

  return {
    hasEventsToday: todayEvents.length > 0,
    todayCount: todayEvents.length,
    activeEvent: activeEvent,
    nextEvent: nextEvent,
    nextIsTomorrow: nextIsTomorrow,
    focusEvent: focusEvent,
    minutesUntilNext: minutesUntilNext,
    barBadgeText: badgeText
  }
}

function searchEvents(events, query) {
  if (!Array.isArray(events)) return []
  var q = String(query === undefined || query === null ? "" : query).trim().toLowerCase()
  if (q === "") return events.slice()
  var results = []
  for (var i = 0; i < events.length; i++) {
    var ev = events[i]
    if (!ev) continue
    var t = (ev.title || "").toLowerCase()
    var l = (ev.location || "").toLowerCase()
    var d = (ev.description || "").toLowerCase()
    var c = (ev.calendarName || "").toLowerCase()
    if (t.indexOf(q) !== -1 || l.indexOf(q) !== -1 || d.indexOf(q) !== -1 || c.indexOf(q) !== -1) {
      results.push(ev)
    }
  }
  return results
}

function validateQuickEvent(input) {
  var raw = input || {}
  var title = neutralizeMarkup(raw.title || "", 200)
  if (!title) return { valid: false, error: "missing-title" }

  var dateParsed = parseDateKey(raw.dateKey)
  if (!dateParsed) return { valid: false, error: "invalid-date" }

  var allDay = Boolean(raw.allDay)
  var startTime = "09:00"
  var endTime = "10:00"

  if (!allDay) {
    var sm = parseMinutes(raw.startTime)
    var em = parseMinutes(raw.endTime)
    if (sm < 0) sm = 9 * 60
    if (em <= sm) em = Math.min(1439, sm + 60)
    startTime = formatMinutes(sm)
    endTime = formatMinutes(em)
  }

  var location = neutralizeMarkup(raw.location || "", 240)
  var description = neutralizeMarkup(raw.description || "", 600)
  var addMeet = Boolean(raw.addMeet)
  return {
    valid: true,
    title: title,
    dateKey: dateParsed.key,
    startTime: allDay ? "" : startTime,
    endTime: allDay ? "" : endTime,
    allDay: allDay,
    location: location,
    description: description,
    addMeet: addMeet
  }
}

function latLonToTile(lat, lon, zoom) {
  var z = Math.max(1, Math.min(18, Math.floor(zoom || 15)))
  var nLat = Number(lat) || 0
  var nLon = Number(lon) || 0
  var x = Math.floor((nLon + 180.0) / 360.0 * Math.pow(2, z))
  var latRad = nLat * Math.PI / 180.0
  latRad = Math.max(-1.4844, Math.min(1.4844, latRad))
  var y = Math.floor((1.0 - Math.log(Math.tan(latRad) + 1.0 / Math.cos(latRad)) / Math.PI) / 2.0 * Math.pow(2, z))
  return { z: z, x: x, y: y }
}

function getTileUrl(z, x, y) {
  var safeZ = Math.max(1, Math.min(18, Math.floor(z || 15)))
  var maxTile = Math.pow(2, safeZ)
  var safeX = ((Math.floor(x) % maxTile) + maxTile) % maxTile
  var safeY = Math.max(0, Math.min(maxTile - 1, Math.floor(y)))
  return "https://basemaps.cartocdn.com/dark_all/" + safeZ + "/" + safeX + "/" + safeY + ".png"
}

function generateMeetCode() {
  var chars = "abcdefghijklmnopqrstuvwxyz"
  function r(n) {
    var s = ""
    for (var i = 0; i < n; i++) s += chars.charAt(Math.floor(Math.random() * chars.length))
    return s
  }
  return r(3) + "-" + r(4) + "-" + r(3)
}

if (typeof module !== "undefined") {
  module.exports = {
    msUntilNextTick: msUntilNextTick,
    pad2: pad2,
    coerceWeekStart: coerceWeekStart,
    dateKey: dateKey,
    keyForDate: keyForDate,
    parseDateKey: parseDateKey,
    daysInMonth: daysInMonth,
    clampDay: clampDay,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockNeedsSeconds: clockNeedsSeconds,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    neutralizeMarkup: neutralizeMarkup,
    sanitizeHexColor: sanitizeHexColor,
    sanitizeHttpsUrl: sanitizeHttpsUrl,
    parseMinutes: parseMinutes,
    formatMinutes: formatMinutes,
    sanitizeEvent: sanitizeEvent,
    indexEventsByDate: indexEventsByDate,
    parseEventsPayload: parseEventsPayload,
    VIEW_MODES: VIEW_MODES,
    normalizeViewMode: normalizeViewMode,
    nextViewMode: nextViewMode,
    stepDay: stepDay,
    stepWeek: stepWeek,
    stepMonthDate: stepMonthDate,
    stepYearDate: stepYearDate,
    stepByViewMode: stepByViewMode,
    eventsForDateKey: eventsForDateKey,
    effectiveMinutesForDate: effectiveMinutesForDate,
    formatEventTooltip: formatEventTooltip,
    monthGridWithEvents: monthGridWithEvents,
    weekViewModel: weekViewModel,
    dayViewModel: dayViewModel,
    yearViewModel: yearViewModel,
    upcomingEventSummary: upcomingEventSummary,
    validateQuickEvent: validateQuickEvent,
    searchEvents: searchEvents,
    layoutTimedEvents: layoutTimedEvents,
    latLonToTile: latLonToTile,
    getTileUrl: getTileUrl,
    generateMeetCode: generateMeetCode
  }
}
