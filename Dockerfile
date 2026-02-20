FROM node:22-slim

# Install basic tools
RUN apt-get update && apt-get install -y \
    git curl jq fish \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw

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

# Expose gateway port for communication
EXPOSE 18789

# Default shell
SHELL ["/bin/bash", "-c"]

# Entrypoint: starts nerve cord heartbeat loop, then execs into openclaw
ENTRYPOINT ["/usr/local/bin/larva-entrypoint.sh"]
CMD ["gateway", "--port", "18789"]
