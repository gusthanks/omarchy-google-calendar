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

## ✨ Features

- 🔄 **Two Sync Methods:**
  - **Quick iCal (.ics) Link:** Connect in 30 seconds with your Google Calendar secret iCal address (no OAuth or setup needed).
  - **Google Cloud OAuth2:** Full two-way sync (create, edit, and delete events directly from Omarchy).
- 🗓️ **4 Rich View Modes:**
  - **Day:** Hour-by-hour timeline with current time indicator and event cards.
  - **Week:** 7-day columns side-by-side with scheduled events.
  - **Month:** Classic Omarchy calendar grid enriched with event badges and selected day agenda.
  - **Year:** 12-month bird's-eye view showing annual event distribution.
- ⚡ **Instant Event Creation:** Fast inline `+ Event` drawer with keyboard focus (`N` or `+`). Works even offline as a local agenda!
- 🔔 **Top Bar Indicator:** Displays your upcoming meeting time and title directly beside the clock when an event is approaching.
- ⌨️ **Keyboard Driven:** Full keyboard navigation (`1`–`4`, `[` / `]`, `T`, `N`, `R`, `S`, `Esc`).
- ⏳ **Memento Mori:** Retains Omarchy's beloved year progress bar and life expectancy counter.
- 🌍 **Bilingual:** Native Portuguese (`pt-BR`) and English (`en`) support, following your Omarchy system language live.
- 🪶 **Zero External Dependencies:** Sync engine runs on pure Python 3 standard library (`urllib`, `sqlite3`, `json`).

---

## 🚀 Installation

Run this single command in your terminal:

```bash
omarchy plugin add https://github.com/gusthx/omarchy-google-calendar.git --enable
```

> **Note:** If prompted for bar placement, select `center` (or `centerEnd`) to place it in your top bar.

---

## ⚙️ How to Connect Google Calendar

### Option 1: Secret iCal URL (Fastest — 30 seconds)
1. Open [Google Calendar](https://calendar.google.com).
2. On the left sidebar, click the three dots `⋮` next to your calendar > **Settings and sharing**.
3. Scroll down to **"Integrate calendar"** and copy the **"Secret address in iCal format"** (`https://.../basic.ics`).
4. Click the clock on your top bar to open the calendar.
5. Press `S` (or click the gear icon `󰒓`), paste the URL, and click **Save & Sync**.

### Option 2: Google Cloud OAuth2 (Two-Way Sync)
1. Create a Desktop OAuth credential in the [Google Cloud Console](https://console.cloud.google.com/apis/credentials).
2. Save the downloaded JSON as `~/.config/omarchy/gcal/credentials.json`.
3. In the calendar settings drawer (`S`), click **Connect via OAuth2** (or run `omarchy-gcal auth` in your terminal) and complete login in your browser.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Description |
|---|---|
| `1`, `2`, `3`, `4` | Switch to **Day**, **Week**, **Month**, **Year** view |
| `[` / `]` | Move backward / forward in time (by day, week, month, or year) |
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
# Check sync status and cached events
omarchy-gcal status

# Force sync
omarchy-gcal sync

# Add an event from command line
omarchy-gcal add --title "Team Meeting" --date 2026-11-10 --start 14:00 --end 15:00 --location "Google Meet"
```

---

## 📄 License

[MIT](LICENSE) © 2026 Gustavo Costa
