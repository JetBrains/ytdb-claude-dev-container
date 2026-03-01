#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Shared build helper for launcher scripts.
#
# Provides build_image_if_needed() which rebuilds the Docker image from
# scratch when it is older than IMAGE_MAX_AGE_DAYS (default: 7).
# ─────────────────────────────────────────────────────────────────────────────

IMAGE_NAME="claude-code-autonomous:latest"
IMAGE_MAX_AGE_SECONDS=$(( ${IMAGE_MAX_AGE_DAYS:-7} * 86400 ))

# build_image_if_needed <compose-file>
#   - If image doesn't exist: full build
#   - If image is >= IMAGE_MAX_AGE_DAYS old: full rebuild (--pull --no-cache)
#   - Otherwise: cached build (--quiet)
build_image_if_needed() {
  local compose_file="$1"

  local created
  created="$(docker inspect --format '{{.Created}}' "$IMAGE_NAME" 2>/dev/null || true)"

  if [ -z "$created" ]; then
    echo "Image not found — building from scratch..."
    docker compose -f "$compose_file" build --pull --no-cache
    return
  fi

  local created_epoch now_epoch age
  created_epoch="$(date -d "$created" +%s)"
  now_epoch="$(date +%s)"
  age=$(( now_epoch - created_epoch ))

  if [ "$age" -ge "$IMAGE_MAX_AGE_SECONDS" ]; then
    local age_days=$(( age / 86400 ))
    echo "Image is ${age_days}d old (max ${IMAGE_MAX_AGE_DAYS:-7}d) — rebuilding..."
    docker compose -f "$compose_file" build --pull --no-cache
  else
    docker compose -f "$compose_file" build --quiet
  fi
}
