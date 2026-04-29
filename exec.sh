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
#   ./exec.sh develop claude               # claude with --dangerously-skip-permissions
#   ./exec.sh develop bash                 # explicit bash shell
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

# Resolve WORKSPACE_PATH so working directory uses the host path inside the
# container (matches git worktree metadata, required for Spotless ratcheting)
WORKSPACE_PATH="${WORKSPACE_PATH:-}"
if [ -z "$WORKSPACE_PATH" ] && [ -f "$SCRIPT_DIR/.workspace_path" ]; then
  WORKSPACE_PATH="$(cat "$SCRIPT_DIR/.workspace_path")"
fi

SUBDIR="${1:-}"
if [ -n "$SUBDIR" ]; then
  shift
  WORKDIR="${WORKSPACE_PATH:-/workspace}/$SUBDIR"
else
  WORKDIR="${WORKSPACE_PATH:-/workspace}"
fi

# Default to bash; auto-add --dangerously-skip-permissions when running claude
CMD=("${@:-bash}")
if [ "${CMD[0]}" = "claude" ]; then
  HAS_SKIP=false
  for arg in "${CMD[@]}"; do
    [ "$arg" = "--dangerously-skip-permissions" ] && HAS_SKIP=true
  done
  if [ "$HAS_SKIP" = false ]; then
    CMD=("claude" "--dangerously-skip-permissions" "${CMD[@]:1}")
  fi
fi

# Resolve the coder user's UID inside the container
CODER_UID=$(docker exec "$CONTAINER" id -u coder)

# docker exec doesn't inherit compose environment — pass what's needed.
# MAVEN_OPTS pins maven.repo.local to the host-style path so absolute paths
# baked into caches (Equo P2 bundle-pool, etc.) match the host.
docker exec -it -u "$CODER_UID" -w "$WORKDIR" \
  -e HOME=/home/coder \
  -e "TERM=${TERM:-xterm-256color}" \
  -e "COLORTERM=${COLORTERM:-}" \
  -e "GITHUB_TOKEN=${GITHUB_TOKEN:-}" \
  -e "GH_TOKEN=${GITHUB_TOKEN:-}" \
  -e "HCLOUD_TOKEN=${HCLOUD_TOKEN:-}" \
  -e "HETZNER_S3_ACCESS_KEY=${HETZNER_S3_ACCESS_KEY:-}" \
  -e "HETZNER_S3_SECRET_KEY=${HETZNER_S3_SECRET_KEY:-}" \
  -e "HETZNER_S3_ENDPOINT=${HETZNER_S3_ENDPOINT:-}" \
  -e "MAVEN_OPTS=${MAVEN_OPTS:-} -Dmaven.repo.local=$HOME/.m2/repository" \
  "$CONTAINER" "${CMD[@]}"
