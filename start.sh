#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Start the Claude Code container in the background.
#
# Usage:
#   ./start.sh [workspace-path]
#
# Mount a parent directory that contains all your git worktrees, e.g.:
#   ./start.sh ~/Projects/ytdb
#
# Then open terminals with:
#   ./exec.sh develop            # cd into /workspace/develop
#   ./exec.sh feature-branch     # cd into /workspace/feature-branch
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKSPACE="${1:-.}"
if [ ! -d "$WORKSPACE" ]; then
  echo "Error: '$WORKSPACE' is not a directory" >&2
  exit 1
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

export WORKSPACE_PATH="$WORKSPACE"

# Persist so claude.sh / exec.sh can read it without .env
echo "$WORKSPACE" > "$SCRIPT_DIR/.workspace_path"

echo "Claude Code Docker"
echo "  Workspace : $WORKSPACE"
echo ""

docker compose -f "$SCRIPT_DIR/docker-compose.yml" build --quiet

# Start in background with an idle process; exec.sh opens terminals
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

# Prevent Plasma/systemd from sleeping while the container runs
if command -v systemd-inhibit &>/dev/null; then
  # Kill stale inhibitor if any
  if [ -f "$SCRIPT_DIR/.inhibit.pid" ]; then
    kill "$(cat "$SCRIPT_DIR/.inhibit.pid")" 2>/dev/null || true
  fi
  systemd-inhibit --what=sleep \
    --who="claude-code-docker" \
    --why="Claude Code container is running" \
    --mode=block sleep infinity &
  echo $! > "$SCRIPT_DIR/.inhibit.pid"
  echo "[ok] Sleep inhibited while container is running"
fi

echo ""
echo "Container is running. Open terminals with:"
echo "  ./exec.sh [subdir]                  # bash shell"
echo "  ./exec.sh [subdir] claude --dangerously-skip-permissions  # claude code"
echo "  cc                                  # from any worktree directory"
echo ""
echo "Stop with:  ./stop.sh"
