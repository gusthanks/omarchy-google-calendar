#!/usr/bin/env python3
"""Write a mock events cache (the file omarchy-gcal sync produces) for the dev harness.

Every event is made up and placed relative to TODAY (default: the real date),
so the Day / Week / Month / Year captures always have something to show. Usage:

    dev/mock/events.py OUT.json [YYYY-MM-DD]
"""

import datetime
import json
import sys

COLORS = ["#039be5", "#33b679", "#8e24aa", "#f6bf26", "#e67c73", "#7986cb", "#f4511e", "#0b8043"]


def main() -> int:
    out = sys.argv[1]
    today = datetime.date.fromisoformat(sys.argv[2]) if len(sys.argv) > 2 else datetime.date.today()
    monday = today - datetime.timedelta(days=today.weekday())
    events = []

    def add(day, title, start=None, end=None, color=0, **extra):
        ev = {
            "id": f"mock-{len(events)}",
            "title": title,
            "startDate": day.isoformat(),
            "endDate": extra.pop("endDate", day).isoformat(),
            "allDay": start is None,
            "startTime": start or "",
            "endTime": end or "",
            "color": COLORS[color % len(COLORS)],
            "calendarName": "Work" if color % 2 == 0 else "Personal",
            "source": "ics",
        }
        ev.update(extra)
        events.append(ev)

    # Today: a realistic, busy day.
    add(today, "Sprint 42", color=5)
    add(today, "Daily standup", "09:00", "09:30", 0, meetLink="https://meet.google.com/abc-defg-hij")
    add(today, "Design review", "10:30", "12:00", 2, location="Studio 2")
    add(today, "Lunch with Ana", "12:30", "13:30", 1, location="Café Central")
    add(today, "1:1 with Rafa", "15:00", "15:45", 4, meetLink="https://meet.google.com/xyz-abcd-efg")
    add(today, "Gym", "18:30", "19:30", 3)

    # The rest of this week.
    week = [
        (0, "Planning", "10:00", "11:00", 0), (0, "Dentist", "16:00", "17:00", 1),
        (1, "Customer call", "09:30", "10:15", 4), (1, "Code review", "14:00", "15:00", 2),
        (2, "Workshop: QML", "13:00", "16:00", 7), (3, "Retro", "11:00", "12:00", 6),
        (3, "Guitar lesson", "19:00", "20:00", 3), (4, "Demo day", "15:00", "16:30", 2),
        (5, "Farmers market", "08:30", "10:00", 1), (6, "Family lunch", "12:00", "14:00", 3),
    ]
    for offset, title, start, end, color in week:
        day = monday + datetime.timedelta(days=offset)
        if day != today:
            add(day, title, start, end, color)

    # Scattered over the year (the year view shows density), skipping this week.
    titles = ["Team sync", "Doctor", "Book club", "Release", "Birthday", "Trip planning", "Conference", "Haircut"]
    year_start = datetime.date(today.year, 1, 1)
    for i in range(0, 365, 3):
        day = year_start + datetime.timedelta(days=i + (i * 7) % 3)
        if day.year != today.year or monday <= day < monday + datetime.timedelta(days=7):
            continue
        n = (i // 3) % len(titles)
        hour = 8 + (i * 5) % 10
        add(day, titles[n], f"{hour:02d}:00", f"{hour + 1:02d}:00", n)
        if i % 9 == 0:
            add(day, titles[(n + 3) % len(titles)], f"{hour + 2:02d}:30", f"{hour + 3:02d}:30", n + 3)

    now = datetime.datetime.now().astimezone()
    payload = {
        "version": 1,
        "syncedAt": now.isoformat(timespec="seconds"),
        "syncedAtShort": now.strftime("%H:%M"),
        "source": "ics",
        "connected": True,
        "icsUrl": "https://calendar.google.com/calendar/ical/example/private-mock/basic.ics",
        "icsUrls": [],
        "hasOAuthCredentials": False,
        "hasOAuthToken": False,
        "lastError": "",
        "events": events,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
