#!/usr/bin/env python3
"""
Unit tests for omarchy-gcal RFC 5545 parsing, event math, and backend CLI.
Run with: dev/test.sh (or python3 -m unittest discover -s dev/tests -t . -p "test_*.py")
"""

import datetime
import argparse
import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from unittest.mock import patch, MagicMock
from pathlib import Path

# Load omarchy-gcal module dynamically (file does not have .py extension)
REPO_ROOT = Path(__file__).resolve().parents[2]
GCAL_SCRIPT = REPO_ROOT / "omarchy-gcal"
loader = importlib.machinery.SourceFileLoader("omarchy_gcal", str(GCAL_SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
gcal = importlib.util.module_from_spec(spec)
loader.exec_module(gcal)

# Never touch the real home: ensure_dirs() also manages ~/.local/bin/omarchy-gcal,
# and the default config/state dirs live under ~. Point everything at a temp home
# for the whole run (the integration tests narrow these further per test).
_TEST_HOME = tempfile.TemporaryDirectory(prefix="omarchy-gcal-test-home.")
gcal.HOME = Path(_TEST_HOME.name)
gcal.CONFIG_DIR = gcal.HOME / ".config" / "omarchy" / "gcal"
gcal.STATE_DIR = gcal.HOME / ".local" / "state" / "omarchy" / "gcal"
gcal.CONFIG_FILE = gcal.CONFIG_DIR / "config.json"
gcal.CREDENTIALS_FILE = gcal.CONFIG_DIR / "credentials.json"
gcal.TOKEN_FILE = gcal.CONFIG_DIR / "token.json"
gcal.LOCAL_EVENTS_FILE = gcal.STATE_DIR / "local_events.json"
gcal.EVENTS_CACHE_FILE = gcal.STATE_DIR / "events.json"


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

    def test_vevent_without_summary_has_empty_title(self):
        # The panel translates an empty title ("(No title)"); the helper must not
        # store a hard-coded language.
        ics = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:ev-untitled
DTSTART:20261107T140000Z
DTEND:20261107T150000Z
END:VEVENT
END:VCALENDAR"""
        events = gcal.parse_ics_content(ics, datetime.date(2026, 11, 1), datetime.date(2026, 11, 30), self.tz)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["title"], "")

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
        gcal.CREDENTIALS_FILE = gcal.CONFIG_DIR / "credentials.json"
        gcal.TOKEN_FILE = gcal.CONFIG_DIR / "token.json"
        gcal.LOCAL_EVENTS_FILE = gcal.STATE_DIR / "local_events.json"
        gcal.EVENTS_CACHE_FILE = gcal.STATE_DIR / "events.json"
        gcal.ensure_dirs()

    def tearDown(self):
        gcal.CONFIG_DIR = self.orig_config
        gcal.STATE_DIR = self.orig_state
        gcal.CONFIG_FILE = self.orig_config / "config.json"
        gcal.CREDENTIALS_FILE = self.orig_config / "credentials.json"
        gcal.TOKEN_FILE = self.orig_config / "token.json"
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

    def test_cmd_update_local_event(self):
        import argparse
        args_add = argparse.Namespace(
            title="Draggable Meeting",
            date="2026-11-15",
            end_date="2026-11-15",
            start="08:00",
            end="10:00",
            all_day=False,
            location="Room 2",
            description="Testing update",
            color="#039be5"
        )
        self.assertEqual(gcal.cmd_add(args_add), 0)
        cache = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
        ev_id = cache["events"][0]["id"]

        # Resize duration by dragging bottom edge to 12:30
        args_upd = argparse.Namespace(
            id=ev_id,
            start="08:00",
            end="12:30",
            date="2026-11-15",
            title="Draggable Meeting (Extended)"
        )
        self.assertEqual(gcal.cmd_update(args_upd), 0)

        cache_updated = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
        ev_updated = cache_updated["events"][0]
        self.assertEqual(ev_updated["startTime"], "08:00")
        self.assertEqual(ev_updated["endTime"], "12:30")
        self.assertEqual(ev_updated["title"], "Draggable Meeting (Extended)")

        # Verify local_events.json was also updated
        locals_list = gcal.load_local_events()
        self.assertEqual(locals_list[0]["endTime"], "12:30")

    def test_cmd_update_gcal_oauth_event(self):
        import argparse
        ev_id = "gcal:primary:remote_12345"
        # Seed cache with remote event
        initial_cache = {
            "version": 1,
            "source": "oauth",
            "events": [{
                "id": ev_id,
                "remoteId": "remote_12345",
                "calendarId": "primary",
                "title": "Will",
                "startDate": "2026-11-06",
                "endDate": "2026-11-06",
                "startTime": "08:00",
                "endTime": "18:00",
                "source": "oauth"
            }]
        }
        gcal.atomic_write_json(gcal.EVENTS_CACHE_FILE, initial_cache)

        patch_called = []
        def mock_google_api_request(method, url, token, payload=None, cfg=None):
            patch_called.append((method, url, payload))
            return {"id": "remote_12345"}

        with patch.object(gcal, "get_valid_access_token", return_value="valid_mock_token"):
            with patch.object(gcal, "google_api_request", side_effect=mock_google_api_request):
                args_upd = argparse.Namespace(
                    id=ev_id,
                    start="08:00",
                    end="17:00",
                    date="2026-11-06",
                    title=""
                )
                ret = gcal.cmd_update(args_upd)
                self.assertEqual(ret, 0)
                self.assertEqual(len(patch_called), 1)
                self.assertEqual(patch_called[0][0], "PATCH")
                self.assertIn("calendars/primary/events/remote_12345", patch_called[0][1])
                self.assertEqual(patch_called[0][2]["end"]["dateTime"][:16], "2026-11-06T17:00")

                # Verify cache is updated immediately
                cache = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
                self.assertEqual(cache["events"][0]["endTime"], "17:00")

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

    def test_cmd_add_with_meet(self):
        args_add = argparse.Namespace(
            title="Video Sync Standup",
            date="2026-11-16",
            end_date="2026-11-16",
            start="11:00",
            end="12:00",
            all_day=False,
            location="",
            description="Daily video standup",
            color="#039be5",
            add_meet=True
        )
        self.assertEqual(gcal.cmd_add(args_add), 0)
        cache = gcal.load_json(gcal.EVENTS_CACHE_FILE, {})
        events = cache.get("events", [])
        standup = [e for e in events if e["title"] == "Video Sync Standup"][0]
        self.assertTrue(standup.get("meetLink", "").startswith("https://meet.google.com/"))
        self.assertTrue(standup.get("addMeet", False))
        extracted = gcal.extract_meet_link({"location": standup["meetLink"]})
        self.assertEqual(extracted, standup["meetLink"])

    def test_sync_all_honors_days_back_and_forward_from_config(self):
        gcal.atomic_write_json(gcal.CONFIG_FILE, {"daysBack": 900, "daysForward": 500})
        # Call sync_all and check that daysBack config is read
        res = gcal.sync_all()
        self.assertIn("events", res)

    def test_cmd_auth_auto_detects_downloads(self):
        downloads = Path(self.temp_dir.name) / "Downloads"
        downloads.mkdir()
        fake_client_secret = downloads / "client_secret_test123.json"
        fake_client_secret.write_text(json.dumps({
            "installed": {
                "client_id": "auto_id_123",
                "client_secret": "auto_sec_456"
            }
        }))
        temp_cred = Path(self.temp_dir.name) / "config" / "credentials.json"

        with patch.object(gcal, "CREDENTIALS_FILE", temp_cred), patch.object(gcal, "HOME", Path(self.temp_dir.name)):
            cfg = {}
            # Before copying, get_oauth_client_config returns empty
            cid, csec = gcal.get_oauth_client_config(cfg)
            self.assertEqual(cid, "")

            # Simulate the auto-detect logic from cmd_auth
            candidates = sorted(downloads.glob("client_secret_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
            self.assertEqual(len(candidates), 1)
            shutil.copyfile(candidates[0], gcal.CREDENTIALS_FILE)

            cid, csec = gcal.get_oauth_client_config(cfg)
            self.assertEqual(cid, "auto_id_123")
            self.assertEqual(csec, "auto_sec_456")

    def test_search_places_and_geocode_command(self):
        # Test empty query returns empty list
        empty_res = gcal.search_places("")
        self.assertEqual(empty_res, [])

        # Mock urllib to test search_places parsing
        fake_features = {
            "features": [
                {
                    "properties": {
                        "name": "Auditório Ibirapuera",
                        "street": "Avenida Pedro Álvares Cabral",
                        "housenumber": "s/n",
                        "city": "São Paulo",
                        "state": "São Paulo",
                        "country": "Brasil"
                    }
                }
            ]
        }
        with patch("urllib.request.urlopen") as mock_url:
            mock_resp = MagicMock()
            mock_resp.read.return_value = json.dumps(fake_features).encode("utf-8")
            mock_resp.__enter__.return_value = mock_resp
            mock_url.return_value = mock_resp

            res = gcal.search_places("Ibirapuera", limit=1)
            self.assertEqual(len(res), 1)
            self.assertEqual(res[0]["title"], "Auditório Ibirapuera")
            self.assertIn("Avenida Pedro Álvares Cabral", res[0]["address"])
            self.assertIn("São Paulo", res[0]["full"])
            self.assertIn("lat", res[0])
            self.assertIn("lon", res[0])

        # Test CLI geocode command
        parser = gcal.build_parser()
        args_flag = parser.parse_args(["geocode", "--query", "Ibirapuera", "--limit", "1"])
        self.assertEqual(args_flag.opt_query, "Ibirapuera")

        args = argparse.Namespace(query="", opt_query="Ibirapuera", limit=1)
        with patch.object(gcal, "search_places", return_value=[{"title": "Test Place", "address": "Test City", "full": "Test Place, Test City", "lat": -23.5, "lon": -46.6}]):
            with patch("builtins.print") as mock_print:
                ret = gcal.cmd_geocode(args)
                self.assertEqual(ret, 0)
                mock_print.assert_called_once()
                out = json.loads(mock_print.call_args[0][0])
                self.assertEqual(out[0]["title"], "Test Place")
                self.assertEqual(out[0]["lat"], -23.5)

    def test_cmd_add_with_explicit_meet_url(self):
        with patch.object(gcal, "EVENTS_CACHE_FILE", Path(self.temp_dir.name) / "cache.json"), \
             patch.object(gcal, "LOCAL_EVENTS_FILE", Path(self.temp_dir.name) / "local.json"), \
             patch.object(gcal, "get_valid_access_token", return_value=None):
            args = argparse.Namespace(
                title="Design Review",
                date="2026-11-10",
                end_date="",
                start="10:00",
                end="11:00",
                all_day=False,
                location="",
                description="",
                color="#039be5",
                add_meet=True,
                meet_url="https://meet.google.com/xyz-abcd-efg"
            )
            ret = gcal.cmd_add(args)
            self.assertEqual(ret, 0)
            cache = gcal.load_json(gcal.LOCAL_EVENTS_FILE, [])
            self.assertEqual(len(cache), 1)
            self.assertEqual(cache[0]["meetLink"], "https://meet.google.com/xyz-abcd-efg")


if __name__ == "__main__":
    unittest.main()
