# Claude Code Docker — Manual

Autonomous Claude Code environment running inside a Docker container with full
permission bypass ("god mode"). Designed for multi-worktree Java/polyglot
development on Fedora/Plasma.

## Prerequisites

- Docker Engine with Compose plugin (`docker compose`)
- A GitHub Personal Access Token (PAT) with `repo` and `read:org` scopes
- An Anthropic API key

## Quick Start

```bash
cd ~/Projects/claude-code-docker

# 1. Configure secrets
cp .env.example .env
#    Edit .env — fill in ANTHROPIC_API_KEY, GITHUB_TOKEN, GIT_USER_NAME, GIT_USER_EMAIL

# 2. Build the image (first time only; cached afterwards)
docker compose build

# 3a. Single-terminal mode — one worktree, interactive
./run.sh ~/Projects/ytdb/develop

# 3b. Multi-terminal mode — multiple worktrees, persistent container
./start.sh ~/Projects/ytdb
```

## Files Overview

| File | Purpose |
|---|---|
| `Dockerfile` | Ubuntu 24.04 image with all dev tooling |
| `docker-compose.yml` | Container orchestration, volumes, networking |
| `entrypoint.sh` | Startup: UID matching, git/gh auth, Claude Code install |
| `.env.example` | Template for secrets and configuration |
| `run.sh` | Single-terminal interactive launcher |
| `start.sh` | Start container in background (multi-terminal) |
| `exec.sh` | Open a new terminal in the running container |
| `claude.sh` | Open Claude Code mapped to your current host directory |
| `stop.sh` | Stop the container and release sleep inhibitor |

## Workflows

### Single-Terminal Mode

Best for quick, focused work on a single worktree.

```bash
./run.sh ~/Projects/ytdb/develop
```

This builds the image (if needed), starts a temporary container, and drops you
into an interactive Claude Code session. The container is removed on exit;
persistent volumes are kept.

### Multi-Terminal Mode

Best for working on multiple worktrees simultaneously within one container.

**Step 1 — Start the container.** Mount the parent directory containing all
your git worktrees:

```bash
./start.sh ~/Projects/ytdb
```

The container starts in the background. On Fedora/Plasma, system sleep is
automatically inhibited while the container runs.

**Step 2 — Open terminals.** Each call opens a new interactive session in the
same container:

```bash
# Claude Code in a specific worktree
./exec.sh develop claude --dangerously-skip-permissions

# Claude Code in another worktree
./exec.sh feature-branch claude --dangerously-skip-permissions

# Plain bash shell in a worktree
./exec.sh develop

# Bash at workspace root
./exec.sh
```

**Step 3 — Stop everything:**

```bash
./stop.sh
```

### Quick Launch from Any Directory (`claude.sh`)

Open Claude Code from your current host directory without specifying paths.

**Setup (one-time):**

1. Add `WORKSPACE_PATH` to your `.env`:
   ```
   WORKSPACE_PATH=/home/you/Projects/ytdb
   ```

2. Add a shell alias to `~/.bashrc` or `~/.zshrc`:
   ```bash
   alias cc='~/Projects/claude-code-docker/claude.sh'
   ```

**Usage:**

```bash
cd ~/Projects/ytdb/develop
cc                     # Claude Code opens at ~/Projects/ytdb/develop inside the container

cd ~/Projects/ytdb/feature-branch
cc                     # Claude Code opens at ~/Projects/ytdb/feature-branch
```

The workspace is mounted at the **same absolute path** inside the container, so
your current directory maps directly. Requires the container to be running
(`./start.sh`).

### Non-Interactive Task Mode

Run a prompt and exit automatically:

```bash
CLAUDE_TASK="Fix all failing tests in core" ./run.sh ~/Projects/ytdb/develop
```

Or set `CLAUDE_TASK` in `.env` for repeated use.

## Environment Variables

Set these in `.env` (loaded automatically by all scripts).

| Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for Claude |
| `GITHUB_TOKEN` | Yes | GitHub PAT for git HTTPS + `gh` CLI |
| `GIT_USER_NAME` | Yes | Git author name |
| `GIT_USER_EMAIL` | Yes | Git author email |
| `WORKSPACE_PATH` | No | Default workspace directory (overridden by script arguments) |
| `MAVEN_REPO` | No | Host Maven repo path (default: `~/.m2`) |
| `HOST_UID` | No | Override auto-detected UID |
| `HOST_GID` | No | Override auto-detected GID |
| `CLAUDE_TASK` | No | Prompt for non-interactive mode |

## What's in the Image

| Tool | Version | Notes |
|---|---|---|
| Ubuntu | 24.04 | Base image |
| Node.js | 22 LTS | Required by Claude Code |
| JDK | 21 | OpenJDK headless |
| Git + git-lfs | System | With `gh` CLI for GitHub API |
| Docker CLI | Latest | Compose + Buildx plugins |
| async-profiler | 4.3 | Java profiler (`asprof` on PATH) |
| Python 3 | System | With pip and venv |
| Build tools | gcc, g++, make | `build-essential` |
| Utilities | jq, ripgrep, fd, tree, tmux, vim-tiny | Common dev tools |

## Architecture

### UID/GID Matching

The container runs an entrypoint as root that:

1. Reads the UID/GID of the mounted workspace directory
2. Adjusts the in-container `coder` user to match
3. Runs all subsequent operations (git, gh, npm, claude) as `coder` via `gosu`

This means every file Claude creates or modifies in your workspace is owned by
**your host user**, not root. The Maven cache (`~/.m2`) works seamlessly for the
same reason.

You can override auto-detection with `HOST_UID` and `HOST_GID` environment
variables.

### Persistent Volumes

| Volume | Container Path | Contents |
|---|---|---|
| `claude-code-npm` | `/opt/claude-npm` | Claude Code npm installation |
| `claude-code-data` | `/home/coder/.claude` | Claude Code config and conversation history |

These survive container restarts, image rebuilds, and `stop.sh`. Claude Code
auto-updates on each container start — the npm package is checked in the
background, so startup is not blocked.

To reset Claude Code completely:

```bash
docker volume rm claude-code-npm claude-code-data
```

### Host-Mounted Directories

| Host Path | Container Path | Mode |
|---|---|---|
| `WORKSPACE_PATH` | `/workspace` + symlink from host path | read-write |
| `~/.m2` (or `MAVEN_REPO`) | `/home/coder/.m2` | read-write |
| `/var/run/docker.sock` | `/var/run/docker.sock` | read-write |

The workspace is mounted at `/workspace`. On startup, the entrypoint creates a
symlink from the original host absolute path to `/workspace` (e.g.
`/home/you/Projects/ytdb` -> `/workspace`). This ensures git worktree
cross-references (which store absolute host paths in `.git` files) resolve
correctly through the symlink.

### Networking

- **Outbound only.** No ports are published; no incoming traffic is accepted.
- Inter-container communication is disabled (`enable_icc: false`).
- Outbound internet is available (Anthropic API, GitHub, npm, Maven Central).
- `host.docker.internal` resolves to the host machine.

### Docker-in-Docker

The container has `privileged: true` and the host Docker socket is mounted.
Claude Code can build and run Docker containers — they execute as sibling
containers on your host Docker daemon.

### Sleep Inhibitor (Fedora/Plasma)

`start.sh` runs `systemd-inhibit` in the background to prevent the system from
sleeping while the container is active. `stop.sh` releases the inhibitor.

Verify it's active:

```bash
systemd-inhibit --list
```

## Authentication Flow

On every container start, the entrypoint:

1. Authenticates `gh` CLI with your `GITHUB_TOKEN` via `gh auth login --with-token`
2. Registers `gh` as the git credential helper via `gh auth setup-git`
3. Sets the git protocol to HTTPS via `gh config set git_protocol https`

All git push/pull/clone operations and `gh` API calls use your PAT
transparently. No SSH keys are needed.

## Troubleshooting

### "WORKSPACE_PATH not set" when using `claude.sh`

Add `WORKSPACE_PATH=/path/to/parent/dir` to `.env`.

### "container is not running" from `exec.sh` or `claude.sh`

Start the container first: `./start.sh ~/Projects/ytdb`

### Files owned by root in workspace

The UID detection may have failed. Check with:

```bash
docker exec <container-id> id coder
```

Override manually: `HOST_UID=$(id -u) HOST_GID=$(id -g) ./start.sh ...`

### Docker commands fail inside the container

The `coder` user is added to the Docker socket's group automatically. If it
still fails, check the socket permissions on the host:

```bash
ls -la /var/run/docker.sock
```

### Claude Code not found on first start

First run installs Claude Code synchronously — this takes 30-60 seconds.
Subsequent starts check for updates in the background without blocking.

### Stale sleep inhibitor after unclean shutdown

```bash
# Find and kill orphaned inhibitor
ps aux | grep 'systemd-inhibit.*claude-code-docker'
# Or just remove the PID file
rm ~/Projects/claude-code-docker/.inhibit.pid
```
