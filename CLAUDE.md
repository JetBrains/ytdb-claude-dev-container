# CLAUDE.md — ytdb-claude-dev-container

## Project Overview

Docker-based autonomous development container for running Claude Code against
YouTrackDB (and other JVM/polyglot) projects. Provides a fully provisioned
environment with UID matching, git worktree support, Docker-in-Docker, and
persistent Claude Code installation.

- **Repository**: https://github.com/JetBrains/ytdb-claude-dev-container
- **License**: Apache 2.0

## File Structure

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition: Ubuntu 24.04, Node.js 22, JDK 21, Docker CLI, gh, async-profiler 4.3 |
| `docker-compose.yml` | Container orchestration: volumes, networking, environment |
| `entrypoint.sh` | Startup logic: symlink creation, UID/GID matching, git/gh auth, MCP setup, Claude Code install |
| `run.sh` | Single-terminal launcher (creates + removes container per session) |
| `start.sh` | Background launcher for multi-terminal workflow |
| `exec.sh` | Open a new shell/claude session in the running container |
| `claude.sh` | Launch Claude Code mapped to your current host directory |
| `stop.sh` | Stop container + release sleep inhibitor |
| `.env.example` | Template for secrets and configuration |
| `config/allowed-domains.txt` | DNS firewall domain whitelist |
| `setup-dns-firewall.sh` | DNS firewall setup (dnsmasq + iptables) |
| `MANUAL.md` | Full user-facing documentation |

## Build and Test

```bash
# Build the image
docker compose build

# Quick smoke test (no API key needed)
WORKSPACE_PATH=/tmp GITHUB_TOKEN="" docker compose run --rm -e GITHUB_TOKEN="" \
  claude bash -c 'id && node --version && java --version && git --version'

# Full test with real config (.env must be populated)
./start.sh ~/Projects/ytdb
./exec.sh develop bash -c 'id && git worktree list | head -5'
./stop.sh
```

## Key Architecture Decisions

### UID/GID Matching
The `ubuntu` user (UID 1000) is deleted from the base image in the Dockerfile.
A `coder` user is created at UID/GID 1000. At runtime, the entrypoint adjusts
`coder`'s UID/GID to match the mounted workspace owner via `usermod`/`groupmod`,
then runs everything through `gosu coder`. This ensures files written by Claude
Code are owned by the host user.

### Git Worktree Symlink
Git worktrees store absolute host paths in `.git` files. The workspace is mounted
at `/workspace`, and the entrypoint creates a symlink from the host absolute path
(e.g. `/home/user/Projects/ytdb`) to `/workspace`. This lets git resolve
cross-worktree references without path translation.

### Networking
Egress-only by default: no published ports, inter-container communication
disabled.

### DNS Firewall
Outbound access is restricted to whitelisted domains via `dnsmasq` + `iptables`.
`dnsmasq` runs on `127.0.0.1` and only resolves domains listed in
`config/allowed-domains.txt`. `iptables` blocks external DNS to prevent bypassing.
Controlled by `DNS_FIREWALL` env var (default `true`). Domains are base domains;
subdomains are included automatically (e.g. `apache.org` covers
`maven.apache.org`). The `config/` directory is bind-mounted from the host (not
the file — directory mounts survive inode-replacing edits); a background watcher
polls mtime every 10s and hot-reloads dnsmasq on change.
`EXTRA_ALLOWED_DOMAINS` env var accepts comma-separated domains appended at
startup.

### Claude Code Persistence
Claude Code is installed into `/opt/claude-npm` (a named Docker volume). On
subsequent starts, the entrypoint checks for updates in the background without
blocking startup.

### Auth Persistence
Claude Code's `.claude.json` (auth config) lives in the container filesystem at
`/home/coder/.claude.json`. A symlink won't work because Claude Code does atomic
writes (temp file + rename) which replace symlinks with regular files. Instead,
the entrypoint restores `.claude.json` from the volume on start, and a background
process syncs it back every 10 seconds. `claude.sh` also saves it after each
session exit.

### GitHub Token
`GITHUB_TOKEN` is passed as an env var; `gh` CLI uses it automatically without
`gh auth login`. Both `GITHUB_TOKEN` and `GH_TOKEN` are set in `docker exec`
sessions since `docker exec` doesn't inherit compose environment variables.

## Code Style

- Shell scripts: `bash`, `set -euo pipefail`, 2-space indent
- Use `gosu coder` for any operation that should run as the non-root user
- Comments use `# ── Section ──` format with box-drawing characters for visual separation
- All scripts include a usage header comment block

## Editing Guidelines

- **Dockerfile**: Keep layers cacheable — group related `apt-get` installs, always `rm -rf /var/lib/apt/lists/*`
- **entrypoint.sh**: Runs as root, must be idempotent (container may restart). Use `2>/dev/null || true` for operations that may legitimately fail
- **Shell scripts** (`run.sh`, `start.sh`, etc.): Must source `.env` if present, resolve paths to absolute, and give clear error messages
- **docker-compose.yml**: Environment variables use passthrough syntax (`- VAR` not `- VAR=value`) so values come from the host/`.env`
- **MANUAL.md**: Keep in sync with any behavioral changes. This is the user-facing documentation
- **`config/allowed-domains.txt`**: Edit to add/remove whitelisted domains. Changes are hot-reloaded within ~10s (no rebuild needed)
- **`config/allowed-domains.local.txt`**: Personal/project-specific domains (gitignored). Same format, also hot-reloaded
- **`setup-dns-firewall.sh`**: Runs as root in the entrypoint. Must be idempotent
- **`.env` must never be committed** — it contains secrets. Only `.env.example` is tracked
- **`.workspace_path`** is written by `start.sh` and read by `claude.sh`/`exec.sh`. Cleaned up by `stop.sh`. Never committed (in `.gitignore`)

## Testing Changes

**NEVER destroy the user's running Claude installation when testing.** Specifically:
- **NEVER run `docker compose down -v`** — this deletes all named volumes including auth, conversation history, and cached packages
- **NEVER remove `claude-code-data` or `claude-code-uv-cache` volumes** — they contain irreplaceable auth tokens and session history
- For testing, always use `docker compose run --rm` with a throwaway container — this does not affect running containers or volumes
- If a specific volume must be recreated (e.g. `claude-code-npm`), stop the container first with `docker compose stop`, then remove **only** that single volume by name with `docker volume rm`

After modifying the Dockerfile or entrypoint, always:

1. Rebuild: `docker compose build`
2. Verify UID: container user should match host UID (`id` inside container)
3. Verify file write: `touch` a file in the workspace, check ownership on host
4. Verify git: `git status` and `git worktree list` should work in any worktree
5. Verify symlink: the host absolute path should resolve inside the container
