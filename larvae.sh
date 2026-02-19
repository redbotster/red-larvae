#!/bin/bash
# 🦞 Larvae — Ephemeral OpenClaw orchestrator
#
# Usage:
#   ./larvae.sh spawn <name> [--model <model>] [--workspace <dir>] "initial task"
#   ./larvae.sh list
#   ./larvae.sh talk <name> "message"
#   ./larvae.sh status <name>
#   ./larvae.sh logs <name>
#   ./larvae.sh kill <name>
#   ./larvae.sh killall
#
# Models (shortcuts):
#   opus      → anthropic/claude-opus-4-6
#   sonnet    → anthropic/claude-sonnet-4-5
#   gpt       → openai/gpt-5.2
#   qwen      → ollama/qwen3-next:80b
#   devstral  → ollama/devstral:latest
#   deepseek  → ollama/deepseek-r1:70b
#   llama     → ollama/llama3.3:latest
#   coder     → ollama/qwen2.5-coder:32b

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_WORKSPACE="${SCRIPT_DIR}/shared-workspace"
LARVAE_DIR="${SCRIPT_DIR}/.larvae"
LARVA_TOKEN="larva-token"
BASE_PORT=28700

mkdir -p "$LARVAE_DIR" "$DEFAULT_WORKSPACE"

# ─── Model aliases ────────────────────────────────────────────────────────────

resolve_model() {
  case "${1:-sonnet}" in
    opus)     echo "anthropic/claude-opus-4-6" ;;
    sonnet)   echo "anthropic/claude-sonnet-4-5" ;;
    gpt)      echo "openai/gpt-5.2" ;;
    qwen)     echo "ollama/qwen3-next:80b" ;;
    devstral) echo "ollama/devstral:latest" ;;
    deepseek) echo "ollama/deepseek-r1:70b" ;;
    llama)    echo "ollama/llama3.3:latest" ;;
    coder)    echo "ollama/qwen2.5-coder:32b" ;;
    *)        echo "$1" ;;  # pass through full model string
  esac
}

# ─── Get next available port ──────────────────────────────────────────────────

next_port() {
  local port=$BASE_PORT
  while grep -rq "\"port\":.*$port" "$LARVAE_DIR"/ 2>/dev/null; do
    port=$((port + 1))
  done
  echo $port
}

# ─── Spawn ────────────────────────────────────────────────────────────────────

cmd_spawn() {
  local name=""
  local model="sonnet"
  local workspace="$DEFAULT_WORKSPACE"
  local task=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --model|-m) model="$2"; shift 2 ;;
      --workspace|-w) workspace="$(cd "$2" && pwd)"; shift 2 ;;
      *) 
        if [ -z "$name" ]; then
          name="$1"
        else
          task="$1"
        fi
        shift ;;
    esac
  done

  if [ -z "$name" ]; then
    echo "Usage: larvae.sh spawn <name> [--model <model>] [--workspace <dir>] \"task\""
    exit 1
  fi

  # Check if already running
  if docker ps --filter "name=larva-${name}" --format '{{.Names}}' | grep -q "larva-${name}"; then
    echo "❌ Larva '${name}' is already running. Kill it first or pick another name."
    exit 1
  fi

  local resolved_model=$(resolve_model "$model")
  local port=$(next_port)
  local container_name="larva-${name}"

  echo "🦞 Spawning larva: ${name}"
  echo "🧠 Model: ${resolved_model}"
  echo "📁 Workspace: ${workspace}"
  echo "🔌 Port: ${port}"

  # Create per-larva workspace subdir
  local larva_workspace="${workspace}/${name}"
  mkdir -p "$larva_workspace"

  # Generate config with the right model (always use internal port 18789)
  local config_file="${LARVAE_DIR}/${name}-config.json"
  jq --arg model "$resolved_model" '
    .agents.list[0].model.primary = $model |
    .gateway.port = 18789
  ' "${SCRIPT_DIR}/openclaw.json" > "$config_file"

  # Build env args
  local env_args="-e ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
  [ -n "${OPENAI_API_KEY:-}" ] && env_args="$env_args -e OPENAI_API_KEY=${OPENAI_API_KEY}"

  # Spawn the container with gateway mode
  # Maps host port → container internal port 18789
  docker run -d --rm \
    --name "$container_name" \
    $env_args \
    --add-host=host.docker.internal:host-gateway \
    -v "${larva_workspace}:/root/workspace" \
    -v "${config_file}:/root/.openclaw/openclaw.json:ro" \
    -p "${port}:18789" \
    larva \
    gateway --port 18789 > /dev/null

  # Save metadata
  cat > "${LARVAE_DIR}/${name}.json" <<EOF
{
  "name": "${name}",
  "container": "${container_name}",
  "model": "${resolved_model}",
  "model_alias": "${model}",
  "port": ${port},
  "workspace": "${larva_workspace}",
  "spawned_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "token": "${LARVA_TOKEN}"
}
EOF

  echo ""

  # Wait for gateway to be ready
  echo -n "⏳ Waiting for gateway..."
  for i in $(seq 1 30); do
    if curl -sf "http://localhost:${port}/health" > /dev/null 2>&1; then
      echo " ✅ Ready!"
      break
    fi
    sleep 1
    echo -n "."
  done

  # If there's an initial task, send it
  if [ -n "$task" ]; then
    echo ""
    echo "📋 Sending initial task..."
    cmd_talk "$name" "$task"
  fi

  echo ""
  echo "🦞 Larva '${name}' is alive on port ${port}"
  echo "   Talk: ./larvae.sh talk ${name} \"do something\""
  echo "   Logs: ./larvae.sh logs ${name}"
  echo "   Kill: ./larvae.sh kill ${name}"
}

# ─── Talk ─────────────────────────────────────────────────────────────────────

cmd_talk() {
  local name="$1"
  shift
  local message="$*"

  if [ -z "$name" ] || [ -z "$message" ]; then
    echo "Usage: larvae.sh talk <name> \"message\""
    exit 1
  fi

  local meta="${LARVAE_DIR}/${name}.json"
  if [ ! -f "$meta" ]; then
    echo "❌ No larva named '${name}'. Run: ./larvae.sh list"
    exit 1
  fi

  local container="larva-${name}"
  
  # Check container is running
  if ! docker ps --filter "name=${container}" --format '{{.Names}}' | grep -q .; then
    echo "❌ Larva '${name}' is not running."
    exit 1
  fi

  echo "📡 Talking to larva '${name}'..."
  echo ""

  # Use docker exec to run openclaw agent inside the container
  # It falls back to embedded mode which works perfectly
  # Capture stdout separately from stderr
  local tmpfile=$(mktemp)
  docker exec "$container" openclaw agent \
    --agent larva \
    --message "$message" \
    --json 2>/dev/null > "$tmpfile"

  # Extract the text payloads cleanly
  local texts
  texts=$(jq -r '.payloads[]?.text // empty' "$tmpfile" 2>/dev/null)
  
  if [ -n "$texts" ]; then
    echo "$texts"
  else
    # Fallback: show raw if JSON parsing fails
    cat "$tmpfile"
  fi
  
  # Show token usage summary
  local model=$(jq -r '.meta.agentMeta.model // "unknown"' "$tmpfile" 2>/dev/null)
  local duration=$(jq -r '.meta.durationMs // 0' "$tmpfile" 2>/dev/null)
  local total_tokens=$(jq -r '.meta.agentMeta.usage.total // 0' "$tmpfile" 2>/dev/null)
  echo ""
  echo "─── 🧠 ${model} · ${duration}ms · ${total_tokens} tokens ───"
  
  rm -f "$tmpfile"
}

# ─── Status ───────────────────────────────────────────────────────────────────

cmd_status() {
  local name="$1"
  local meta="${LARVAE_DIR}/${name}.json"
  
  if [ ! -f "$meta" ]; then
    echo "❌ No larva named '${name}'."
    exit 1
  fi

  local container="larva-${name}"
  local port=$(jq -r '.port' "$meta")
  local model=$(jq -r '.model' "$meta")
  local workspace=$(jq -r '.workspace' "$meta")
  local spawned=$(jq -r '.spawned_at' "$meta")

  echo "🦞 Larva: ${name}"
  echo "🧠 Model: ${model}"
  echo "📁 Workspace: ${workspace}"
  echo "🔌 Port: ${port}"
  echo "🕐 Spawned: ${spawned}"
  
  if docker ps --filter "name=${container}" --format '{{.Status}}' | head -1 | grep -q .; then
    local status=$(docker ps --filter "name=${container}" --format '{{.Status}}')
    echo "💚 Container: Running (${status})"
  else
    echo "💀 Container: Stopped"
  fi

  # Check gateway health
  if curl -sf "http://localhost:${port}/health" > /dev/null 2>&1; then
    echo "✅ Gateway: Healthy"
  else
    echo "❌ Gateway: Not responding"
  fi

  # Show workspace contents
  echo ""
  echo "📁 Workspace files:"
  ls -la "$workspace" 2>/dev/null | tail -n +4 || echo "  (empty)"
}

# ─── List ─────────────────────────────────────────────────────────────────────

cmd_list() {
  echo "🦞 Active Larvae"
  echo "═══════════════════════════════════════════════════════"
  
  local found=0
  for meta in "${LARVAE_DIR}"/*.json; do
    [ -f "$meta" ] || continue
    [[ "$meta" == *-config.json ]] && continue
    
    local name=$(jq -r '.name' "$meta")
    local model=$(jq -r '.model_alias // .model' "$meta")
    local port=$(jq -r '.port' "$meta")
    local container="larva-${name}"
    
    local status="💀 stopped"
    if docker ps --filter "name=${container}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
      status="💚 running"
    fi

    printf "  %-15s %-12s port:%-6s %s\n" "$name" "$model" "$port" "$status"
    found=1
  done

  if [ "$found" = "0" ]; then
    echo "  No larvae spawned. Run: ./larvae.sh spawn <name> --model <model> \"task\""
  fi
  echo ""
}

# ─── Logs ─────────────────────────────────────────────────────────────────────

cmd_logs() {
  local name="$1"
  local lines="${2:-50}"
  docker logs --tail "$lines" "larva-${name}" 2>&1
}

# ─── Kill ─────────────────────────────────────────────────────────────────────

cmd_kill() {
  local name="$1"
  echo "🔪 Killing larva '${name}'..."
  docker stop "larva-${name}" 2>/dev/null || true
  rm -f "${LARVAE_DIR}/${name}.json" "${LARVAE_DIR}/${name}-config.json"
  echo "💀 Larva '${name}' terminated. Workspace files preserved."
}

# ─── Kill All ─────────────────────────────────────────────────────────────────

cmd_killall() {
  echo "🔪 Killing all larvae..."
  docker ps --filter "name=larva-" --format '{{.Names}}' | while read container; do
    docker stop "$container" 2>/dev/null || true
    echo "  💀 ${container}"
  done
  rm -f "${LARVAE_DIR}"/*.json
  echo "All larvae terminated. Workspace files preserved."
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-help}" in
  spawn)   shift; cmd_spawn "$@" ;;
  list|ls) cmd_list ;;
  talk|t)  shift; cmd_talk "$@" ;;
  status)  shift; cmd_status "$@" ;;
  logs)    shift; cmd_logs "$@" ;;
  kill)    shift; cmd_kill "$@" ;;
  killall) cmd_killall ;;
  help|*)
    echo "🦞 Larvae — Ephemeral OpenClaw Orchestrator"
    echo ""
    echo "Commands:"
    echo "  spawn <name> [--model <m>] [--workspace <dir>] \"task\"  Hatch a larva"
    echo "  list                                                     List all larvae"
    echo "  talk <name> \"message\"                                    Send a message"
    echo "  status <name>                                            Check on a larva"
    echo "  logs <name> [lines]                                      View container logs"
    echo "  kill <name>                                              Kill a larva"
    echo "  killall                                                  Kill all larvae"
    echo ""
    echo "Model shortcuts: opus, sonnet, gpt, qwen, devstral, deepseek, llama, coder"
    echo ""
    echo "Examples:"
    echo "  ./larvae.sh spawn alice --model sonnet \"Build a React todo app\""
    echo "  ./larvae.sh spawn bob --model coder \"Write unit tests for the API\""
    echo "  ./larvae.sh talk alice \"How's it going? Show me what you have so far.\""
    echo "  ./larvae.sh list"
    echo "  ./larvae.sh kill alice"
    ;;
esac
