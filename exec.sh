#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Open a new terminal in the running Claude Code container.
#
# Usage:
#   ./exec.sh [subdir] [command...]
#
# Examples:
#   ./exec.sh                              # bash in /workspace
#   ./exec.sh develop                      # bash in /workspace/develop
#   ./exec.sh develop claude --dangerously-skip-permissions
#   ./exec.sh feature-branch               # bash in /workspace/feature-branch
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env for any config
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

CONTAINER=$(docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps -q claude 2>/dev/null)

if [ -z "$CONTAINER" ]; then
  echo "Error: container is not running. Start it first with ./start.sh" >&2
  exit 1
fi

SUBDIR="${1:-}"
if [ -n "$SUBDIR" ]; then
  shift
  WORKDIR="/workspace/$SUBDIR"
else
  WORKDIR="/workspace"
fi

CMD=("${@:-bash}")

# Resolve the coder user's UID inside the container
CODER_UID=$(docker exec "$CONTAINER" id -u coder)

# docker exec doesn't inherit compose environment — pass what's needed
docker exec -it -u "$CODER_UID" -w "$WORKDIR" \
  -e HOME=/home/coder \
  -e "GITHUB_TOKEN=${GITHUB_TOKEN:-}" \
  -e "GH_TOKEN=${GITHUB_TOKEN:-}" \
  "$CONTAINER" "${CMD[@]}"
