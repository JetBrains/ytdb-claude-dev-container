#!/usr/bin/env bash
# Stop the Claude Code container.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Release sleep inhibitor
if [ -f "$SCRIPT_DIR/.inhibit.pid" ]; then
  kill "$(cat "$SCRIPT_DIR/.inhibit.pid")" 2>/dev/null || true
  rm -f "$SCRIPT_DIR/.inhibit.pid"
  echo "[ok] Sleep inhibitor released"
fi

docker compose -f "$SCRIPT_DIR/docker-compose.yml" down
rm -f "$SCRIPT_DIR/.workspace_path"
echo "Container stopped. Persistent volumes (npm, .claude, .m2) are preserved."
