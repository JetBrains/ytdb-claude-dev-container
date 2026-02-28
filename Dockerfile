FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_PREFIX=/opt/claude-npm \
    PATH="/opt/async-profiler/bin:/opt/claude-npm/bin:${PATH}" \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ── Base packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg2 lsb-release software-properties-common \
    git git-lfs openssh-client \
    build-essential \
    python3 python3-pip python3-venv \
    jq ripgrep fd-find tree unzip zip \
    less vim-tiny nano tmux \
    sudo locales gosu \
    dnsmasq iptables iputils-ping \
    && locale-gen en_US.UTF-8 \
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 LTS ──────────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI ───────────────────────────────────────────────────────────────
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) \
       signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
       https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ── Docker CLI + Compose + Buildx ────────────────────────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) \
       signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/ubuntu \
       $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# ── JDK 21 (default) ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# ── JDK 25 (Adoptium Temurin) ────────────────────────────────────────────────
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) ADOPT_ARCH=x64 ;; \
         arm64) ADOPT_ARCH=aarch64 ;; \
         *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://api.adoptium.net/v3/binary/latest/25/ga/linux/${ADOPT_ARCH}/jdk/hotspot/normal/eclipse" \
       -o /tmp/jdk25.tar.gz \
    && mkdir -p /usr/lib/jvm/temurin-25 \
    && tar xzf /tmp/jdk25.tar.gz -C /usr/lib/jvm/temurin-25 --strip-components=1 \
    && rm /tmp/jdk25.tar.gz

RUN ln -s /usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture) /usr/lib/jvm/java-21

ENV JAVA_HOME=/usr/lib/jvm/java-21
ENV JAVA21_HOME=/usr/lib/jvm/java-21
ENV JAVA25_HOME=/usr/lib/jvm/temurin-25

# ── uv (Python package runner — used by code-index-mcp) ──────────────────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
RUN ln -sf /usr/local/bin/uv /usr/local/bin/uvx

# ── async-profiler 4.3 ────────────────────────────────────────────────────────
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) AP_ARCH=x64 ;; \
         arm64) AP_ARCH=arm64 ;; \
         *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/async-profiler/async-profiler/releases/download/v4.3/async-profiler-4.3-linux-${AP_ARCH}.tar.gz" \
       | tar xz -C /opt \
    && mv "/opt/async-profiler-4.3-linux-${AP_ARCH}" /opt/async-profiler

# ── Non-root user (UID/GID adjusted at runtime to match host) ────────────────
# Remove the default 'ubuntu' user that occupies UID/GID 1000 in the base image
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g 1000 coder \
    && useradd -m -u 1000 -g 1000 -s /bin/bash coder

# ── Directory structure ──────────────────────────────────────────────────────
RUN mkdir -p /opt/claude-npm /workspace /opt/scripts /home/coder/.claude \
    && chown -R coder:coder /opt/claude-npm /home/coder

COPY entrypoint.sh /opt/scripts/entrypoint.sh
COPY setup-dns-firewall.sh /opt/scripts/setup-dns-firewall.sh
COPY config/allowed-domains.txt /opt/config/allowed-domains.txt
RUN chmod +x /opt/scripts/entrypoint.sh /opt/scripts/setup-dns-firewall.sh

WORKDIR /workspace
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
CMD ["claude", "--dangerously-skip-permissions"]
