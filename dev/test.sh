#!/usr/bin/env bash
# Unit tests: the Python helper (omarchy-gcal) and the pure JS model (Model.js).
# Everything runs against temp dirs; nothing reads or writes your calendar,
# tokens, ~/.config/omarchy or ~/.local/bin.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
export PYTHONDONTWRITEBYTECODE=1 OMARCHY_GCAL_NO_CLI_LINK=1

echo "=== omarchy-gcal (Python) ==="
python3 -m unittest discover -s dev/tests -t . -p "test_*.py"

echo
echo "=== Model.js (node) ==="
node --test dev/tests/test_model.js dev/tests/test_model_units.js

echo
echo "All tests passed."
