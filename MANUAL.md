# Claude Code Docker — Manual

Autonomous Claude Code environment running inside a Docker container with full
permission bypass ("god mode"). Designed for multi-worktree Java/polyglot
development on Fedora/Plasma.

## Prerequisites

- Docker Engine with Compose plugin (`docker compose`)
- A GitHub Personal Access Token (fine-grained with **Contents: Read and write**,
  or classic with `repo` scope)
- An Anthropic account (interactive login on first container run)

## Quick Start

```bash
cd ~/Projects/claude-code-docker

# 1. Configure secrets (GitHub PAT and git identity — no paths needed)
cp .env.example .env
#    Edit .env — fill in GITHUB_TOKEN, GIT_USER_NAME, GIT_USER_EMAIL

# 2. Build the image (first time only; cached afterwards)
docker compose build

# 3a. Single-terminal mode — one project, interactive
./run.sh ~/Projects/ytdb/develop

# 3b. Multi-terminal mode — mount a parent directory, work across projects
./start.sh ~/Projects
```

## Files Overview

| File | Purpose |
|---|---|
| `Dockerfile` | Ubuntu 24.04 image with all dev tooling |
| `docker-compose.yml` | Container orchestration, volumes, networking |
| `entrypoint.sh` | Startup: symlink, UID matching, git/gh auth, Claude Code install |
| `.env.example` | Template for secrets and configuration |
| `run.sh` | Single-terminal interactive launcher |
| `start.sh` | Start container in background (multi-terminal) |
| `exec.sh` | Open a new terminal in the running container |
| `claude.sh` | Open Claude Code mapped to your current host directory |
| `stop.sh` | Stop the container and release sleep inhibitor |

## Workflows

### Single-Terminal Mode

Best for quick, focused work on a single project or worktree.

```bash
./run.sh ~/Projects/ytdb/develop
```

This builds the image (if needed), starts a temporary container, and drops you
into an interactive Claude Code session. The container is removed on exit;
persistent volumes are kept.

### Multi-Terminal Mode

Best for working across multiple projects or worktrees simultaneously within
one container.

**Step 1 — Start the container.** Mount a parent directory containing your
projects:

```bash
# All projects under ~/Projects
./start.sh ~/Projects

# Or just a specific repo with its worktrees
./start.sh ~/Projects/ytdb
```

The workspace path is saved automatically — no need to set it in `.env`.
On Fedora/Plasma, system sleep is automatically inhibited while the container
runs.

**Step 2 — Open terminals.** Each call opens a new interactive session in the
same container:

```bash
# Claude Code in a specific worktree
./exec.sh ytdb/develop claude --dangerously-skip-permissions

# Claude Code in another worktree
./exec.sh ytdb/feature-branch claude --dangerously-skip-permissions

# Plain bash shell
./exec.sh ytdb/develop

# Bash at workspace root
./exec.sh
```

**Step 3 — Stop everything:**

```bash
./stop.sh
```

### Quick Launch from Any Directory (`claude.sh`)

Open Claude Code from your current host directory without specifying paths.

**Setup (one-time):** Add shell aliases to `~/.bashrc` or `~/.zshrc`:

```bash
alias claude-sandbox='~/Projects/claude-code-docker/claude.sh'
alias claude-sandbox-start='~/Projects/claude-code-docker/start.sh ~/Projects'
alias claude-sandbox-stop='~/Projects/claude-code-docker/stop.sh'
```

**Usage:** The workspace path is picked up automatically from `start.sh`:

```bash
# Start the container once
claude-sandbox-start

# Then from any terminal, just cd and run
cd ~/Projects/ytdb/develop && claude-sandbox
cd ~/Projects/ytdb/feature-branch && claude-sandbox
cd ~/Projects/other-project && claude-sandbox

# When done for the day
claude-sandbox-stop
```

The script maps your current host directory to the corresponding
`/workspace/...` path inside the container. Requires the container to be
running (`./start.sh`).

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
| `GITHUB_TOKEN` | Yes | GitHub PAT for git HTTPS + `gh` CLI |
| `GIT_USER_NAME` | Yes | Git author name |
| `GIT_USER_EMAIL` | Yes | Git author email |
| `MAVEN_REPO` | No | Host Maven repo path (default: `~/.m2`) |
| `HOST_UID` | No | Override auto-detected UID |
| `HOST_GID` | No | Override auto-detected GID |
| `CLAUDE_TASK` | No | Prompt for non-interactive mode |
| `DNS_FIREWALL` | No | Domain whitelist firewall (default: `true`). Set `false` to disable |
| `EXTRA_ALLOWED_DOMAINS` | No | Comma-separated domains to add to the whitelist at runtime |

`WORKSPACE_PATH` is **not** needed in `.env`. It is determined automatically:
- `start.sh` and `run.sh` accept it as a command-line argument
- `start.sh` saves it to `.workspace_path` for `claude.sh` and `exec.sh`

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
| dnsmasq + iptables | System | DNS-based domain whitelist firewall |

## Architecture

### UID/GID Matching

The default `ubuntu` user (UID 1000) is removed from the base image during
build. A `coder` user is created at UID/GID 1000. At runtime, the entrypoint:

1. Reads the UID/GID of the mounted `/workspace` directory
2. Adjusts the `coder` user to match via `usermod`/`groupmod`
3. Runs all subsequent operations (git, gh, npm, claude) as `coder` via `gosu`

This means every file Claude creates or modifies in your workspace is owned by
**your host user**, not root. The Maven cache (`~/.m2`) works seamlessly for the
same reason.

You can override auto-detection with `HOST_UID` and `HOST_GID` environment
variables.

### Git Worktree Support

Git worktrees store absolute host paths in `.git` files (e.g.
`gitdir: /home/you/Projects/ytdb/develop/.git/worktrees/feature-branch`).

The workspace is mounted at `/workspace`. On startup, the entrypoint creates a
symlink from the original host absolute path to `/workspace`:

```
/home/you/Projects -> /workspace   (symlink)
```

This ensures all git worktree cross-references resolve correctly through the
symlink without any path translation.

### Persistent Volumes

| Volume | Container Path | Contents |
|---|---|---|
| `claude-code-npm` | `/opt/claude-npm` | Claude Code npm installation |
| `claude-code-data` | `/home/coder/.claude` | Claude Code config, conversation history, and auth |

These survive container restarts, image rebuilds, and `stop.sh`. Claude Code
auto-updates on each container start — the npm package is checked in the
background, so startup is not blocked.

**Anthropic authentication** is handled by Claude Code's interactive login on
first run. The auth config (`.claude.json`) is persisted into the `claude-data`
volume via a background sync process — you only need to log in once. A periodic
sync (every 10 seconds) plus a save-on-exit in `claude.sh` ensures the config
survives container restarts.

To reset Claude Code completely:

```bash
docker volume rm claude-code-npm claude-code-data
```

### Host-Mounted Directories

| Host Path | Container Path | Mode |
|---|---|---|
| Workspace (from `start.sh` / `run.sh` argument) | `/workspace` + symlink from host path | read-write |
| `~/.m2` (or `MAVEN_REPO`) | `/home/coder/.m2` | read-write |
| `./config/` | `/opt/config/` | read-only |
| `/var/run/docker.sock` | `/var/run/docker.sock` | read-write |

### Networking

- **Outbound only.** No ports are published; no incoming traffic is accepted.
- Inter-container communication is disabled (`enable_icc: false`).
- `host.docker.internal` resolves to the host machine.

### DNS Firewall (Domain Whitelist)

By default, outbound network access is restricted to a whitelist of allowed
domains. This prevents Claude Code from reaching arbitrary internet hosts.

**How it works:**

1. `dnsmasq` runs as a local DNS resolver on `127.0.0.1`
2. It only resolves domains listed in `config/allowed-domains.txt`
3. `iptables` rules block DNS queries to any external resolver
4. Non-whitelisted domains fail to resolve — connections are refused

**Allowed domains** include infrastructure (Anthropic API, GitHub, npm, Maven
Central, Gradle) and documentation sites matching the project's `.claude/settings.json`
WebFetch permissions. The full list is in `config/allowed-domains.txt`.

**Editing the whitelist:**

Edit `config/allowed-domains.txt` on the host (one base domain per line).
Subdomains are included automatically — e.g. `apache.org` covers
`maven.apache.org`, `lucene.apache.org`, etc. The `config/` directory is
bind-mounted into the container (directory mounts, unlike file mounts, survive
inode-replacing edits by editors). A background watcher polls for changes every
10 seconds — dnsmasq is hot-reloaded automatically. No rebuild or restart needed.

**Adding domains at runtime (one-off):**

```bash
# In .env or as an environment variable
EXTRA_ALLOWED_DOMAINS=example.com,cooldb.io
```

These are appended to the file-based whitelist on container start.

**Disabling the firewall:**

```bash
# In .env
DNS_FIREWALL=false
```

Or pass it directly: `DNS_FIREWALL=false ./start.sh ~/Projects`

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

### Anthropic (Claude Code)

Authenticate interactively on first run — the login prompt appears automatically.
The auth config (`.claude.json`) is synced to the `claude-data` volume every
10 seconds and on session exit, so it persists across container restarts.

### GitHub (git + gh CLI)

The `GITHUB_TOKEN` environment variable (from `.env`) is passed into the
container as both `GITHUB_TOKEN` and `GH_TOKEN` (the newer preferred name).
The `gh` CLI uses it automatically — no `gh auth login` needed.
On each container start, the entrypoint:

1. Registers `gh` as the git credential helper via `gh auth setup-git`
2. Sets the git protocol to HTTPS via `gh config set git_protocol https`

All git push/pull/clone operations and `gh` API calls use your PAT
transparently. No SSH keys are needed.

## Troubleshooting

### "WORKSPACE_PATH not set" when using `claude.sh`

Run `./start.sh <path>` first — it saves the workspace path automatically.
Or add `WORKSPACE_PATH=/path/to/parent/dir` to `.env` as a fallback.

### "container is not running" from `exec.sh` or `claude.sh`

Start the container first: `./start.sh ~/Projects`

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

### Network request fails for a domain that should be allowed

The domain (or its base domain) may be missing from `config/allowed-domains.txt`.
Add it — the change is hot-reloaded within ~10 seconds (no rebuild needed).

To test DNS resolution inside the container:

```bash
./exec.sh bash -c 'getent hosts example.com'
```

To temporarily disable the firewall: `DNS_FIREWALL=false ./start.sh ...`

### Stale sleep inhibitor after unclean shutdown

```bash
# Find and kill orphaned inhibitor
ps aux | grep 'systemd-inhibit.*claude-code-docker'
# Or just remove the PID file
rm ~/Projects/claude-code-docker/.inhibit.pid
```
