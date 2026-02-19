#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Open Claude Code in the running container, mapped to your current directory.
#
# Call from anywhere inside the mounted workspace tree:
#   cd ~/Projects/ytdb/develop && claude.sh
#   cd ~/Projects/ytdb/feature-branch && claude.sh
#
# Tip: create an alias in your shell rc file:
#   alias cc='~/Projects/claude-code-docker/claude.sh'
# Then just:  cd ~/Projects/ytdb/develop && cc
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

WORKSPACE_PATH="${WORKSPACE_PATH:-}"
if [ -z "$WORKSPACE_PATH" ]; then
  echo "Error: WORKSPACE_PATH not set. Add it to .env or export it." >&2
  exit 1
fi

WORKSPACE_PATH="$(cd "$WORKSPACE_PATH" && pwd)"
CWD="$(pwd)"

if [[ "$CWD" != "$WORKSPACE_PATH"* ]]; then
  echo "Error: current directory is not inside WORKSPACE_PATH ($WORKSPACE_PATH)" >&2
  exit 1
fi

# Map host path → container /workspace path
REL_PATH="${CWD#"$WORKSPACE_PATH"}"
CONTAINER_DIR="/workspace${REL_PATH}"

# Find running container
CONTAINER=$(docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps -q claude 2>/dev/null)
if [ -z "$CONTAINER" ]; then
  echo "Error: container is not running. Start it first with ./start.sh" >&2
  exit 1
fi

CODER_UID=$(docker exec "$CONTAINER" id -u coder)

exec docker exec -it -u "$CODER_UID" -w "$CONTAINER_DIR" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  "$CONTAINER" claude --dangerously-skip-permissions "$@"
