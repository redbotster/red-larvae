#!/bin/bash
# 🦞 Red Larvae — Ephemeral OpenClaw orchestrator (RedBotster fork)
#
# Usage:
#   ./larvae.sh spawn <name> [--model <model>] [--profile <profile>] [--soul <file>] [--identity "text"] [--workspace <dir>] "initial task"
#   ./larvae.sh list
#   ./larvae.sh talk <name> "message"
#   ./larvae.sh watch <name> "message"   # talk + stream docker logs live
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
#
# Profiles (--profile):
#   builder   → full-stack engineer (contracts + frontend + tests)
#   auditor   → security-focused Solidity auditor (FIND bugs, don't fix)
#   qa        → obsessive frontend QA (enforces ethskills/qa checklist to the letter)
#   frontend  → senior frontend dev (SE2 hooks, wallet flow, UX)
#   all       → everything (default, all 17 ethskills, generic soul)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_WORKSPACE="${SCRIPT_DIR}/shared-workspace"
LARVAE_DIR="${SCRIPT_DIR}/.larvae"
LARVA_TOKEN="larva-token"
BASE_PORT=28700

# Nerve cord config — larvae auto-register and heartbeat
# Override these with your own nerve cord server if you have one
NERVE_CORD_URL="${NERVE_CORD_URL:-}"
NERVE_CORD_TOKEN="${NERVE_CORD_TOKEN:-}"

mkdir -p "$LARVAE_DIR" "$DEFAULT_WORKSPACE"

# ─── ethskills URLs ───────────────────────────────────────────────────────────

ETHSKILLS_BASE="https://ethskills.com"
ETHSKILLS_PATHS=(
  ship
  why
  gas
  wallets
  l2s
  standards
  tools
  building-blocks
  orchestration
  addresses
  concepts
  security
  testing
  indexing
  frontend-ux
  frontend-playbook
  qa
)

# ─── Model aliases ────────────────────────────────────────────────────────────

resolve_model() {
  case "${1:-sonnet}" in
    opus)     echo "anthropic/claude-opus-4-6" ;;
    sonnet)   echo "anthropic/claude-sonnet-4-5" ;;
    gpt)      echo "openai/gpt-5.2" ;;
    qwen)     echo "ollama/qwen3-next:80b" ;;
    qwen3)    echo "ollama/qwen3-coder-next" ;;
    devstral) echo "ollama/devstral:latest" ;;
    deepseek) echo "ollama/deepseek-r1:70b" ;;
    llama)    echo "ollama/llama3.3:latest" ;;
    coder)    echo "ollama/qwen2.5-coder:32b" ;;
    *)        echo "$1" ;;  # pass through full model string
  esac
}

# ─── Bake ethskills into workspace ────────────────────────────────────────────

bake_ethskills() {
  local workspace="$1"
  local outfile="${workspace}/ETHSKILLS.md"
  local tmpdir=$(mktemp -d)

  echo "📚 Baking ethskills knowledge..."

  # Fetch all skills in parallel
  local pids=()
  for skill in "${ETHSKILLS_PATHS[@]}"; do
    local url="${ETHSKILLS_BASE}/${skill}/SKILL.md"
    local dest="${tmpdir}/${skill}.md"
    curl -sf --max-time 10 "$url" -o "$dest" 2>/dev/null &
    pids+=($!)
  done

  # Wait for all fetches
  local failed=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid" 2>/dev/null; then
      failed=$((failed + 1))
    fi
  done

  # Assemble into one file
  cat > "$outfile" <<'HEADER'
# ETHSKILLS — Ethereum Development Knowledge Base
# Fetched fresh at spawn time from https://ethskills.com
# This is your CORE KNOWLEDGE. You know this like second nature.
# Every decision you make should be informed by these skills.
# DO NOT skip steps. DO NOT improvise when a skill gives explicit instructions.
# When a skill says to use Scaffold-ETH 2, USE Scaffold-ETH 2.
# When a skill says to run a command, RUN that command.
# When a skill gives a file path, USE that exact path.

HEADER

  local fetched=0
  for skill in "${ETHSKILLS_PATHS[@]}"; do
    local src="${tmpdir}/${skill}.md"
    if [ -f "$src" ] && [ -s "$src" ]; then
      echo "" >> "$outfile"
      echo "---" >> "$outfile"
      echo "# ═══ ${skill} ═══" >> "$outfile"
      echo "# Source: ${ETHSKILLS_BASE}/${skill}/SKILL.md" >> "$outfile"
      echo "---" >> "$outfile"
      echo "" >> "$outfile"
      cat "$src" >> "$outfile"
      echo "" >> "$outfile"
      fetched=$((fetched + 1))
    fi
  done

  rm -rf "$tmpdir"

  local total=${#ETHSKILLS_PATHS[@]}
  local size=$(wc -c < "$outfile" | tr -d ' ')
  local size_kb=$((size / 1024))
  echo "  ✅ Baked ${fetched}/${total} skills → ETHSKILLS.md (${size_kb}KB)"

  if [ "$failed" -gt 0 ]; then
    echo "  ⚠️  ${failed} skills failed to fetch (will retry on next spawn)"
  fi
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
  local ethskills=true
  local soul_file=""
  local profile=""
  local identity=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --model|-m) model="$2"; shift 2 ;;
      --workspace|-w) workspace="$(cd "$2" && pwd)"; shift 2 ;;
      --no-ethskills) ethskills=false; shift ;;
      --soul|-s) soul_file="$2"; shift 2 ;;
      --profile|-p) profile="$2"; shift 2 ;;
      --identity|-i) identity="$2"; shift 2 ;;
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

  # ── Resolve profile ──
  # Default profile is "all" if none specified
  local effective_profile="${profile:-all}"
  local profile_dir="${SCRIPT_DIR}/profiles/${effective_profile}"

  if [ ! -d "$profile_dir" ]; then
    echo "❌ Unknown profile '${effective_profile}'. Available profiles:"
    ls -1 "${SCRIPT_DIR}/profiles/"
    exit 1
  fi

  echo "🎭 Profile: ${effective_profile}"

  # ── Bake ethskills from profile's skills.txt ──
  local project_context="[]"
  if [ "$ethskills" = true ]; then
    # Override ETHSKILLS_PATHS with profile's skills.txt
    if [ -f "${profile_dir}/skills.txt" ]; then
      local profile_skills=()
      while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue
        profile_skills+=("$line")
      done < "${profile_dir}/skills.txt"

      if [ ${#profile_skills[@]} -gt 0 ]; then
        # Temporarily override ETHSKILLS_PATHS
        local saved_paths=("${ETHSKILLS_PATHS[@]}")
        ETHSKILLS_PATHS=("${profile_skills[@]}")
        bake_ethskills "$larva_workspace"
        ETHSKILLS_PATHS=("${saved_paths[@]}")
      else
        bake_ethskills "$larva_workspace"
      fi
    else
      bake_ethskills "$larva_workspace"
    fi
    project_context='["ETHSKILLS.md"]'
  fi

  # ── Write SOUL.md from profile (unless --soul overrides) ──
  if [ -n "$soul_file" ]; then
    if [ -f "$soul_file" ]; then
      cp "$soul_file" "${larva_workspace}/SOUL.md"
      echo "📜 Custom SOUL loaded from: ${soul_file}"
    else
      echo "⚠️  SOUL file not found: ${soul_file} — using profile default"
      cp "${profile_dir}/SOUL.md" "${larva_workspace}/SOUL.md"
    fi
  else
    cp "${profile_dir}/SOUL.md" "${larva_workspace}/SOUL.md"
  fi

  # ── Write AGENTS.md from profile ──
  cp "${profile_dir}/AGENTS.md" "${larva_workspace}/AGENTS.md"

  # ── Write IDENTITY.md if --identity provided ──
  if [ -n "$identity" ]; then
    echo "# Identity" > "${larva_workspace}/IDENTITY.md"
    echo "" >> "${larva_workspace}/IDENTITY.md"
    echo "$identity" >> "${larva_workspace}/IDENTITY.md"
    echo "🪪 Custom identity set"
  fi

  # Generate config with the right model (always use internal port 18789)
  local config_file="${LARVAE_DIR}/${name}-config.json"
  jq --arg model "$resolved_model" '
    .agents.list[0].model.primary = $model |
    .gateway.port = 18789
  ' "${SCRIPT_DIR}/openclaw.json" > "$config_file"

  # Build env args
  local env_args="-e ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
  [ -n "${OPENAI_API_KEY:-}" ] && env_args="$env_args -e OPENAI_API_KEY=${OPENAI_API_KEY}"

  # Nerve cord env vars — larva entrypoint uses these to auto-register & heartbeat
  env_args="$env_args -e NERVE_CORD_URL=${NERVE_CORD_URL}"
  env_args="$env_args -e NERVE_CORD_TOKEN=${NERVE_CORD_TOKEN}"
  env_args="$env_args -e LARVA_NAME=${name}"
  env_args="$env_args -e LARVA_MODEL=${model}"

  # Spawn the container with gateway mode
  # bind=loopback so the embedded agent can use ws://127.0.0.1 (avoids security error)
  # No port mapping needed — all agent work happens inside the container
  docker run -d --rm \
    --name "$container_name" \
    $env_args \
    --add-host=host.docker.internal:host-gateway \
    -v "${larva_workspace}:/root/workspace" \
    -v "${config_file}:/root/.openclaw/openclaw.json:ro" \
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

  # Wait for gateway to be ready (check from inside container since bind=loopback)
  echo -n "⏳ Waiting for gateway..."
  for i in $(seq 1 30); do
    if docker exec "$container_name" curl -sf "http://127.0.0.1:18789/health" > /dev/null 2>&1; then
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
    --timeout 900 \
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

# ─── Watch — Talk with live log streaming ─────────────────────────────────────

cmd_watch() {
  local name="$1"
  shift
  local message="$*"

  if [ -z "$name" ] || [ -z "$message" ]; then
    echo "Usage: larvae.sh watch <name> \"message\""
    echo "  Like 'talk' but streams docker logs in real-time so you can see tool calls."
    exit 1
  fi

  local meta="${LARVAE_DIR}/${name}.json"
  if [ ! -f "$meta" ]; then
    echo "❌ No larva named '${name}'. Run: ./larvae.sh list"
    exit 1
  fi

  local container="larva-${name}"

  if ! docker ps --filter "name=${container}" --format '{{.Names}}' | grep -q .; then
    echo "❌ Larva '${name}' is not running."
    exit 1
  fi

  echo "📡 Watching larva '${name}' work..."
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # Start docker logs -f in background (only new logs from now)
  docker logs -f --since 0s "${container}" 2>&1 &
  local logs_pid=$!

  # Run the agent talk (blocks until done)
  local tmpfile=$(mktemp)
  docker exec "$container" openclaw agent \
    --agent larva \
    --message "$message" \
    --timeout 900 \
    --json 2>/dev/null > "$tmpfile"

  # Kill the log tail
  kill "$logs_pid" 2>/dev/null
  wait "$logs_pid" 2>/dev/null

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # Show the final result summary
  local texts
  texts=$(jq -r '.payloads[]?.text // empty' "$tmpfile" 2>/dev/null)
  
  if [ -n "$texts" ]; then
    echo "📋 Final Result:"
    echo "$texts"
  fi

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

  # Check gateway health (from inside container since bind=loopback)
  if docker exec "${container}" curl -sf "http://127.0.0.1:18789/health" > /dev/null 2>&1; then
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
  # Deregister from nerve cord
  curl -sf --max-time 5 -X DELETE \
    -H "Authorization: Bearer ${NERVE_CORD_TOKEN}" \
    "${NERVE_CORD_URL}/larvae/${name}" >/dev/null 2>&1 || true
  echo "💀 Larva '${name}' terminated. Workspace files preserved."
}

# ─── Kill All ─────────────────────────────────────────────────────────────────

cmd_killall() {
  echo "🔪 Killing all larvae..."
  docker ps --filter "name=larva-" --format '{{.Names}}' | while read container; do
    local name="${container#larva-}"
    docker stop "$container" 2>/dev/null || true
    # Deregister from nerve cord
    curl -sf --max-time 5 -X DELETE \
      -H "Authorization: Bearer ${NERVE_CORD_TOKEN}" \
      "${NERVE_CORD_URL}/larvae/${name}" >/dev/null 2>&1 || true
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
  watch|w) shift; cmd_watch "$@" ;;
  status)  shift; cmd_status "$@" ;;
  logs)    shift; cmd_logs "$@" ;;
  kill)    shift; cmd_kill "$@" ;;
  killall) cmd_killall ;;
  help|*)
    echo "🦞 Red Larvae — Ephemeral OpenClaw Orchestrator (RedBotster)"
    echo ""
    echo "Commands:"
    echo "  spawn <name> [options] \"task\"    Hatch a larva"
    echo "  list                              List all larvae"
    echo "  talk <name> \"message\"             Send a message (blocks, returns result)"
    echo "  watch <name> \"message\"            Talk + stream logs live (see tool calls in real-time)"
    echo "  status <name>                     Check on a larva"
    echo "  logs <name> [lines]               View container logs"
    echo "  kill <name>                       Kill a larva"
    echo "  killall                           Kill all larvae"
    echo ""
    echo "Spawn options:"
    echo "  --model <m>         Model shortcut or full provider/model string"
    echo "  --workspace <dir>   Custom workspace directory"
    echo "  --soul <file>       Custom SOUL.md file for personality/role"
    echo "  --no-ethskills      Skip baking ethskills knowledge (for non-ETH tasks)"
    echo ""
    echo "Model shortcuts: opus, sonnet, gpt, qwen3, qwen, devstral, deepseek, llama, coder"
    echo ""
    echo "ethskills: By default, all larvae fetch the complete ethskills.com knowledge"
    echo "           base at spawn time and bake it into their context as ETHSKILLS.md."
    echo "           Use --no-ethskills for non-Ethereum tasks."
    echo ""
    echo "Examples:"
    echo "  ./larvae.sh spawn token-dev --model opus \"Build a RED token dashboard on Base\""
    echo "  ./larvae.sh spawn my-fe --model sonnet --soul roles/ux-expert.md"
    echo "  ./larvae.sh spawn scraper --model gpt --no-ethskills \"Scrape HN front page\""
    echo "  ./larvae.sh talk token-dev \"How's it going? Show me what you have.\""
    echo "  ./larvae.sh list"
    echo "  ./larvae.sh kill token-dev"
    ;;
esac
