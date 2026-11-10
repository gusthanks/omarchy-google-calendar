#!/usr/bin/env bash
# Install the committed state of this repo into the live Omarchy plugin.
# Run this only when the work is finished, tested in the dev harness and
# committed. It restarts the shell once at the end so the new version shows.
#
# If the live plugin is a plain copy (not a git checkout), it is first backed
# up to $BACKUP_DIR/<id>.<timestamp> (default ~/.local/state/omarchy/plugin-backups),
# then replaced by a git checkout of this repo, so later deploys are a
# fast-forward. Your calendar config, tokens and cache live outside the plugin
# (~/.config/omarchy/gcal, ~/.local/state/omarchy/gcal) and are not touched.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
id="$(jq -r .id "$repo/manifest.json")"
plugins="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}"
live="$plugins/$id"
branch="$(git -C "$repo" branch --show-current)"

# The id was gusthx.clock before 1.3.0. Move an install under the old id first,
# so the bar never loads the plugin twice.
if [[ -e $plugins/gusthx.clock ]]; then
  echo "Found the old id at $plugins/gusthx.clock: run dev/migrate-id.sh first (one time)." >&2
  exit 1
fi

[[ -z $(git -C "$repo" status --porcelain) ]] || { echo "Commit your changes first (deploy installs HEAD)." >&2; exit 1; }
omarchy plugin validate "$repo"
"$repo/dev/run.sh" check >/dev/null || { "$repo/dev/run.sh" check; echo "QML does not compile; not deploying." >&2; exit 1; }
"$repo/dev/test.sh" >/dev/null || { echo "Unit tests fail (dev/test.sh); not deploying." >&2; exit 1; }

if [[ -L $live ]]; then
  echo "$live is a symlink ($(readlink "$live")); leaving it alone." >&2
  exit 1
elif [[ -d $live/.git ]]; then
  git -C "$live" pull --ff-only -q "$repo" "$branch"
else
  if [[ -e $live ]]; then
    backup="${BACKUP_DIR:-$HOME/.local/state/omarchy/plugin-backups}/$id.$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname "$backup")"
    cp -a "$live" "$backup"
    echo "Backed up the installed copy to $backup"
  fi
  # Clone next to it (dot-prefixed, so the shell does not load it), then swap.
  stage="$plugins/.$id.deploy.$$"
  rm -rf "$stage"
  git clone -q --branch "$branch" "$repo" "$stage"
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  [[ -n $origin ]] && git -C "$stage" remote set-url origin "$origin"
  rm -rf "$live"
  mv "$stage" "$live"
fi
echo "Deployed $(git -C "$repo" log --oneline -1) to $live"
# `omarchy plugin update` pulls from the live copy's origin (GitHub), not from
# this repo: warn when what was just installed is not pushed there yet.
if git -C "$repo" remote get-url origin >/dev/null 2>&1 \
  && [[ -z $(git -C "$repo" branch -r --contains HEAD 2>/dev/null) ]]; then
  echo "Note: HEAD is not pushed to origin; 'omarchy plugin update' pulls from origin, so push before relying on it." >&2
fi

# The shell's hot reload is not reliable for plugins (the old version can stay
# on screen), so finish with one restart. Skip with NO_RESTART=1.
if [[ ${NO_RESTART:-0} != 1 ]]; then
  omarchy restart shell >/dev/null 2>&1 || true
  echo "Shell restarted: the new version is live."
fi
