FROM node:22-slim

# Install basic tools + Chromium dependencies
RUN apt-get update && apt-get install -y \
    git curl jq fish \
    # Chromium deps for headless browser in container
    chromium \
    fonts-liberation \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxkbcommon0 \
    libgbm1 \
    libasound2 \
    libcups2 \
    libxdamage1 \
    libxrandr2 \
    libpango-1.0-0 \
    libcairo2 \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry (forge, anvil, cast, chisel)
RUN curl -L https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup
ENV PATH="/root/.foundry/bin:${PATH}"

# Install OpenClaw globally
RUN npm install -g openclaw

# Install Playwright Chromium (uses the system Chromium, just needs the node bindings)
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN npm install -g playwright
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium

# Install yarn (corepack)
RUN corepack enable && corepack prepare yarn@stable --activate || true

# Create workspace, config dir, and agent auth dir
RUN mkdir -p /root/.openclaw/workspace /root/workspace \
    /root/.openclaw/agents/larva/agent

# Copy pre-baked config (supports all models, runs gateway)
COPY openclaw.json /root/.openclaw/openclaw.json

# Seed auth profiles so Ollama doesn't complain about missing keys
RUN echo '{"version":1,"profiles":{"ollama:default":{"type":"none","provider":"ollama"}}}' \
    > /root/.openclaw/agents/larva/agent/auth-profiles.json

# Ollama doesn't need a real key but OpenClaw auth system checks for one
ENV OLLAMA_API_KEY=not-needed

# Nerve cord heartbeat entrypoint
COPY larva-entrypoint.sh /usr/local/bin/larva-entrypoint.sh
RUN chmod +x /usr/local/bin/larva-entrypoint.sh

# The shared volume mount point — host work persists here
VOLUME /root/workspace

# Expose gateway port + dev server ports
EXPOSE 18789 3000 8545

# Default shell
SHELL ["/bin/bash", "-c"]

# Entrypoint: starts nerve cord heartbeat loop, then execs into openclaw
ENTRYPOINT ["/usr/local/bin/larva-entrypoint.sh"]
CMD ["gateway", "--port", "18789"]
