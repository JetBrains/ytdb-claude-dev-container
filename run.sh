#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Launch Claude Code in an autonomous Docker container (single-terminal mode).
#
# Usage:
#   ./run.sh [workspace-path]
#
# Examples:
#   ./run.sh                           # mount current directory
#   ./run.sh ~/Projects/myproject      # mount a specific project
#
# Environment (set in .env or export before running):
#   ANTHROPIC_API_KEY   – required, your Anthropic API key
#   GITHUB_TOKEN        – GitHub PAT for git + gh CLI (HTTPS)
#   GIT_USER_NAME       – git author name
#   GIT_USER_EMAIL      – git author email
#   CLAUDE_TASK         – if set, run this prompt non-interactively and exit
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve workspace to an absolute path
WORKSPACE="${1:-.}"
if [ ! -d "$WORKSPACE" ]; then
  echo "Error: '$WORKSPACE' is not a directory" >&2
  exit 1
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

export WORKSPACE_PATH="$WORKSPACE"

# Compute CPU limit as 85% of host CPUs (prevents container from starving the host)
if [ -z "${CPU_LIMIT:-}" ]; then
  export CPU_LIMIT=$(awk "BEGIN {printf \"%.1f\", $(nproc) * 0.85}")
fi

echo "Claude Code Docker"
echo "  Workspace : $WORKSPACE"
echo ""

# Build image (quiet if already cached)
docker compose -f "$SCRIPT_DIR/docker-compose.yml" build --quiet

# Run interactively — overrides the default idle command, removed on exit
docker compose -f "$SCRIPT_DIR/docker-compose.yml" run --rm claude \
  claude --dangerously-skip-permissions
