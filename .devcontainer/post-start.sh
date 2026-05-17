#!/usr/bin/env bash
# Runs on every container start. Keep this fast — anything slow belongs in setup.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "==> gh authenticated; you can run: bb-sync"
else
  echo "==> gh not authenticated. Run 'gh auth login' before 'bb-sync'."
fi
