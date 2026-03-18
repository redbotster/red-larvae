#!/bin/bash
# Red Larva entrypoint — starts nerve cord heartbeat, then runs OpenClaw gateway

# ── Nerve Cord Registration & Heartbeat ──
# Env vars (set by larvae.sh at spawn time):
#   NERVE_CORD_URL    — e.g. http://host.docker.internal:9999
#   NERVE_CORD_TOKEN  — auth token
#   LARVA_NAME        — this larva's name (e.g. "contract-dev")
#   LARVA_MODEL       — model being used (e.g. "opus")

if [ -n "$NERVE_CORD_URL" ] && [ -n "$NERVE_CORD_TOKEN" ] && [ -n "$LARVA_NAME" ]; then
  (
    # Wait for gateway to be ready
    for i in $(seq 1 30); do
      curl -sf "http://localhost:18789/health" > /dev/null 2>&1 && break
      sleep 1
    done

    # Register with nerve cord
    curl -sf -X POST "${NERVE_CORD_URL}/larvae" \
      -H "Authorization: Bearer ${NERVE_CORD_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${LARVA_NAME}\",
        \"model\": \"${LARVA_MODEL:-unknown}\",
        \"status\": \"alive\",
        \"port\": 18789
      }" > /dev/null 2>&1

    # Log registration
    echo "🦞 Registered with nerve cord as '${LARVA_NAME}'"

    # Heartbeat loop — every 60 seconds
    while true; do
      sleep 60
      curl -sf -X POST "${NERVE_CORD_URL}/larvae/${LARVA_NAME}/heartbeat" \
        -H "Authorization: Bearer ${NERVE_CORD_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"status\": \"alive\"}" > /dev/null 2>&1 || true
    done
  ) &
fi

# Hand off to OpenClaw gateway
exec openclaw "$@"
