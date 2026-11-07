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
    endTime: "15:00"
  });
  assert.equal(good.valid, true);
  assert.equal(good.title, "Sync Call");
  assert.equal(good.dateKey, "2026-11-10");
  assert.equal(good.startTime, "14:00");
  assert.equal(good.endTime, "15:00");
});
