# Google Calendar for Omarchy

A bar clock for [Omarchy](https://omarchy.org) whose popup is a full agenda: Day, Week,
Month and Year views of your Google Calendar, with event creation, drag to reschedule,
search, Meet links and a reminder before each meeting. It replaces (and is a clone of)
the stock clock, so it sits in the same place and keeps the year and life progress bars.

<p align="center">
  <img src="docs/view-month.png" alt="Month view" width="49%" />
  <img src="docs/view-week.png" alt="Week view" width="49%" />
</p>
<p align="center">
  <img src="docs/view-day.png" alt="Day view" width="49%" />
  <img src="docs/view-year.png" alt="Year view" width="49%" />
</p>
<p align="center">
  <img src="docs/bar.png" alt="Bar widget with the next event" width="60%" />
</p>

*All screenshots are rendered by the dev harness from made-up events (see Development).*

## Features

- **Two ways to sync:** a secret iCal (.ics) address (read-only, 30 seconds to set up) or
  Google OAuth2 (two-way: events you create, move or delete in Omarchy go to Google).
  Without either, it works as a local agenda.
- **Four views:** Day and Week on a proportional time grid with a "now" line, Month with
  event dots and the selected day's agenda, Year with event density per day.
- **Create and edit in place:** drag on the Day or Week grid (15-minute snap) or press `N`;
  drag an event's edges to change its time, drag it to another day to move it. Optional
  Google Meet link, location suggestions with a map preview, description.
- **Search** (`/`) across all synced events.
- **Reminders:** a desktop notification a few minutes before each meeting (with a button
  that opens the Meet link), and optionally the next event next to the clock.
- **Keyboard driven**, follows the Omarchy theme and language (English, Portuguese).
- **No dependencies to install:** the sync helper (`omarchy-gcal`) is plain Python 3
  standard library.

<p align="center">
  <img src="docs/new-event.png" alt="New event drawer" width="49%" />
  <img src="docs/settings.png" alt="Sync settings" width="49%" />
</p>

## Install

```bash
omarchy plugin add https://github.com/gusthanks/omarchy-google-calendar.git --enable
```

When asked where to place it in the bar, pick `center` (next to, or instead of, the stock
clock). Then click the clock and press `S` to connect your calendar.

## Connect Google Calendar

The plugin supports two flexible synchronization methods depending on your needs.

### ⚖️ Comparison: Which method should you choose?

| Feature | Option 1: Secret iCal URL (.ics) | Option 2: Google Cloud OAuth2 |
|---|---|---|
| **Setup Time** | ⚡ **~30 seconds** | 🛠️ **~3–5 minutes** (one-time setup) |
| **Sync Direction** | 📥 **One-way** (Google ➔ Omarchy) | 🔄 **Two-way** (Google ⇄ Omarchy) |
| **Event Creation** | Saved locally in Omarchy | Pushed to Google Cloud / Mobile app |
| **Google Cloud Project** | ❌ None required | ✅ Free Google Cloud Desktop App |
| **Expiration** | 🔒 Never (permanent secret link) | 🔄 Automatic background token refresh |
| **Best For** | Instant setup, viewing agenda & alerts | Full calendar control & bidirectional sync |

---

### Option 1: Secret iCal URL (Fastest — 30 seconds, Read-Only)

Ideal if you only want to view your agenda, see your upcoming meetings, and receive native desktop notifications.

1. Open [Google Calendar (Web)](https://calendar.google.com/) in your browser.
2. In the left sidebar under **"My calendars"**, hover over your main calendar and click the three dots `⋮` > **Settings and sharing**.
3. Scroll down to the **"Integrate calendar"** section.
4. Locate the field **"Secret address in iCal format"** and copy the URL (`https://calendar.google.com/calendar/ical/.../basic.ics`).
   > ⚠️ **Important:** Copy the **Secret address**, not the public address. The secret address allows Omarchy to read your private events without publishing them to the web.
5. Click the clock on your Omarchy top bar to open the calendar.
6. Press `S` (or click the gear icon `󰒓`), paste the URL into the **iCal (.ics) URL** field, and click **Save & Sync** (or press Enter).

---

### Option 2: Google Cloud OAuth2 (Two-Way Sync — Read & Write)

Ideal if you want events created inside Omarchy (via `+ Event`, pressing `N`, or `omarchy-gcal add`) to sync straight to Google Calendar servers, making them instantly visible on your phone and Google Calendar web.

#### 1. Create a Free Project in Google Cloud
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Click the project dropdown at the top and select **"New Project"** (or open [projectcreate](https://console.cloud.google.com/projectcreate) directly).
3. Set **Project name** to `Omarchy Calendar`.
4. Leave **Organization** as **"No organization"** (default for personal `@gmail.com` accounts).
5. Click **Create** and ensure this new project is selected in the top bar.

#### 2. Enable the Google Calendar API
1. In the navigation menu, go to **APIs & Services > Library** (or go directly to the [Calendar API page](https://console.cloud.google.com/marketplace/product/google/calendar-json.googleapis.com)).
2. Click **Enable**.

#### 3. Configure the Google Auth Platform / OAuth Consent Screen
Google recently updated the console to the new **Google Auth Platform**:

1. In the left sidebar, click **Google Auth Platform** (or **OAuth consent screen**).
2. **App Information:** Enter `Omarchy Calendar` for the App name, and select your email for both support and developer contact. Click **Next** / **Save and Continue**.
3. **Audience:** Select **External** (standard for personal `@gmail.com` accounts) and click **Next**.
4. **Test Users:** Under the **Audience** menu (or Test users step), click **+ Add users**, enter your Google email address, and save. *(Required so your account has permission to log in while in testing mode)*.
5. **Data Access:** Add `.../auth/calendar` if prompted for scopes.

#### 4. Create OAuth Client Credentials
1. In the left sidebar, click **Clients** (or **Credentials > Create Credentials > OAuth client ID**).
2. Click **+ Create Client**.
3. For **Application type**, choose **Desktop app**.
4. Set the name to `Omarchy Shell`.
5. Leave *"Use this client for an AI-powered agent"* **unchecked**.
6. Click **Create**.
7. In the confirmation dialog, click **Download JSON** (⬇️). This saves `client_secret_*.json` into your `~/Downloads` folder.

#### 5. Authenticate in Omarchy (1 single command)
Open your terminal and simply run:

```bash
omarchy-gcal auth
```

> ⚡ **Auto-Discovery:** `omarchy-gcal` automatically detects the newly downloaded `client_secret_*.json` in your `~/Downloads` folder! You don't need to rename or copy anything manually.
>
> *(Alternatively, pass a specific path: `omarchy-gcal auth --credentials-file ~/Downloads/client_secret_*.json`).*

6. A browser tab will open automatically. Sign in with your Google account.
7. If you see an *"Unverified app"* warning screen, click **Advanced > Go to Omarchy Calendar (unsafe)** (this is normal for self-created personal test apps).
8. Grant calendar access permissions and click **Continue**.
9. The browser confirms: *"Google Calendar is connected to Omarchy."*

🎉 You're all set! Tokens will now renew automatically in the background.

> Guia em português: [docs/GUIA_DE_SINCRONIZACAO.md](docs/GUIA_DE_SINCRONIZACAO.md).

## Keyboard shortcuts

| Shortcut | Description |
|---|---|
| `1`, `2`, `3`, `4` | Switch to **Day**, **Week**, **Month**, **Year** view |
| `[` / `]` or `h` / `l` | Move backward / forward in time (by day, week, month, or year) |
| `k` / `j` | Vertical step (move by week or year matching Up/Down arrows) |
| `/` | Open **Search events** drawer to live-filter agenda |
| `T` | Jump back to **Today** |
| `N` or `+` | Open **+ Event** quick creation drawer |
| `R` | Force immediate refresh / synchronization |
| `S` | Toggle Google Calendar sync settings drawer |
| `W` | Toggle week start day (Monday / Sunday) in Month view |
| `Esc` | Close active drawer or calendar panel |

## Command line

The backend engine can also be queried directly from your shell or scripts:

```bash
# Check sync status and event count
omarchy-gcal status

# List upcoming events or filter by date
omarchy-gcal list --upcoming
omarchy-gcal list --date today
omarchy-gcal list --date tomorrow

# Search events by keyword
omarchy-gcal list -q "Standup"

# Force sync
omarchy-gcal sync

# Add an event from command line
omarchy-gcal add --title "Team Meeting" --date 2026-11-10 --start 14:00 --end 15:00 --location "Google Meet"
```

## Configuration

The widget reads these optional keys from its entry in the bar layout
(`~/.config/omarchy/shell.json`, the same place as the stock clock's settings):

| Key | Default | What it does |
|---|---|---|
| `format` / `formatAlt` | `dddd dd MMM h:mm AP` / `d MMMM 'W'ww yyyy` | Clock formats (right-click cycles through presets) |
| `verticalFormat` / `verticalFormatAlt` | `HH\n—\nmm` / … | Formats for a vertical bar |
| `defaultViewMode` | `month` | `day`, `week`, `month` or `year` |
| `weekStartDay` | your locale | `monday`, `sunday`, … (`W` toggles it) |
| `autoSync` | `true` | Sync in the background |
| `syncIntervalMinutes` | `10` | How often |
| `showBarEventBadge` | `false` | Show the next event next to the clock |
| `notificationsEnabled` | `true` | Reminder notifications |
| `notifyBeforeMinutes` | `10` | How long before a meeting |
| `birthYear`, `lifeExpectancy` | unset, `90` | The LIFE progress bar (also editable in the panel) |
| `gcalBinPath` | the bundled `omarchy-gcal` | Use another helper binary |

The helper keeps its own settings in `~/.config/omarchy/gcal/config.json` (iCal
addresses, OAuth client) and its cache in `~/.local/state/omarchy/gcal/`.
`OMARCHY_GCAL_CONFIG_DIR` and `OMARCHY_GCAL_STATE_DIR` move them.

## Privacy

Everything stays on your machine except the requests below; there is no telemetry.

**What it stores** (files are created `0600`, folders `0700`):
- `~/.config/omarchy/gcal/config.json`: your secret iCal address(es) and, if you paste
  them, your OAuth client ID and secret.
- `~/.config/omarchy/gcal/credentials.json` and `token.json`: the OAuth client file and
  the access/refresh token.
- `~/.local/state/omarchy/gcal/events.json`: the synced events (about two years back and
  one forward), read by the bar widget; `local_events.json`: events created offline.
- `~/.local/bin/omarchy-gcal`: a symlink to the helper so you can use it in a terminal.
  It is only created when nothing is there.

**What it reads:** besides the files above, `omarchy-gcal auth` looks in `~/Downloads`
for a `client_secret_*.json` file (the one Google Cloud just gave you) and copies the
newest one to `credentials.json`.

**Hosts it contacts:**
- `www.googleapis.com` and `oauth2.googleapis.com`: the Calendar API and token refresh
  (OAuth2 mode only). Sign-in opens `accounts.google.com` in your browser, with a
  one-time callback on `127.0.0.1`.
- The iCal address(es) you configured (usually `calendar.google.com`), over HTTPS only.
- `photon.komoot.io`, then `nominatim.openstreetmap.org` as a fallback: the text you type
  in an event's **location** field, for address suggestions (only while you type there).
- `basemaps.cartocdn.com`: map tiles for the small map shown after picking a suggested
  location.
- Links you click (Meet, Google Maps, the event on Google Calendar) open in your browser.

The secret iCal address is never printed: `omarchy-gcal status` and sync errors show
only its host.


## Development

Never develop on the installed copy (`~/.config/omarchy/plugins/gusthx.clock`): saving
there hot-reloads your bar. Work in a clone and use the isolated harness in `dev/`. It
runs its own Quickshell instance with Omarchy's `Commons`/`Ui` libraries, made-up events
and a stub helper, so it never touches your bar, calendar, tokens or config.

```bash
dev/run.sh check      # compile every QML type (Panel and BarWidget included)
dev/run.sh docs       # render all screenshots in docs/ (offscreen, nothing on screen)
dev/run.sh panel week # just one view
dev/run.sh preview    # a window with the panel, to click around in
dev/test.sh           # unit tests: helper (Python) and Model.js (node)
omarchy plugin validate .
```

When everything is committed, install it once and restart the shell once:

```bash
dev/deploy.sh   # validates, checks, tests, updates the installed plugin, restarts the shell
```

If the installed plugin is a plain copy, `deploy.sh` backs it up to
`~/Work/backups/gusthx.clock.<timestamp>` and replaces it with a git checkout of this repo.
See [AGENTS.md](AGENTS.md) for the rules AI agents follow here.

## License

[MIT](LICENSE) © 2026 Gustavo Costa
