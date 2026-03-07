#!/usr/bin/env bash
set -e

echo "=== Claude Code Container ==="

# ── Symlink /workspace → host path ────────────────────────────────────────────
# The workspace is mounted at $WORKSPACE_PATH (the host absolute path) so that
# getcwd() returns paths matching git worktree .git metadata. A /workspace
# symlink is created for convenience and backward compatibility.
if [ -n "$WORKSPACE_PATH" ] && [ "$WORKSPACE_PATH" != "/workspace" ]; then
  rm -rf /workspace
  ln -s "$WORKSPACE_PATH" /workspace
  echo "[ok] Symlink: /workspace -> $WORKSPACE_PATH"
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

# Restore .claude.json from the persistent volume (if previously saved).
# We can't use a symlink because Claude Code does atomic writes (temp+rename)
# which replace the symlink with a regular file outside the volume.
if [ -f /home/coder/.claude/.claude.json.persist ]; then
  cp /home/coder/.claude/.claude.json.persist /home/coder/.claude.json
fi

# ── Migrate Claude project history from /workspace to host path ──────────────
# When WORKSPACE_PATH changes (e.g. /workspace → /home/user/Projects/ytdb),
# Claude Code won't find old conversation history because it keys projects by
# working directory path. Create symlinks so both old and new paths resolve.
if [ -n "$WORKSPACE_PATH" ] && [ "$WORKSPACE_PATH" != "/workspace" ]; then
  PROJECTS_DIR="/home/coder/.claude/projects"
  if [ -d "$PROJECTS_DIR" ]; then
    OLD_PREFIX="-workspace"
    NEW_PREFIX=$(echo "$WORKSPACE_PATH" | tr '/' '-')
    for old_dir in "$PROJECTS_DIR"/${OLD_PREFIX}*; do
      [ -d "$old_dir" ] || continue
      old_name="$(basename "$old_dir")"
      suffix="${old_name#"$OLD_PREFIX"}"
      new_name="${NEW_PREFIX}${suffix}"
      if [ ! -e "$PROJECTS_DIR/$new_name" ]; then
        ln -s "$old_name" "$PROJECTS_DIR/$new_name"
        echo "[ok] Migrated project history: $old_name -> $new_name"
      fi
    done
  fi
fi

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

# ── DNS firewall (domain whitelist) ──────────────────────────────────────────
if [ "${DNS_FIREWALL:-true}" = "true" ]; then
  /opt/scripts/setup-dns-firewall.sh
else
  echo "[ok] DNS firewall disabled"
fi

# ── Git setup (as coder) ────────────────────────────────────────────────────
gosu coder git config --global --add safe.directory '*'
[ -n "$GIT_USER_NAME" ]  && gosu coder git config --global user.name  "$GIT_USER_NAME"
[ -n "$GIT_USER_EMAIL" ] && gosu coder git config --global user.email "$GIT_USER_EMAIL"

echo "[ok] Git configured"

# ── GitHub CLI auth (HTTPS + PAT) ────────────────────────────────────────────
if [ -n "$GITHUB_TOKEN" ]; then
  # gh CLI uses GITHUB_TOKEN env var automatically — no login needed.
  # Just configure git to use gh as the credential helper for HTTPS.
  gosu coder gh auth setup-git 2>/dev/null || true
  gosu coder gh config set git_protocol https 2>/dev/null || true
  echo "[ok] GitHub CLI authenticated (HTTPS via GITHUB_TOKEN)"
fi

# ── MCP servers ──────────────────────────────────────────────────────────────
# Claude Code reads MCP servers from ~/.claude.json (user scope), NOT from
# ~/.claude/settings.json (which is for permissions/hooks).
MCP_CFG="/home/coder/.claude.json"
if [ ! -f "$MCP_CFG" ]; then
  echo '{}' > "$MCP_CFG"
fi
# maven-indexer-mcp: indexes ~/.m2 JARs for class search, method signatures,
# decompilation, and interface implementation discovery.
# Pre-install globally so it starts instantly (npx -y downloads on every cold
# start which can exceed MCP timeout).
gosu coder npm install -g maven-indexer-mcp@latest --prefix /opt/claude-npm 2>/dev/null || true
if ! jq -e '.mcpServers["maven-indexer"]' "$MCP_CFG" &>/dev/null; then
  jq '.mcpServers["maven-indexer"] = {"command":"maven-indexer-mcp","args":[]}' \
    "$MCP_CFG" > "${MCP_CFG}.tmp" && mv "${MCP_CFG}.tmp" "$MCP_CFG"
fi
# Remove stale MCP servers from previous versions
for stale in "code-index" "maven"; do
  if jq -e ".mcpServers[\"$stale\"]" "$MCP_CFG" &>/dev/null; then
    jq "del(.mcpServers[\"$stale\"])" "$MCP_CFG" > "${MCP_CFG}.tmp" && mv "${MCP_CFG}.tmp" "$MCP_CFG"
  fi
done
chown coder:coder "$MCP_CFG"
echo "[ok] MCP servers configured"

# ── Claude Code global permissions ────────────────────────────────────────
# Allow all Bash commands globally so Claude Code doesn't prompt for each one.
SETTINGS_DIR="/home/coder/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi
if ! jq -e '.permissions.allow' "$SETTINGS_FILE" 2>/dev/null | grep -q '"Bash"'; then
  jq '.permissions.allow = ((.permissions.allow // []) + ["Bash"] | unique)' \
    "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
fi
chown -R coder:coder "$SETTINGS_DIR"
echo "[ok] Global permissions configured"

# ── Claude Code install / update ─────────────────────────────────────────────
if gosu coder bash -c 'command -v claude' &>/dev/null; then
  echo "[ok] Claude Code found — checking for updates in background"
  (gosu coder npm update -g @anthropic-ai/claude-code 2>/dev/null \
    || { rm -rf /opt/claude-npm/lib/node_modules/@anthropic-ai 2>/dev/null
         gosu coder npm install -g @anthropic-ai/claude-code; }) &>/dev/null &
else
  echo "     Installing Claude Code (first run) ..."
  gosu coder npm install -g @anthropic-ai/claude-code 2>/dev/null \
    || { echo "     Cleaning stale npm volume and retrying..."
         rm -rf /opt/claude-npm/lib/node_modules/@anthropic-ai
         gosu coder npm install -g @anthropic-ai/claude-code; }
  echo "[ok] Claude Code installed"
fi

# ── Periodic .claude.json sync to volume ─────────────────────────────────────
# Runs in background; saves auth config every 10s so it survives restarts
(while true; do
  sleep 10
  cp /home/coder/.claude.json /home/coder/.claude/.claude.json.persist 2>/dev/null || true
done) &

echo "=== Ready ==="
echo ""

# ── Launch as coder ──────────────────────────────────────────────────────────
if [ -n "$CLAUDE_TASK" ]; then
  exec gosu coder claude --dangerously-skip-permissions -p "$CLAUDE_TASK"
fi

exec gosu coder "$@"
