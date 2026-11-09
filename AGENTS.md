# Notes for AI agents (and humans) working on this plugin

## Never work on the live plugin

The copy installed at `~/.config/omarchy/plugins/gusthx.google-calendar/` is the one the user's Omarchy
shell is running. Saving a file there hot-reloads the plugin in the user's bar, and
`omarchy restart shell` restarts the whole bar. Doing that over and over while developing
is disruptive.

- **Edit only this repository** (the working copy in `~/Work/`).
- **Do not** edit, copy into, or `git` anything under `~/.config/omarchy/plugins/`.
- **Do not** run `omarchy restart shell`, `omarchy refresh shell`, `omarchy theme set`,
  or IPC calls (`omarchy-shell gusthx.google-calendar ...`) to test a change.
- **Do not** take screenshots of the user's desktop (`grim`) to check your work.

## Test and capture in isolation

`dev/run.sh` starts a **separate** Quickshell instance with Omarchy's `Commons` library,
a shadow copy of its `Ui` module (whose `KeyboardPanel`, a layer-shell window, is swapped
for `dev/stubs/KeyboardPanel.qml`) and this repo. It never touches the running shell.
It feeds MOCK events (`dev/mock/events.py`) and a stub helper (`dev/mock/omarchy-gcal`),
with auto-sync and notifications off: the user's calendar, tokens and config are never
read, and nothing is synced, created or deleted. Captures render offscreen (Qt's
offscreen platform), so nothing shows on the desktop.

```bash
dev/run.sh check        # compile every type against the REAL Ui (deploy runs this too)
dev/run.sh panel [VIEW] # docs/view-<day|week|month|year>.png
dev/run.sh settings     # docs/settings.png
dev/run.sh event        # docs/new-event.png
dev/run.sh bar          # docs/bar.png
dev/run.sh docs         # all captures
dev/run.sh preview      # a window with the panel (opens on the desktop: only if asked)
dev/test.sh             # unit tests (helper + Model.js), all in temp dirs
```

Look at the rendered images to verify a change. QML warnings from the harness are
printed by `dev/run.sh`; fix them before going further. Also run
`omarchy plugin validate .`.

Never run the real `omarchy-gcal` against the user's home while testing (it syncs their
account and manages `~/.local/bin/omarchy-gcal`). Tests and the harness set
`OMARCHY_GCAL_STATE_DIR`, `OMARCHY_GCAL_CONFIG_DIR` and `OMARCHY_GCAL_NO_CLI_LINK=1`.

What the harness cannot render (the real bar, live data, popup placement) is checked by
the user after deploying, not by you on their live shell.

## Deploy once, at the end, and restart the bar

When ALL the requested work is finished, tested in the harness and committed:

```bash
dev/deploy.sh   # validate + check + tests, update the live plugin, restart the shell once
```

If the live plugin is a plain copy, the script backs it up to
`~/Work/backups/gusthx.google-calendar.<timestamp>` and replaces it with a git checkout of this
repo; afterwards it fast-forwards. The shell's hot reload is not reliable for plugins (the
old version can stay on screen), so the deploy always ends with one
`omarchy restart shell`. Do not tell the user something is done before this ran. Never use
`omarchy refresh shell` (it resets the bar layout). Never deploy or restart in the middle
of a task.

## The old id (`gusthx.clock`)

Before 1.3.0 the plugin id was `gusthx.clock`. `dev/migrate-id.sh` moves an existing
install to the new id once (backup, new checkout, the bar entry in `shell.json`, the
`~/.local/bin/omarchy-gcal` link) and is safe to re-run; `dev/deploy.sh` refuses to run
while `~/.config/omarchy/plugins/gusthx.clock` still exists. Test it only against a fake
`HOME` (e.g. `HOME=/run/user/1000/fakehome dev/migrate-id.sh`), never the real one.

## Other conventions

- Repo root = plugin root (the layout `omarchy plugin add <url>` expects). Tests and
  tooling live in `dev/`.
- Strings go through the plugin's own catalog in `i18n/` (`Commons.Translations`, `tr`),
  never through `Commons.I18n` keys, which Omarchy may rename.
- Never print or show the secret iCal address or tokens (log the host only).
- The bar widget is always visible on an older laptop: keep it cheap (no extra timers or
  processes); heavy work belongs in the panel content, which loads on first open.
