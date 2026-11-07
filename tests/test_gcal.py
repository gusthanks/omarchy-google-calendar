#!/usr/bin/env python3
"""
Unit tests for omarchy-gcal RFC 5545 parsing, event math, and backend CLI.
Run with: python3 -m unittest discover -s tests -p "test_*.py"
"""

import datetime
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

# Load omarchy-gcal module dynamically (file does not have .py extension)
REPO_ROOT = Path(__file__).resolve().parent.parent
GCAL_SCRIPT = REPO_ROOT / "omarchy-gcal"
loader = importlib.machinery.SourceFileLoader("omarchy_gcal", str(GCAL_SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
gcal = importlib.util.module_from_spec(spec)
loader.exec_module(gcal)


class TestIcsParsing(unittest.TestCase):
    def setUp(self):
        self.tz = datetime.timezone(datetime.timedelta(hours=-3)) # UTC-3

    def test_unfold_ics_lines(self):
        raw = "SUMMARY:Meeting with \r\n team\r\n  and client\nDESCRIPTION:Hello\n"
        lines = gcal.unfold_ics_lines(raw)
        self.assertEqual(lines[0], "SUMMARY:Meeting with team and client")
        self.assertEqual(lines[1], "DESCRIPTION:Hello")

    def test_unescape_ics_text(self):
        escaped = r"Hello\, World\; Line 1\nLine 2\\Backslash\NLine 3"
        unescaped = gcal.unescape_ics_text(escaped)
        self.assertEqual(unescaped, "Hello, World; Line 1\nLine 2\\Backslash\nLine 3")

    def test_parse_ics_prop(self):
        line = 'DTSTART;TZID="America/Sao_Paulo";VALUE=DATE-TIME:20261107T100000'
        name, params, val = gcal.parse_ics_prop(line)
        self.assertEqual(name, "DTSTART")
        self.assertEqual(params.get("TZID"), "America/Sao_Paulo")
        self.assertEqual(params.get("VALUE"), "DATE-TIME")
        self.assertEqual(val, "20261107T100000")

    def test_parse_ics_duration(self):
        self.assertEqual(gcal.parse_ics_duration("PT1H"), datetime.timedelta(hours=1))
        self.assertEqual(gcal.parse_ics_duration("PT1H30M"), datetime.timedelta(hours=1, minutes=30))
        self.assertEqual(gcal.parse_ics_duration("P1D"), datetime.timedelta(days=1))
        self.assertEqual(gcal.parse_ics_duration("P2W"), datetime.timedelta(weeks=2))
        self.assertEqual(gcal.parse_ics_duration("-PT15M"), datetime.timedelta(minutes=-15))
        self.assertIsNone(gcal.parse_ics_duration("INVALID"))

    def test_parse_ics_datetime_utc(self):
        d, dt, is_date = gcal.parse_ics_datetime("20261107T130000Z", {}, self.tz)
        self.assertFalse(is_date)
        self.assertEqual(d, datetime.date(2026, 11, 7))
        # 13:00 UTC converted to UTC-3 is 10:00
        self.assertEqual(dt.hour, 10)
        self.assertEqual(dt.minute, 0)

    def test_parse_ics_datetime_date_only(self):
        d, dt, is_date = gcal.parse_ics_datetime("20261107", {"VALUE": "DATE"}, self.tz)
        self.assertTrue(is_date)
        self.assertEqual(d, datetime.date(2026, 11, 7))
        self.assertIsNone(dt)

    def test_basic_vevent(self):
        ics = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:ev-12345
DTSTART:20261107T140000Z
DTEND:20261107T150000Z
SUMMARY:Architecture Review
LOCATION:https://meet.google.com/xyz-uvwx-rst
DESCRIPTION:Reviewing calendar plugin design
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertEqual(ev["remoteId"], "ev-12345")
        self.assertEqual(ev["title"], "Architecture Review")
        # 14:00Z in UTC-3 is 11:00
        self.assertEqual(ev["startTime"], "11:00")
        self.assertEqual(ev["endTime"], "12:00")
        self.assertFalse(ev["allDay"])
        self.assertEqual(ev["meetLink"], "https://meet.google.com/xyz-uvwx-rst")

    def test_vevent_with_duration(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:ev-dur
DTSTART:20261107T100000Z
DURATION:PT45M
SUMMARY:Standup
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), datetime.timezone.utc)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["startTime"], "10:00")
        self.assertEqual(events[0]["endTime"], "10:45")

    def test_vevent_all_day_span(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:ev-allday
DTSTART;VALUE=DATE:20261110
DTEND;VALUE=DATE:20261113
SUMMARY:3-day Summit
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        self.assertEqual(len(events), 1)
        ev = events[0]
        self.assertTrue(ev["allDay"])
        self.assertEqual(ev["startDate"], "2026-11-10")
        # Exclusive end date 2026-11-13 becomes inclusive 2026-11-12
        self.assertEqual(ev["endDate"], "2026-11-12")

    def test_cancelled_vevent_skipped(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:ev-canc
STATUS:CANCELLED
DTSTART:20261107T100000Z
SUMMARY:Canceled Meeting
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        self.assertEqual(len(events), 0)

    def test_rrule_weekly_with_byday(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:rec-weekly
DTSTART:20261102T090000Z
DURATION:PT1H
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6
SUMMARY:Recurring Standup
END:VEVENT
END:VCALENDAR"""
        # Nov 2 2026 is Monday; occurrences should be Nov 2 (Mo), Nov 4 (We), Nov 6 (Fr), Nov 9 (Mo), Nov 11 (We), Nov 13 (Fr)
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), datetime.timezone.utc)
        self.assertEqual(len(events), 6)
        dates = [e["startDate"] for e in events]
        self.assertEqual(dates, ["2026-11-02", "2026-11-04", "2026-11-06", "2026-11-09", "2026-11-11", "2026-11-13"])

    def test_rrule_daily_with_byday_weekdays(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:rec-daily-weekdays
DTSTART:20261106T100000Z
RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=3
SUMMARY:Weekday Daily
END:VEVENT
END:VCALENDAR"""
        # Nov 6 is Friday. Daily with weekdays: Nov 6 (Fr), Nov 9 (Mo), Nov 10 (Tu)
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), datetime.timezone.utc)
        dates = [e["startDate"] for e in events]
        self.assertIn("2026-11-06", dates)
        self.assertIn("2026-11-09", dates)
        self.assertNotIn("2026-11-07", dates) # Saturday skipped
        self.assertNotIn("2026-11-08", dates) # Sunday skipped

    def test_rdate_support(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:rdate-ev
DTSTART;VALUE=DATE:20261105
RDATE;VALUE=DATE:20261112,20261119
SUMMARY:Explicit Recurring Dates
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        dates = sorted([e["startDate"] for e in events])
        self.assertEqual(dates, ["2026-11-05", "2026-11-12", "2026-11-19"])

    def test_exdate_exclusion(self):
        ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
UID:exdate-ev
DTSTART:20261102T090000Z
RRULE:FREQ=DAILY;COUNT=5
EXDATE:20261104T090000Z
SUMMARY:Daily with Holiday Excluded
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), datetime.timezone.utc)
        dates = [e["startDate"] for e in events]
        self.assertEqual(dates, ["2026-11-02", "2026-11-03", "2026-11-05", "2026-11-06"])
        self.assertNotIn("2026-11-04", dates)


class TestGcalBackendIntegration(unittest.TestCase):
    def setUp(self):
        self.tz = datetime.timezone(datetime.timedelta(hours=-3))
        self.temp_dir = tempfile.TemporaryDirectory()
        self.orig_config = gcal.CONFIG_DIR
        self.orig_state = gcal.STATE_DIR
        gcal.CONFIG_DIR = Path(self.temp_dir.name) / "config"
        gcal.STATE_DIR = Path(self.temp_dir.name) / "state"
        gcal.CONFIG_FILE = gcal.CONFIG_DIR / "config.json"
        gcal.LOCAL_EVENTS_FILE = gcal.STATE_DIR / "local_events.json"
        gcal.EVENTS_CACHE_FILE = gcal.STATE_DIR / "events.json"
        gcal.ensure_dirs()

    def tearDown(self):
        gcal.CONFIG_DIR = self.orig_config
        gcal.STATE_DIR = self.orig_state
        gcal.CONFIG_FILE = self.orig_config / "config.json"
        gcal.LOCAL_EVENTS_FILE = self.orig_state / "local_events.json"
        gcal.EVENTS_CACHE_FILE = self.orig_state / "events.json"
        self.temp_dir.cleanup()

    def test_add_and_list_local_event(self):
        import argparse
        args_add = argparse.Namespace(
            title="Local Testing Sync",
            date="2026-11-15",
            end_date="2026-11-15",
            start="10:00",
            end="11:30",
            all_day=False,
            location="Room B",
            description="Testing CLI add",
            color="#039be5"
        )
        ret = gcal.cmd_add(args_add)
        self.assertEqual(ret, 0)

        cache = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
        self.assertEqual(len(cache.get("events", [])), 1)
        ev = cache["events"][0]
        self.assertEqual(ev["title"], "Local Testing Sync")
        self.assertEqual(ev["startDate"], "2026-11-15")
        self.assertEqual(ev["startTime"], "10:00")
        self.assertEqual(ev["endTime"], "11:30")

        # Test deleting event
        args_del = argparse.Namespace(id=ev["id"])
        ret_del = gcal.cmd_delete(args_del)
        self.assertEqual(ret_del, 0)

        cache_after = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
        self.assertEqual(len(cache_after.get("events", [])), 0)

    def test_cmd_list_filtering(self):
        import argparse
        import io
        from contextlib import redirect_stdout, redirect_stderr

        # Add 2 events
        ev1 = argparse.Namespace(
            title="Design Review",
            date="2026-11-20",
            end_date="2026-11-20",
            start="09:00",
            end="10:00",
            all_day=False,
            location="Room 101",
            description="Discuss UI",
            color="#039be5"
        )
        ev2 = argparse.Namespace(
            title="Budget Planning",
            date="2026-11-21",
            end_date="2026-11-21",
            start="14:00",
            end="15:00",
            all_day=False,
            location="Finance Hall",
            description="Q4 budget",
            color="#039be5"
        )
        gcal.cmd_add(ev1)
        gcal.cmd_add(ev2)

        # Filter by query
        f = io.StringIO()
        with redirect_stdout(f):
            args_list = argparse.Namespace(date="", query="budget", upcoming=False, limit=50, json=True)
            ret = gcal.cmd_list(args_list)
        self.assertEqual(ret, 0)
        out = json.loads(f.getvalue())
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["title"], "Budget Planning")

        # Invalid date format error
        err_buf = io.StringIO()
        with redirect_stderr(err_buf):
            args_bad_date = argparse.Namespace(date="invalid-date", query="", upcoming=False, limit=50, json=False)
            ret_err = gcal.cmd_list(args_bad_date)
        self.assertEqual(ret_err, 1)
        self.assertIn("Error: invalid date format", err_buf.getvalue())

    def test_rdate_period_and_long_uid(self):
        long_uid = "long-uid-" + "a" * 150
        ics = f"""BEGIN:VCALENDAR
BEGIN:VEVENT
UID:{long_uid}
DTSTART:20261110T100000Z
DURATION:PT1H
SUMMARY:Master Series
RDATE:20261112T100000Z/PT1H,20261114T100000Z/20261114T110000Z
END:VEVENT
BEGIN:VEVENT
UID:{long_uid}
RECURRENCE-ID:20261112T100000Z
DTSTART:20261112T100000Z
DURATION:PT1H
SUMMARY:Overridden Master
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        # Should include start date (Nov 10), overridden Nov 12, and RDATE Nov 14
        dates = [e["startDate"] for e in events]
        self.assertIn("2026-11-10", dates)
        self.assertIn("2026-11-12", dates)
        self.assertIn("2026-11-14", dates)
        # Overridden occurrence has the new title
        nov12 = [e for e in events if e["startDate"] == "2026-11-12"][0]
        self.assertEqual(nov12["title"], "Overridden Master")

    def test_google_api_request_401_token_refresh(self):
        import io
        from unittest.mock import patch, MagicMock
        import urllib.error

        cfg = {"clientId": "client_id", "clientSecret": "secret"}
        tokens = {"access_token": "expired_tok", "refresh_token": "valid_refresh", "expires_at": 9999999999}
        gcal.atomic_write_json(gcal.TOKEN_FILE, tokens)

        # Mock urllib to return 401 on first call, 200 on second call
        attempt = [0]
        def mock_urlopen(req, timeout=12):
            attempt[0] += 1
            if attempt[0] == 1:
                fp = io.BytesIO(b'{"error": "invalid_grant"}')
                raise urllib.error.HTTPError(req.full_url, 401, "Unauthorized", {}, fp)
            resp = MagicMock()
            resp.read.return_value = b'{"items": [{"id": "ev1", "summary": "Sync Test"}]}'
            resp.__enter__.return_value = resp
            resp.__exit__.return_value = False
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_urlopen):
            with patch.object(gcal, "get_valid_access_token", return_value="refreshed_access_tok"):
                res = gcal.google_api_request(
                    "GET",
                    "https://www.googleapis.com/calendar/v3/users/me/calendarList",
                    "expired_tok",
                    cfg=cfg
                )
                self.assertIsNotNone(res)
                self.assertIn("items", res)
                self.assertEqual(attempt[0], 2)


if __name__ == "__main__":
    unittest.main()
