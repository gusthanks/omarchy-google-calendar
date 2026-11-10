# Google Calendar sync guide

**🇺🇸 English** · [🇧🇷 Português (Brasil)](sync-guide.pt-BR.md)

This guide covers the **two ways** to connect your Google Calendar account to the
Calendar for Google plugin for Omarchy, how they differ, and every step of each.

This plugin is not affiliated with Google. Google Calendar is a trademark of Google LLC.

---

## Which method should you choose?

| | Option 1: secret iCal address (.ics) | Option 2: Google Cloud OAuth2 |
|---|---|---|
| **Setup time** | **~30 seconds** | **~3–5 minutes** (once) |
| **Sync direction** | **One-way** (Google ➔ Omarchy) | **Two-way** (Google ⇄ Omarchy) |
| **New events** | Saved locally in Omarchy | Sent to Google (phone, web) |
| **Google Cloud project** | None | A free one, created by you |
| **Expiration** | Never (private link) | Tokens refresh automatically |
| **Best for** | Seeing your agenda and getting reminders | Full control (create, move, delete events) |

---

## Option 1: secret iCal address (fastest, read-only)

Ideal if you only want to see your agenda, your next meetings and desktop reminders.

1. Open [Google Calendar on the web](https://calendar.google.com/).
2. In the left sidebar, under **"My calendars"**, hover over your main calendar and click
   the three dots `⋮` > **Settings and sharing**.
3. Scroll down to **"Integrate calendar"**.
4. Copy **"Secret address in iCal format"** (it looks like
   `https://calendar.google.com/calendar/ical/.../basic.ics`).
   > **Important:** copy the **secret** address, not the public one. The secret address
   > lets the plugin read your private events without publishing them. Do not share it.
5. In Omarchy, click the clock in the bar to open the calendar.
6. Press `S` (or click the gear icon at the top of the panel).
7. Paste the address into **"Google Calendar secret iCal (.ics) URL"** and click
   **Save & Sync** (or press Enter).

Your events show up in the Day, Week, Month and Year views within seconds.

From a terminal, the same thing: `omarchy-gcal set-ics 'https://calendar.google.com/calendar/ical/.../basic.ics'`.

---

## Option 2: Google Cloud OAuth2 (two-way)

Ideal if you want events created in Omarchy (with `+ Event`, the `N` key or
`omarchy-gcal add`) to be saved to Google and show up on your phone and on the web.

### Step 1: create a Google Cloud project (free)
1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and sign in.
2. Click the project picker at the top, then **"New project"** (or open
   [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate)).
3. Fill in:
   - **Project name:** `Omarchy Calendar` (any name works)
   - **Organization:** leave **"No organization"**, the default for personal
     `@gmail.com` accounts.
4. Click **Create** and make sure the new project is selected at the top of the page.

### Step 2: enable the Google Calendar API
1. In the menu (or the search bar), go to **APIs & Services > Library** (or open the
   [Calendar API page](https://console.cloud.google.com/marketplace/product/google/calendar-json.googleapis.com)).
2. Click **Enable**.

### Step 3: set up the Google Auth Platform (consent screen)
1. In the left sidebar, click **Google Auth Platform** (or **OAuth consent screen**).
2. **App information:**
   - **App name:** `Omarchy Calendar`
   - **User support email** and **developer contact:** your own email.
   - Click **Next** / **Save and continue**.
3. **Audience:** choose **External** (personal `@gmail.com` accounts use External) and
   continue.
4. **Test users:** under **Audience**, in **"Test users"**, click **+ Add users**, enter
   your Google email and save. *(Required: while the app is in testing mode, only test
   users can sign in.)*
5. **Data access / scopes:** if asked, add `.../auth/calendar`.

### Step 4: create the OAuth client
1. In the left sidebar, click **Clients** (or **Credentials**).
2. Click **+ Create Client** (or **+ Create credentials > OAuth client ID**).
3. **Application type:** **Desktop app**.
4. **Name:** `Omarchy Shell`.
5. If you see *"Use this client for an AI-powered agent"*, leave it **unchecked**.
6. Click **Create**.
7. In the dialog that follows, click **Download JSON**. The file `client_secret_...json`
   lands in `~/Downloads`.

### Step 5: connect it to Omarchy (one command)
With the file in `~/Downloads`, open a terminal and run:

```bash
omarchy-gcal auth
```

`omarchy-gcal` finds the newest `client_secret_*.json` in `~/Downloads` and copies it to
`~/.config/omarchy/gcal/credentials.json`, so there is nothing to rename. To point at the
file yourself:

```bash
omarchy-gcal auth --credentials-file ~/Downloads/client_secret_XXXX.json
```

> **From the panel instead:** copy the file to `~/.config/omarchy/gcal/credentials.json`:
> ```bash
> mkdir -p ~/.config/omarchy/gcal
> cp ~/Downloads/client_secret_*.json ~/.config/omarchy/gcal/credentials.json
> ```
> Then open the calendar, press `S` and click **Launch OAuth2 Setup**.

### Step 6: authorize in the browser
1. A browser tab opens. Pick your Google account.
2. If you see *"Google hasn't verified this app"*, click **Advanced > Go to Omarchy
   Calendar (unsafe)**. That is expected: the app is yours, in testing mode.
3. Allow access to see and edit your calendar and click **Continue**.
4. The browser shows *"Google Calendar is connected to Omarchy."*

Done. Tokens refresh automatically in the background.

---

## Useful commands

```bash
# Connection status and event count
omarchy-gcal status

# Sync now
omarchy-gcal sync

# Upcoming events, or one day's
omarchy-gcal list --upcoming
omarchy-gcal list --date today

# Search events by keyword
omarchy-gcal list -q "Standup"

# Create an event from the terminal (with OAuth2 it goes to Google)
omarchy-gcal add --title "Team meeting" --date 2026-11-10 --start 14:00 --end 15:00 --location "Google Meet"
```
