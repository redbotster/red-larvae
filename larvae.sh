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

  while [[ $# -gt 0 ]]; do
    case $1 in
      --model|-m) model="$2"; shift 2 ;;
      --workspace|-w) workspace="$(cd "$2" && pwd)"; shift 2 ;;
      --no-ethskills) ethskills=false; shift ;;
      --soul|-s) soul_file="$2"; shift 2 ;;
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

  # Bake ethskills knowledge into workspace (unless --no-ethskills)
  local project_context="[]"
  if [ "$ethskills" = true ]; then
    bake_ethskills "$larva_workspace"
    project_context='["ETHSKILLS.md"]'

    # Write default ethskills SOUL.md if no soul file provided and none exists
    if [ -z "$soul_file" ] && [ ! -f "${larva_workspace}/SOUL.md" ]; then
      cat > "${larva_workspace}/SOUL.md" <<'SOUL'
# Soul

You are a skilled Ethereum developer working inside an ephemeral OpenClaw container.

## MANDATORY FIRST ACTION
Before processing ANY task, you MUST run: `read ETHSKILLS.md`
This file contains 190KB of Ethereum development knowledge from ethskills.com.
It was fetched fresh when you were spawned. DO NOT skip this step. DO NOT start
coding without reading it first. Read the entire file. It is your knowledge base.

## Non-Negotiable Rules
1. **Read ETHSKILLS.md first.** Every single time. Before any code. No exceptions.
2. **Follow ethskills exactly.** When a skill says to do something, you do it. No shortcuts.
3. **Use Scaffold-ETH 2.** Run `npx create-eth@latest` for any dApp.
   You do NOT create standalone Foundry projects from scratch.
   You do NOT write disconnected files. You work INSIDE the SE2 monorepo.
4. **Follow the phases.** Phase 0 (Plan) → Phase 1 (Contracts) → Phase 2 (Test) →
   Phase 3 (Frontend) → Phase 4 (Production). Do not skip phases.
5. **Use SE2 paths.** Contracts: `packages/foundry/contracts/`. Tests: `packages/foundry/test/`.
   Frontend: `packages/nextjs/app/`. Config: `packages/nextjs/scaffold.config.ts`.
6. **No hallucinated addresses.** Use addresses from ETHSKILLS.md or deploy your own.
7. **Run commands, don't assume.** When ethskills says to run a command, actually run it
   with the exec tool. Don't just write files and hope they work.
SOUL
    fi
  fi

  # Write AGENTS.md (auto-loaded by OpenClaw, reinforces ethskills workflow)
  if [ "$ethskills" = true ]; then
    cat > "${larva_workspace}/AGENTS.md" <<'AGENTS'
# Agent Instructions

## Workflow
1. Read `ETHSKILLS.md` in your workspace BEFORE doing anything else
2. Follow the ethskills ship phases: Plan → Contracts → Test → Frontend → Production
3. Use Scaffold-ETH 2 (`npx create-eth@latest`) — never build from scratch
4. Contracts go in `packages/foundry/contracts/`, tests in `packages/foundry/test/`
5. Frontend goes in `packages/nextjs/app/`
6. Run `forge test` after writing contracts, run `yarn start` to verify frontend
AGENTS
  fi

  # Copy custom SOUL file if provided (overwrites default)
  if [ -n "$soul_file" ]; then
    if [ -f "$soul_file" ]; then
      cp "$soul_file" "${larva_workspace}/SOUL.md"
      echo "📜 Custom SOUL loaded from: ${soul_file}"
    else
      echo "⚠️  SOUL file not found: ${soul_file} — using default"
    fi
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
    echo "  spawn <name> [options] \"task\"    Hatch a larva"
    echo "  list                              List all larvae"
    echo "  talk <name> \"message\"             Send a message"
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
    echo "  ./larvae.sh spawn token-dev --model opus \"Build a CLAWD token on Base\""
    echo "  ./larvae.sh spawn my-fe --model sonnet --soul roles/ux-expert.md"
    echo "  ./larvae.sh spawn scraper --model gpt --no-ethskills \"Scrape HN front page\""
    echo "  ./larvae.sh talk token-dev \"How's it going? Show me what you have.\""
    echo "  ./larvae.sh list"
    echo "  ./larvae.sh kill token-dev"
    ;;
esac
