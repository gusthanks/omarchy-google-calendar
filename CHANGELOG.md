# Changelog

All notable changes to this plugin. Versions follow the `version` field in
`manifest.json`.

## 1.3.0 (2026-11-10)

### Changed
- **New plugin id: `gusthx.google-calendar`** (was `gusthx.clock`). An existing install
  is moved once with `dev/migrate-id.sh` (backup, new git checkout, the bar entry in
  `shell.json` with its settings, the `~/.local/bin/omarchy-gcal` link); see
  "Upgrading from 1.2 or earlier" in the README. Calendar config, tokens and cache are
  not affected. `dev/deploy.sh` refuses to run while the old folder exists.
- Display name is now **Calendar for Google**, and the docs say it is not affiliated
  with Google. Author: Gustavo Costa (gusthx).
- The Portuguese sync guide moved to `docs/sync-guide.pt-BR.md`, with an English
  version in `docs/sync-guide.md`. The README is in English with a Portuguese
  translation in `README.pt-BR.md`.
- `dev/migrate-id.sh` and `dev/deploy.sh` keep their backups in
  `~/.local/state/omarchy/plugin-backups/` (or `$BACKUP_DIR`).

### Kept
- The stock calendar shortcut (`Super + Ctrl + Alt + D`) still opens this panel
  (`clonedFrom: omarchy.clock`), and the widget still answers IPC calls on the
  `omarchy.clock` and `omarchy-google-calendar` targets as well as its own id.

### Fixed
- Untitled events: the helper stores an empty title instead of a hard-coded Portuguese
  "(Sem título)", and the panel shows the localized "(No title)"; old caches are mapped.
- The top-bar badge toggle in the settings reads On/Off.
- Day and Week grids: the first visible hour label is no longer clipped, and short Day
  events show one "09:00 · Title" line.
- README shortcut table corrected; the privacy notes say that `events.json` also holds
  the secret iCal address.

### Added
- `docs/demo.gif` (a 10-second tour of the views) and `dev/run.sh gif`, which renders it
  offscreen from mock events in the isolated harness.
- `LICENSE` keeps the upstream Omarchy copyright line (the widget is a clone of the stock
  clock); README Credits.
- `dev/deploy.sh` warns when the deployed commit is not pushed to origin.

## 1.2.0 (2026-11-09)

- Isolated dev harness (`dev/run.sh`): compiles every QML type against the real Omarchy
  `Ui` module and renders the screenshots in `docs/` offscreen from mock events, without
  touching the running shell, your calendar or your config.
- `dev/deploy.sh` installs the committed state as a git checkout and restarts the shell
  once.
- All strings come from the plugin's own catalog (English, Portuguese).
- License set to MIT; README rewritten in English with a privacy section.

## 1.1.0 (2026-11-07)

- Proportional time grid for Day and Week, drag to create, resize and move events,
  click-to-create ghost card.
- Google Meet links, location suggestions with a map preview and a Google Maps button.
- Event search, meeting reminders (including back-to-back meetings), OAuth token refresh
  on 401, auto-detection of the OAuth client file in `~/Downloads`.

## 1.0.0 (2026-11-07)

- First version: a clone of the stock Omarchy clock whose popup shows Day, Week, Month
  and Year views synced with Google Calendar (secret iCal address or OAuth2).
