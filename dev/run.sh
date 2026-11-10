#!/usr/bin/env bash
# Run the Google Calendar plugin's dev harness in its OWN Quickshell instance.
# It never touches the live Omarchy shell or the installed plugin, so the bar
# is not reloaded or restarted while you test or take screenshots. It uses
# MOCK events (dev/mock/events.py) and a mock helper (dev/mock/omarchy-gcal):
# your calendar, tokens and ~/.config/omarchy are never read or written.
#
#   dev/run.sh check            compile every plugin type, Panel.qml included
#                               (declared, never instantiated); deploy runs it too
#   dev/run.sh panel [VIEW]     docs/view-<view>.png for day week month year, or VIEW
#   dev/run.sh settings         docs/settings.png  (sync settings drawer)
#   dev/run.sh event            docs/new-event.png (new event drawer)
#   dev/run.sh bar              docs/bar.png       (bar widget with event badge)
#   dev/run.sh gif              docs/demo.gif      (a short tour of the views)
#   dev/run.sh docs             all of the captures above
#   dev/run.sh preview [VIEW]   a window with the panel to click around in
#   dev/run.sh test             unit tests (same as dev/test.sh)
#
# Captures render with Qt's offscreen platform: nothing shows on the desktop.
# DEV_SCALE (default 1.6) stands in for the monitor scale; MOCK_TODAY=YYYY-MM-DD
# pins the mock events (and nothing else) to another date.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

# A throwaway Quickshell config: Omarchy's Commons and a shadow copy of its
# Ui module whose KeyboardPanel (a layer-shell window) is the dev stub, this
# repo as "plugin", and the harness as shell.qml.
cfg="${XDG_RUNTIME_DIR:-/tmp}/gusthx-google-calendar-dev"
rm -rf "$cfg"
mkdir -p "$cfg/Ui" "$cfg/state" "$cfg/config"
ln -s "$omarchy_shell/Commons" "$cfg/Commons"
for f in "$omarchy_shell"/Ui/*; do ln -s "$f" "$cfg/Ui/$(basename "$f")"; done
rm "$cfg/Ui/KeyboardPanel.qml"
cp "$repo/dev/stubs/KeyboardPanel.qml" "$cfg/Ui/KeyboardPanel.qml"
ln -s "$repo" "$cfg/plugin"
cp "$repo/dev/Harness.qml" "$cfg/shell.qml"

python3 -I "$repo/dev/mock/events.py" "$cfg/state/events.json" ${MOCK_TODAY:+"$MOCK_TODAY"}
export OMARCHY_GCAL_STATE_DIR="$cfg/state" OMARCHY_GCAL_CONFIG_DIR="$cfg/config"
export OMARCHY_GCAL_NO_CLI_LINK=1 MOCK_GCAL="$repo/dev/mock/omarchy-gcal" MOCK_GCAL_LOG="$cfg/mock-gcal.log"

# Log lines from Quickshell/Qt that are expected offscreen and not ours.
noise='qmlscanner|portal|polkit|QT_QPA_PLATFORM|actually running wayland|window masks|--- WARNING ---|No PanelWindow backend|toplevel-mapping|Hyprland IPC|HYPRLAND_INSTANCE'

render() { # mode out [log-name]
  local log="$cfg/${3:-$1}.log"
  MODE="$1" OUT="$2" timeout "${CAPTURE_TIMEOUT:-60}" env QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR="${DEV_SCALE:-1.6}" \
    quickshell -n -p "$cfg/shell.qml" >"$log" 2>&1 || true
  if grep -E 'WARN|ERROR' "$log" | grep -vE "$noise" | grep -q .; then
    grep -E 'WARN|ERROR' "$log" | grep -vE "$noise" >&2
  fi
  # A still is one png; the GIF is a folder of frames plus list.txt.
  [ -f "$2" ] || [ -s "$2/list.txt" ] || { echo "no image: see $log" >&2; return 1; }
  echo "${2#"$repo"/}"
}

gif() {
  local frames="$cfg/frames"
  rm -rf "$frames"; mkdir -p "$frames"
  # One frame per state of the tour plus how long it stays on screen
  # (list.txt, an ffmpeg concat list); rendered at 1x and grabbed at 1.5x.
  # The tour takes minutes on a slow, busy machine, hence the long timeout
  # (GIF_TIMEOUT seconds); the harness quits as soon as the last frame is saved.
  DEV_SCALE="${DEV_SCALE:-1}" CAPTURE_TIMEOUT="${GIF_TIMEOUT:-900}" VIEW=week render gif "$frames" gif >/dev/null \
    || { echo "no frames: see $cfg/gif.log" >&2; return 1; }
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$frames/list.txt" \
    -vf "fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$repo/docs/demo.gif"
  echo "docs/demo.gif ($(ls "$frames"/*.png | wc -l) states, $(du -k "$repo/docs/demo.gif" | cut -f1) KB)"
}

mkdir -p "$repo/docs"
case "${1:-preview}" in
  panel)
    for v in ${2:-day week month year}; do VIEW="$v" render panel "$repo/docs/view-$v.png" "panel-$v"; done ;;
  settings) VIEW=month render settings "$repo/docs/settings.png" ;;
  event)    VIEW=day render event "$repo/docs/new-event.png" ;;
  bar)      render bar "$repo/docs/bar.png" ;;
  gif)      gif ;;
  docs)     "$0" panel; "$0" settings; "$0" event; "$0" bar; "$0" gif ;;
  preview)  MODE=preview VIEW="${2:-month}" quickshell -n -p "$cfg/shell.qml" ;;
  test)     exec "$repo/dev/test.sh" ;;
  check)
    # Compile-only against the REAL Ui module: types are declared inside
    # Components that never get created, so no window opens. Needs the
    # Wayland backend (KeyboardPanel is a PanelWindow).
    rm -rf "$cfg/Ui"; ln -s "$omarchy_shell/Ui" "$cfg/Ui"
    files=$(cd "$repo" && ls *.qml | sed 's/\.qml$//')
    { echo 'import QtQuick'; echo 'import Quickshell'; echo 'import "plugin" as Plugin'; echo 'ShellRoot {'
      i=0; for f in $files; do echo "  Component { id: c$i; Plugin.$f {} }"; i=$((i+1)); done
      echo '  Component.onCompleted: {'
      i=0; for f in $files; do echo "    console.warn(\"CHECK $f\", c$i.status === Component.Ready ? \"OK\" : c$i.errorString())"; i=$((i+1)); done
      echo '  }'; echo '}'; } > "$cfg/shell.qml"
    timeout 20 quickshell -n -p "$cfg/shell.qml" >"$cfg/check.log" 2>&1 || true
    if grep -q 'Failed to load configuration' "$cfg/check.log"; then grep -E 'ERROR' "$cfg/check.log" >&2; exit 1; fi
    grep -a 'CHECK ' "$cfg/check.log" | sed 's/^.*CHECK /CHECK /'
    grep -aq 'CHECK ' "$cfg/check.log" && ! grep -a 'CHECK ' "$cfg/check.log" | grep -vq ' OK$' ;;
  *) sed -n '2,23p' "$0"; exit 1 ;;
esac
