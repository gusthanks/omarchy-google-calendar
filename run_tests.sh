#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Running Python Backend Unit Tests ==="
python3 -m unittest discover -s tests -p "test_*.py"

echo ""
echo "=== Running Node.js Model Unit Tests ==="
node --test tests/test_model.js

echo ""
echo "All tests passed successfully!"
