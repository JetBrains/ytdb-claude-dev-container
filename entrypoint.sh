#!/usr/bin/env bash
set -e

echo "=== Claude Code Container ==="

# ── Symlink host absolute path → /workspace ──────────────────────────────────
# Git worktrees store absolute host paths in .git files. This symlink ensures
# those paths resolve correctly inside the container.
if [ -n "$WORKSPACE_PATH" ] && [ "$WORKSPACE_PATH" != "/workspace" ]; then
  mkdir -p "$(dirname "$WORKSPACE_PATH")"
  ln -sfn /workspace "$WORKSPACE_PATH"
  echo "[ok] Symlink: $WORKSPACE_PATH -> /workspace"
fi

# ── Match host UID/GID ───────────────────────────────────────────────────────
# Auto-detect from the mounted workspace; fall back to 1000
HOST_UID="${HOST_UID:-$(stat -c '%u' /workspace 2>/dev/null || echo 1000)}"
HOST_GID="${HOST_GID:-$(stat -c '%g' /workspace 2>/dev/null || echo 1000)}"
[ "$HOST_UID" = "0" ] && HOST_UID=1000
[ "$HOST_GID" = "0" ] && HOST_GID=1000

CUR_UID=$(id -u coder)
CUR_GID=$(id -g coder)
[ "$CUR_GID" != "$HOST_GID" ] && groupmod -g "$HOST_GID" coder 2>/dev/null || true
[ "$CUR_UID" != "$HOST_UID" ] && usermod -u "$HOST_UID" coder 2>/dev/null || true

# Own the persistent volumes / home
chown -R coder:coder /home/coder /opt/claude-npm
echo "[ok] Running as UID=$(id -u coder) GID=$(id -g coder)"

# ── Docker socket ────────────────────────────────────────────────────────────
if [ -S /var/run/docker.sock ]; then
  DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
  if [ "$DOCKER_SOCK_GID" != "0" ]; then
    # Create/reuse a group matching the socket's GID and add coder to it
    DOCKER_GROUP=$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1 || true)
    if [ -z "$DOCKER_GROUP" ]; then
      groupadd -g "$DOCKER_SOCK_GID" docker-host
      DOCKER_GROUP=docker-host
    fi
    usermod -aG "$DOCKER_GROUP" coder
  else
    chmod 660 /var/run/docker.sock 2>/dev/null || true
  fi
  echo "[ok] Docker socket available"
fi

# ── Git setup (as coder) ────────────────────────────────────────────────────
gosu coder git config --global --add safe.directory '*'
[ -n "$GIT_USER_NAME" ]  && gosu coder git config --global user.name  "$GIT_USER_NAME"
[ -n "$GIT_USER_EMAIL" ] && gosu coder git config --global user.email "$GIT_USER_EMAIL"
echo "[ok] Git configured"

# ── GitHub CLI auth (HTTPS + PAT) ────────────────────────────────────────────
if [ -n "$GITHUB_TOKEN" ]; then
  echo "$GITHUB_TOKEN" | gosu coder gh auth login --with-token 2>/dev/null
  gosu coder gh auth setup-git 2>/dev/null
  gosu coder gh config set git_protocol https 2>/dev/null || true
  echo "[ok] GitHub CLI authenticated (HTTPS)"
fi

# ── Anthropic API key check ──────────────────────────────────────────────────
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "[WARN] ANTHROPIC_API_KEY is not set — Claude Code will not function without it"
fi

# ── Claude Code install / update ─────────────────────────────────────────────
if gosu coder bash -c 'command -v claude' &>/dev/null; then
  echo "[ok] Claude Code found — checking for updates in background"
  gosu coder npm update -g @anthropic-ai/claude-code &>/dev/null &
else
  echo "     Installing Claude Code (first run) ..."
  gosu coder npm install -g @anthropic-ai/claude-code
  echo "[ok] Claude Code installed"
fi

echo "=== Ready ==="
echo ""

# ── Launch as coder ──────────────────────────────────────────────────────────
if [ -n "$CLAUDE_TASK" ]; then
  exec gosu coder claude --dangerously-skip-permissions -p "$CLAUDE_TASK"
fi

exec gosu coder "$@"
