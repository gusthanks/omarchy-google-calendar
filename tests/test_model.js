// Unit tests for Model.js pure calendar logic, security sanitization, and view models.
// Run with: node --test tests/test_model.js

const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../Model.js");

test("dateKey and parseDateKey round-trip", () => {
  const key = Model.dateKey(2026, 10, 7);
  assert.equal(key, "2026-11-07");

  const parsed = Model.parseDateKey("2026-11-07");
  assert.deepEqual(parsed, {
    year: 2026,
    month: 10,
    day: 7,
    weekday: 6, // Saturday
    key: "2026-11-07"
  });

  // Leap year check
  assert.notEqual(Model.parseDateKey("2024-02-29"), null);
  assert.equal(Model.parseDateKey("2023-02-29"), null);
  assert.equal(Model.parseDateKey("invalid-date"), null);
  assert.equal(Model.parseDateKey("2026-13-01"), null);
  assert.equal(Model.parseDateKey(""), null);
});

test("daysInMonth and clampDay", () => {
  assert.equal(Model.daysInMonth(2026, 1), 28); // Feb non-leap
  assert.equal(Model.daysInMonth(2024, 1), 29); // Feb leap
  assert.equal(Model.daysInMonth(2026, 0), 31); // Jan
  assert.equal(Model.daysInMonth(2026, 3), 30); // April

  assert.equal(Model.clampDay(2026, 1, 31), 28);
  assert.equal(Model.clampDay(2024, 1, 31), 29);
  assert.equal(Model.clampDay(2026, 1, 0), 1);
});

test("weekStart normalization and toggling", () => {
  assert.equal(Model.normalizedWeekStart("monday"), 1);
  assert.equal(Model.normalizedWeekStart("sunday"), 0);
  assert.equal(Model.normalizedWeekStart(0), 0);
  assert.equal(Model.normalizedWeekStart(1), 1);
  assert.equal(Model.normalizedWeekStart(null, 0), 0);

  assert.equal(Model.toggledWeekStart(1), 0);
  assert.equal(Model.toggledWeekStart(0), 1);

  assert.deepEqual(Model.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0]);
  assert.deepEqual(Model.weekdayOrder(0), [0, 1, 2, 3, 4, 5, 6]);
});

test("isoWeek and yearProgress", () => {
  // 2026-01-01 is Thursday -> ISO week 1
  assert.equal(Model.isoWeek(2026, 0, 1), 1);
  assert.equal(Model.dayOfYear(2026, 0, 1), 1);

  const prog = Model.yearProgress(2026, 0, 1);
  assert.equal(prog, 0);

  const percent = Model.yearProgressPercent(2026, 5, 30);
  assert.ok(percent >= 49 && percent <= 51);
});

test("lifeProgress and parseBirthYear", () => {
  assert.equal(Model.parseBirthYear("1995", 2026), 1995);
  assert.equal(Model.parseBirthYear("invalid", 2026), 0);
  assert.equal(Model.ageFromBirthYear("1995", 2026), 31);

  assert.equal(Model.lifeProgress(30, 90), 30 / 90);
  assert.equal(Model.lifeProgressPercent(45, 90), 50);
});

test("clockFormatRing and clockNeedsSeconds", () => {
  assert.equal(Model.clockNeedsSeconds("HH:mm:ss"), true);
  assert.equal(Model.clockNeedsSeconds("HH:mm"), false);
  assert.equal(Model.clockNeedsSeconds("HH:mm 'ss'"), false); // quoted literal

  const ring = Model.clockFormatRing("HH:mm", "dddd HH:mm", ["HH:mm", "h:mm AP"]);
  assert.ok(ring.length >= 2);
  const next = Model.nextClockFormat(ring, ring[0]);
  assert.equal(next, ring[1]);
});

test("neutralizeMarkup prevents Qt RichText injection", () => {
  const bad = '<script>alert("xss")</script><b>Bold Title</b> & score < 3 and > 1';
  const clean = Model.neutralizeMarkup(bad, 200);
  assert.equal(clean.includes("<"), false);
  assert.equal(clean.includes(">"), false);
  assert.ok(clean.includes("Bold Title"));
  assert.ok(clean.includes("‹ 3"));
  assert.ok(clean.includes("› 1"));
});

test("sanitizeHexColor and sanitizeHttpsUrl", () => {
  assert.equal(Model.sanitizeHexColor("#039be5"), "#039be5");
  assert.equal(Model.sanitizeHexColor("#AABBCC"), "#aabbcc");
  assert.equal(Model.sanitizeHexColor("invalid", "#000000"), "#000000");

  assert.equal(Model.sanitizeHttpsUrl("https://meet.google.com/abc"), "https://meet.google.com/abc");
  assert.equal(Model.sanitizeHttpsUrl("http://insecure.com"), "");
  assert.equal(Model.sanitizeHttpsUrl("javascript:evil()"), "");
});

test("sanitizeEvent and indexEventsByDate", () => {
  const rawEv = {
    id: "test-1",
    title: "Sprint Planning",
    startDate: "2026-11-07",
    endDate: "2026-11-07",
    startTime: "10:00",
    endTime: "11:00",
    allDay: false,
    location: "Meeting Room A",
    color: "#33B679"
  };

  const sanitized = Model.sanitizeEvent(rawEv);
  assert.equal(sanitized.id, "test-1");
  assert.equal(sanitized.title, "Sprint Planning");
  assert.equal(sanitized.startMinutes, 600);
  assert.equal(sanitized.endMinutes, 660);
  assert.equal(sanitized.color, "#33b679");

  const byDate = Model.indexEventsByDate([sanitized]);
  assert.ok(byDate["2026-11-07"]);
  assert.equal(byDate["2026-11-07"].length, 1);
  assert.equal(byDate["2026-11-07"][0].id, "test-1");
});

test("multi-day event index across all dates in range", () => {
  const multiDay = {
    id: "conf-1",
    title: "Tech Conference",
    startDate: "2026-11-10",
    endDate: "2026-11-12",
    allDay: true
  };
  const byDate = Model.indexEventsByDate([multiDay]);
  assert.ok(byDate["2026-11-10"]);
  assert.ok(byDate["2026-11-11"]);
  assert.ok(byDate["2026-11-12"]);
  assert.equal(byDate["2026-11-13"], undefined);
});

test("upcomingEventSummary with active event and lookahead to tomorrow", () => {
  const now = new Date(2026, 10, 7, 10, 15); // 10:15
  const activeEv = {
    id: "act-1",
    title: "Live Standup",
    startDate: "2026-11-07",
    endDate: "2026-11-07",
    startTime: "10:00",
    endTime: "10:30",
    allDay: false
  };
  const byDate1 = Model.indexEventsByDate([activeEv]);
  const sum1 = Model.upcomingEventSummary(byDate1, now, 720);
  assert.notEqual(sum1.activeEvent, null);
  assert.equal(sum1.activeEvent.title, "Live Standup");
  assert.equal(sum1.barBadgeText, "Live Standup");

  // Late evening lookahead to tomorrow morning
  const lateEvening = new Date(2026, 10, 7, 22, 30); // 22:30
  const tomorrowEv = {
    id: "tmrw-1",
    title: "Client Pitch",
    startDate: "2026-11-08",
    endDate: "2026-11-08",
    startTime: "09:00",
    endTime: "10:00",
    allDay: false
  };
  const byDate2 = Model.indexEventsByDate([tomorrowEv]);
  const sum2 = Model.upcomingEventSummary(byDate2, lateEvening, 720);
  assert.equal(sum2.activeEvent, null);
  assert.notEqual(sum2.nextEvent, null);
  assert.equal(sum2.nextEvent.title, "Client Pitch");
  assert.equal(sum2.nextIsTomorrow, true);
  assert.equal(sum2.barBadgeText, "→ 09:00 Client Pitch");
});

test("upcomingEventSummary resolves both active and upcoming back-to-back events", () => {
  const now = new Date(2026, 10, 7, 10, 20); // 10:20
  const ev1 = {
    id: "m-1",
    title: "Current Sync",
    startDate: "2026-11-07",
    endDate: "2026-11-07",
    startTime: "10:00",
    endTime: "10:30",
    allDay: false
  };
  const ev2 = {
    id: "m-2",
    title: "Next Workshop",
    startDate: "2026-11-07",
    endDate: "2026-11-07",
    startTime: "10:30",
    endTime: "11:30",
    allDay: false
  };
  const byDate = Model.indexEventsByDate([ev1, ev2]);
  const summary = Model.upcomingEventSummary(byDate, now, 720);
  assert.notEqual(summary.activeEvent, null);
  assert.equal(summary.activeEvent.title, "Current Sync");
  assert.notEqual(summary.nextEvent, null);
  assert.equal(summary.nextEvent.title, "Next Workshop");
  assert.equal(summary.minutesUntilNext, 10);
  assert.equal(summary.barBadgeText, "Current Sync");
});

test("searchEvents helper filters accurately", () => {
  const events = [
    { title: "Design Review", location: "Figma", description: "UI components" },
    { title: "Budget Planning", location: "Finance Wing", description: "Q4 forecast" },
    { title: "Doctor Appointment", location: "Clinic", description: "" }
  ];

  const resDesign = Model.searchEvents(events, "design");
  assert.equal(resDesign.length, 1);
  assert.equal(resDesign[0].title, "Design Review");

  const resFinance = Model.searchEvents(events, "finance");
  assert.equal(resFinance.length, 1);
  assert.equal(resFinance[0].title, "Budget Planning");

  const resQ4 = Model.searchEvents(events, "q4");
  assert.equal(resQ4.length, 1);
  assert.equal(resQ4[0].title, "Budget Planning");

  assert.equal(Model.searchEvents(events, "").length, 3);
});

test("quickEvent validation", () => {
  assert.equal(Model.validateQuickEvent({}).valid, false);
  assert.equal(Model.validateQuickEvent({ title: "Test" }).valid, false);

  const good = Model.validateQuickEvent({
    title: "Sync Call",
    dateKey: "2026-11-10",
    startTime: "14:00",
    endTime: "15:00",
    addMeet: true
  });
  assert.equal(good.valid, true);
  assert.equal(good.title, "Sync Call");
  assert.equal(good.dateKey, "2026-11-10");
  assert.equal(good.startTime, "14:00");
  assert.equal(good.endTime, "15:00");
  assert.equal(good.addMeet, true);

  const tip = Model.formatEventTooltip({
    title: "Sync Call",
    startTime: "14:00",
    endTime: "15:00",
    meetLink: "https://meet.google.com/abc-defg-hij",
    location: "Online Room"
  });
  assert.ok(tip.includes("󰕧 Meet"));
  assert.ok(tip.includes("Online Room"));
});

test("yearViewModel suppresses today and selected for days outside the month", () => {
  // 2026-11-07 is today. In October (month index 9), November 7 falls in week 6.
  const yearData = Model.yearViewModel(2026, 0, "2026-11-07", "2026-11-07", {});
  assert.equal(yearData.length, 12);

  const october = yearData[9];
  assert.equal(october.month, 9);

  // In October, all days with inMonth: false must have today: false and selected: false
  for (const week of october.weeks) {
    for (const day of week.days) {
      if (!day.inMonth) {
        assert.equal(day.today, false, `Leading/trailing day ${day.key} in October must not be marked today`);
        assert.equal(day.selected, false, `Leading/trailing day ${day.key} in October must not be marked selected`);
      }
    }
  }

  // In November (month index 10), day 7 has inMonth: true and today: true
  const november = yearData[10];
  let foundToday = false;
  for (const week of november.weeks) {
    for (const day of week.days) {
      if (day.inMonth && day.day === 7) {
        assert.equal(day.today, true);
        foundToday = true;
      }
    }
  }
  assert.equal(foundToday, true);
});

test("layoutTimedEvents computes parallel columns for overlapping events", () => {
  // Test case 1: Single non-overlapping event
  const single = Model.layoutTimedEvents([
    { title: "Solo Event", effectiveStartMinutes: 480, effectiveEndMinutes: 540 }
  ]);
  assert.equal(single.length, 1);
  assert.equal(single[0].colIndex, 0);
  assert.equal(single[0].totalCols, 1);

  // Test case 2: Two overlapping events (8:00 - 10:00 and 9:00 - 11:00)
  const overlapping = Model.layoutTimedEvents([
    { title: "Event A", effectiveStartMinutes: 480, effectiveEndMinutes: 600 },
    { title: "Event B", effectiveStartMinutes: 540, effectiveEndMinutes: 660 }
  ]);
  assert.equal(overlapping.length, 2);
  assert.equal(overlapping[0].colIndex, 0);
  assert.equal(overlapping[0].totalCols, 2);
  assert.equal(overlapping[1].colIndex, 1);
  assert.equal(overlapping[1].totalCols, 2);

  // Test case 3: Consecutive non-overlapping events (8:00-9:00 and 9:00-10:00)
  const consecutive = Model.layoutTimedEvents([
    { title: "First", effectiveStartMinutes: 480, effectiveEndMinutes: 540 },
    { title: "Second", effectiveStartMinutes: 540, effectiveEndMinutes: 600 }
  ]);
  assert.equal(consecutive.length, 2);
  assert.equal(consecutive[0].colIndex, 0);
  assert.equal(consecutive[0].totalCols, 1);
  assert.equal(consecutive[1].colIndex, 0);
  assert.equal(consecutive[1].totalCols, 1);
});

test("dayViewModel and weekViewModel produce laid out timed events with positions", () => {
  const eventsByDate = {
    "2026-11-06": [
      Model.sanitizeEvent({
        id: "ev1",
        title: "Will",
        startDate: "2026-11-06",
        startTime: "08:00",
        endTime: "18:00"
      }),
      Model.sanitizeEvent({
        id: "ev2",
        title: "Afternoon Standup",
        startDate: "2026-11-06",
        startTime: "14:00",
        endTime: "14:30"
      })
    ]
  };

  const dayData = Model.dayViewModel(2026, 10, 6, "2026-11-07", 720, eventsByDate);
  assert.equal(dayData.timedEvents.length, 2);
  // Will event (8:00-18:00) overlaps with Afternoon Standup (14:00-14:30)
  assert.equal(dayData.timedEvents[0].effectiveStartMinutes, 480);
  assert.equal(dayData.timedEvents[0].effectiveEndMinutes, 1080);
  assert.equal(dayData.timedEvents[0].durationMinutes, 600); // 10 hours!
  assert.equal(dayData.timedEvents[0].totalCols, 2);
  assert.equal(dayData.timedEvents[1].totalCols, 2);
  assert.equal(dayData.firstEventHour, 8);

  // In week view, Friday Nov 6 must also have laid-out timed events
  const weekData = Model.weekViewModel(2026, 10, 7, 0, "2026-11-07", "2026-11-07", eventsByDate, 720);
  const friday = weekData.days.find(d => d.key === "2026-11-06");
  assert.ok(friday);
  assert.equal(friday.timedEvents.length, 2);
  assert.equal(friday.timedEvents[0].totalCols, 2);
  assert.equal(friday.timedEvents[0].durationMinutes, 600);
});

test("latLonToTile, getTileUrl, and generateMeetCode", () => {
  // Test tile calculation for Sao Paulo (lat: -23.55, lon: -46.63)
  const tile = Model.latLonToTile(-23.55, -46.63, 15);
  assert.equal(tile.z, 15);
  assert.ok(tile.x > 0);
  assert.ok(tile.y > 0);

  const url = Model.getTileUrl(tile.z, tile.x, tile.y);
  assert.ok(url.startsWith("https://basemaps.cartocdn.com/dark_all/15/"));
  assert.ok(url.endsWith(".png"));

  // Test meet code format: xxx-yyyy-zzz
  const code = Model.generateMeetCode();
  assert.match(code, /^[a-z]{3}-[a-z]{4}-[a-z]{3}$/);
});
