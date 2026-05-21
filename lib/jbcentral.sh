#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# JetBrains Central CLI proxy integration helpers.
#
# The host runs `jbcentral proxy start` (uses the host keyring for auth).
# `socat` forwards the docker network's bridge gateway IP to host's 127.0.0.1
# so the container can reach the proxy via `host.docker.internal`.
#
# JBC_PROXY_SECRET / JBC_PROXY_PORT are exported here and passed into the
# container; entrypoint.sh writes them into ~/.claude/settings.json as
# `apiKeyHelper` + `ANTHROPIC_BASE_URL`. No jbcentral binary or ~/.wire
# bind mount is needed inside the container.
# ─────────────────────────────────────────────────────────────────────────────

JBC_PIDFILE_NAME=".jbcentral-socat.pid"

# Detect host jbcentral, read proxy_secret/proxy_port, start the proxy.
# Exports JBC_PROXY_SECRET and JBC_PROXY_PORT (empty if jbcentral not set up).
# Silent no-op when jbcentral isn't installed on the host.
jbcentral_proxy_up() {
  command -v jbcentral >/dev/null 2>&1 || return 0
  local wire_cfg="$HOME/.wire/config.json"
  [ -f "$wire_cfg" ] || return 0

  JBC_PROXY_SECRET="$(jq -r '.proxy_secret // empty' "$wire_cfg" 2>/dev/null || true)"
  JBC_PROXY_PORT="$(jq -r '.proxy_port // 19516' "$wire_cfg" 2>/dev/null || true)"
  [ -n "$JBC_PROXY_SECRET" ] || return 0
  export JBC_PROXY_SECRET JBC_PROXY_PORT

  # Idempotent: no-op if the proxy daemon is already running.
  jbcentral proxy start >/dev/null 2>&1 || true
  echo "[ok] JetBrains Central proxy running on host (port $JBC_PROXY_PORT)"
}

# Start socat on the host's docker0 bridge IP (where `host-gateway` resolves
# to for any container with `host.docker.internal:host-gateway` in extra_hosts),
# forwarding to host's 127.0.0.1:$JBC_PROXY_PORT.
# Args: <script-dir>
jbcentral_forwarder_up() {
  local script_dir="$1"
  [ -n "${JBC_PROXY_SECRET:-}" ] || return 0

  if ! command -v socat >/dev/null 2>&1; then
    echo "[warn] socat not installed — install with: sudo dnf install -y socat" >&2
    echo "       Container will not be able to reach the JetBrains Central proxy." >&2
    return 0
  fi

  local gateway
  gateway="$(docker network inspect bridge \
    --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
  [ -n "$gateway" ] || return 0

  jbcentral_forwarder_down "$script_dir"

  socat TCP-LISTEN:"$JBC_PROXY_PORT",bind="$gateway",reuseaddr,fork \
        TCP:127.0.0.1:"$JBC_PROXY_PORT" >/dev/null 2>&1 &
  echo $! > "$script_dir/$JBC_PIDFILE_NAME"
  echo "[ok] socat forwarder: $gateway:$JBC_PROXY_PORT -> 127.0.0.1:$JBC_PROXY_PORT"
}

jbcentral_forwarder_down() {
  local script_dir="$1"
  local pidfile="$script_dir/$JBC_PIDFILE_NAME"
  if [ -f "$pidfile" ]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
}
