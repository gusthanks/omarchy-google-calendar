# 📅 Omarchy Google Calendar Plugin

<p align="center">
  <b>Seamless Google Calendar synchronization & multi-view agenda (Day, Week, Month, Year) for Omarchy Linux.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Omarchy-Shell%20Plugin-blue?style=flat-square" alt="Omarchy Plugin" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License" />
  <img src="https://img.shields.io/badge/Python-3%20Stdlib%20(Zero%20pip)-yellow?style=flat-square" alt="Python Zero Dependencies" />
</p>

---

## 📸 Screenshots

<p align="center">
  <b>Month View (Mês)</b><br>
  <i>Classic month grid with event indicators, selected day agenda, and sync toolbar</i><br>
  <img src="assets/view-month.png" alt="Month View" width="85%" />
</p>

<p align="center">
  <b>Week View (Semana)</b><br>
  <i>7-day continuous grid with proportional event blocks and live current time indicator</i><br>
  <img src="assets/view-week.png" alt="Week View" width="85%" />
</p>

<p align="center">
  <b>Day View (Dia)</b><br>
  <i>Continuous 24h timeline schedule with proportional event blocks, current time line, and drag-to-resize handles</i><br>
  <img src="assets/view-day.png" alt="Day View" width="85%" />
</p>

<p align="center">
  <b>Year View (Ano)</b><br>
  <i>12-month bird's-eye overview showing annual event density</i><br>
  <img src="assets/view-year.png" alt="Year View" width="85%" />
</p>

---

## ✨ Features

- 🔄 **Two Sync Methods:**
  - **Quick iCal (.ics) Link:** Connect in 30 seconds with your Google Calendar secret iCal address (no OAuth or cloud setup needed).
  - **Google Cloud OAuth2:** Full two-way sync (create, edit, and delete events directly from Omarchy).
- 🗓️ **4 Rich View Modes:**
  - **Day:** Continuous 24h timeline with proportional duration blocks, live "Now" indicator, and drag-to-resize handles on event borders.
  - **Week:** 7-day continuous grid with proportional event blocks placed in their correct hourly positions.
  - **Month:** Classic Omarchy calendar grid enriched with event badges, dots, and selected day agenda.
  - **Year:** 12-month bird's-eye view showing annual event distribution and counters.
- 🎯 **Drag & Double-Click Creation:** Click and drag directly on any time slot in Day or Week view to draw an event with 15-minute snap, opening the quick options drawer upon release. Double-click anywhere to instantly create a 1-hour slot.
- 🎛️ **Segmented Capsule & Action Toolbar:** Clean segmented control (`Day | Week | Month | Year`) separated from standardized actions (`Today`, `+ Event`, `Sync`, `Search`, `Settings`).
- ↔️ **Drag-to-Resize Events:** Drag the top or bottom edges of any event card to adjust start time or duration directly with live 15-minute feedback.
- ⚡ **Instant Event Creation:** Fast inline `+ Event` drawer with keyboard focus (`N` or `+`). Works even offline as a local agenda!
- 🔍 **Real-Time Event Search:** Press `/` or click search to instantly filter upcoming and historical events across all your calendars.
- 🔔 **Desktop & Bar Notifications:** Native desktop reminder notification 10 minutes before your meetings, plus live upcoming indicator directly beside the clock.
- ⌨️ **Keyboard & Vim Driven:** Full keyboard navigation (`1`–`4`, `[` / `]`, Vim `h`/`j`/`k`/`l`, `T`, `N`, `R`, `S`, `Esc`).
- 🖱️ **Interactive Event Cards:** Single click to open Google Meet/Zoom links directly; double click to inspect the day's full agenda.
- ⏳ **Memento Mori:** Retains Omarchy's beloved year progress bar and life expectancy counter.
- 🌍 **Bilingual:** Native Portuguese (`pt-BR`) and English (`en`) support, following your Omarchy system language live.
- 🪶 **Zero External Dependencies:** Sync engine runs on pure Python 3 standard library (`urllib`, `sqlite3`, `json`).

---

## 🚀 Installation

Run this single command in your terminal:

```bash
omarchy plugin add https://github.com/gusthanks/omarchy-google-calendar.git --enable
```

> **Note:** If prompted for bar placement, select `center` (or `centerEnd`) to place it in your top bar.

---

## ⚙️ How to Connect Google Calendar

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
9. The browser will confirm: *"Google Calendar conectado ao Omarchy!"*.

🎉 You're all set! Tokens will now renew automatically in the background.

---

> 📖 **Guia em Português:** Para instruções detalhadas passo a passo em português, consulte o [docs/GUIA_DE_SINCRONIZACAO.md](docs/GUIA_DE_SINCRONIZACAO.md).

---

## ⌨️ Keyboard Shortcuts

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

---

## 🛠️ CLI Utilities

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

---

## 📄 License

[MIT](LICENSE) © 2026 Gustavo Costa
