#!/usr/bin/env bash
# One-time migration of an installed copy from the old plugin id `gusthx.clock`
# to `gusthx.google-calendar` (renamed in 1.3.0). Safe to run more than once:
# every step checks whether it is already done and skips it.
#
#   1. Backs up ~/.config/omarchy/plugins/gusthx.clock to $BACKUP_DIR
#      (default ~/.local/state/omarchy/plugin-backups).
#   2. Installs ~/.config/omarchy/plugins/gusthx.google-calendar as a git
#      checkout of this repo (origin set to this repo's origin, like deploy.sh).
#   3. In ~/.config/omarchy/shell.json, renames the widget entry
#      {"id": "gusthx.clock", ...} to "gusthx.google-calendar", keeping all of
#      its settings and its place in the bar (the file is backed up first).
#   4. Repoints the ~/.local/bin/omarchy-gcal symlink to the new path (only if
#      it is a symlink into the old plugin folder, or dangling).
#   5. Removes the old plugin folder (it is in the backup from step 1).
#
# Your calendar data is not touched: ~/.config/omarchy/gcal (config, tokens)
# and ~/.local/state/omarchy/gcal (events cache) do not depend on the id.
#
# It does NOT restart the shell. Run `dev/deploy.sh` (or `omarchy restart
# shell`) afterwards so the bar loads the plugin under its new id.
#
#   dev/migrate-id.sh          do it
#   DRY_RUN=1 dev/migrate-id.sh   only print what would change
#   BACKUP_DIR=~/backups dev/migrate-id.sh   keep the backups somewhere else
#
# Everything is relative to $HOME, so it can be rehearsed against a fake home:
#   HOME=/run/user/1000/fakehome dev/migrate-id.sh
set -euo pipefail

old_id="gusthx.clock"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
new_id="$(jq -r .id "$repo/manifest.json")"
plugins="$HOME/.config/omarchy/plugins"
old="$plugins/$old_id"
new="$plugins/$new_id"
shell_json="$HOME/.config/omarchy/shell.json"
cli_link="$HOME/.local/bin/omarchy-gcal"
backups="${BACKUP_DIR:-$HOME/.local/state/omarchy/plugin-backups}"
stamp="$(date +%Y%m%d-%H%M%S)"
dry="${DRY_RUN:-0}"

say() { printf '%s\n' "$*"; }
run() { if [[ $dry == 1 ]]; then say "  (dry run) $*"; else "$@"; fi; }

[[ $new_id != "$old_id" ]] || { say "manifest id is still $old_id; nothing to migrate." >&2; exit 1; }

# --- 1. back up the old plugin folder ---------------------------------------
if [[ -e $old || -L $old ]]; then
  backup="$backups/$old_id.$stamp"
  say "Backing up $old -> $backup"
  run mkdir -p "$backups"
  run cp -a "$old" "$backup"
else
  say "No $old: nothing to back up."
fi

# --- 2. install the new id as a git checkout --------------------------------
if [[ -d $new/.git ]]; then
  say "$new is already a git checkout: leaving it (dev/deploy.sh updates it)."
elif [[ -e $new || -L $new ]]; then
  say "$new exists but is not a git checkout; not touching it. Move it away and run again." >&2
  exit 1
else
  if [[ ! -e $old && ! -L $old ]] && ! grep -q "\"$old_id\"" "$shell_json" 2>/dev/null; then
    say "Neither $old nor a \"$old_id\" bar entry exists: nothing to migrate."
    say "For a fresh install use: omarchy plugin add https://github.com/gusthanks/omarchy-google-calendar.git --enable"
    exit 0
  fi
  [[ -z $(git -C "$repo" status --porcelain) ]] || { say "Commit your changes first (the checkout installs HEAD)." >&2; exit 1; }
  if command -v omarchy >/dev/null 2>&1; then omarchy plugin validate "$repo"; fi
  branch="$(git -C "$repo" branch --show-current)"
  # Prefer the remote the old checkout tracked, then this repo's origin.
  origin="$(git -C "$old" remote get-url origin 2>/dev/null || git -C "$repo" remote get-url origin 2>/dev/null || true)"
  say "Installing $new (git checkout of $repo, branch $branch${origin:+, origin $origin})"
  if [[ $dry != 1 ]]; then
    mkdir -p "$plugins"
    stage="$plugins/.$new_id.migrate.$$"   # dot-prefixed: the shell ignores it
    rm -rf "$stage"
    git clone -q --branch "$branch" "$repo" "$stage"
    [[ -n $origin ]] && git -C "$stage" remote set-url origin "$origin"
    mv "$stage" "$new"
  fi
fi

# --- 3. rename the widget entry in shell.json -------------------------------
# Only objects whose "id" is exactly the old id, in the bar layout sections
# and in the top-level "plugins" list; every other key of the entry is kept.
rename_filter='
  def ren: if type == "object" and .id == $old then .id = $new else . end;
  (if (.bar.layout | type) == "object"
     then .bar.layout |= with_entries(.value |= (if type == "array" then map(ren) else . end))
     else . end)
  | (if (.plugins | type) == "array" then .plugins |= map(ren) else . end)'
if [[ -f $shell_json ]]; then
  count=$(jq --arg old "$old_id" '[.. | objects | select(.id? == $old)] | length' "$shell_json")
  if (( count > 0 )); then
    say "Renaming $count \"$old_id\" entr$([[ $count == 1 ]] && echo y || echo ies) in $shell_json to \"$new_id\""
    if [[ $dry != 1 ]]; then
      mkdir -p "$backups"
      cp -a "$shell_json" "$backups/shell.json.$stamp"
      say "  (previous file saved as $backups/shell.json.$stamp)"
      tmp="$(mktemp "$shell_json.migrate.XXXXXX")"
      jq --arg old "$old_id" --arg new "$new_id" "$rename_filter" "$shell_json" >"$tmp"
      chmod --reference="$shell_json" "$tmp"
      mv "$tmp" "$shell_json"
    fi
  else
    say "No \"$old_id\" entry in $shell_json."
  fi
else
  say "No $shell_json."
fi

# --- 4. repoint ~/.local/bin/omarchy-gcal -----------------------------------
if [[ -L $cli_link ]]; then
  current="$(readlink "$cli_link")"
  if [[ $current == "$new/omarchy-gcal" ]]; then
    say "$cli_link already points to $new."
  elif [[ $current == "$old/"* || ! -e $cli_link ]]; then
    say "Repointing $cli_link -> $new/omarchy-gcal (was $current)"
    run ln -sfn "$new/omarchy-gcal" "$cli_link"
  else
    say "$cli_link points to $current (another copy): leaving it."
  fi
elif [[ -e $cli_link ]]; then
  say "$cli_link is a regular file, not a link: leaving it."
else
  say "No $cli_link (the helper creates it on first run)."
fi

# --- 5. remove the old plugin folder ----------------------------------------
if [[ -e $old || -L $old ]]; then
  if [[ $dry != 1 ]] && ! ls -d "$backups/$old_id".* >/dev/null 2>&1; then
    say "No backup of $old found in $backups; not removing it." >&2
    exit 1
  fi
  say "Removing $old (backed up in $backups)"
  run rm -rf "$old"
fi

say "Done. Restart the shell once (dev/deploy.sh does it) to load $new_id."
