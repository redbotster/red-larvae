FROM node:22-slim

# Install basic tools
RUN apt-get update && apt-get install -y \
    git curl jq fish \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw

# Create workspace and config dir
RUN mkdir -p /root/.openclaw/workspace /root/workspace

# Copy pre-baked config (supports all models, runs gateway)
COPY openclaw.json /root/.openclaw/openclaw.json

# The shared volume mount point — host work persists here
VOLUME /root/workspace

# Expose gateway port for communication
EXPOSE 18789

# Default shell
SHELL ["/bin/bash", "-c"]

# Two modes:
#   1. Gateway mode (default): runs a gateway you can talk to
#   2. One-shot mode: docker run ... --entrypoint openclaw ... agent --local ...
#
# Gateway mode lets the parent OpenClaw send messages to the larva.
ENTRYPOINT ["openclaw"]
CMD ["gateway", "--port", "18789"]
