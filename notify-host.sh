#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# notify-host.sh — Claude Code Notification hook.
#
# Forwards Claude's user-attention notifications to the host desktop (KDE,
# GNOME, etc.) via the host's D-Bus session socket, which is bind-mounted
# into the container at /run/host-bus.
#
# Reads the hook JSON payload from stdin. No-ops silently if D-Bus isn't
# reachable (e.g. headless host, socket not mounted, libnotify missing).
# ─────────────────────────────────────────────────────────────────────────────
set -u

export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/host-bus}"

input="$(cat)"
msg="$(printf '%s' "$input" | jq -r '.message // "needs your attention"' 2>/dev/null)"
[ -n "$msg" ] || msg="needs your attention"

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
title="Claude Code"
[ -n "$cwd" ] && title="Claude Code ($(basename "$cwd"))"

notify-send -a "Claude Code" -i utilities-terminal "$title" "$msg" 2>/dev/null || true
exit 0
