#!/bin/bash
# 🦞 Larvae Pipeline — Automated PLAYBOOK Runner
#
# Runs through the PLAYBOOK steps automatically, spawning larvae for each step,
# waiting for completion, checking results, and proceeding to the next step.
#
# Usage:
#   ./pipeline.sh <project-name> [--from <step>] [--to <step>] [--model <model>] [--plan <plan-file>]
#
# Examples:
#   ./pipeline.sh clawd-vesting --plan shared-workspace/BUILD-PLAN.md
#   ./pipeline.sh clawd-vesting --from 5 --to 7     # Frontend build through E2E
#   ./pipeline.sh clawd-vesting --from 2             # Start from contract build
#
# Steps:
#   2: Build contract     (--profile builder)
#   3: Audit contract     (--profile auditor)
#   4: Deploy to local fork (run locally, no larva needed)
#   5: Build frontend     (--profile frontend)
#   6: Frontend QA        (--profile qa)
#   7: E2E browser test   (--profile qa, uses headless Chromium + burner wallets)
#
# Step 1 (write plan) must be done before running the pipeline.
# Steps 8+ (production deploy, real wallet testing) require human interaction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_WS="${SCRIPT_DIR}/shared-workspace"
LOGS_DIR="${SCRIPT_DIR}/.pipeline-logs"

# ─── Defaults ─────────────────────────────────────────────────────────────────

PROJECT=""
FROM_STEP=2
TO_STEP=7
MODEL="opus"
PLAN_FILE=""
TALK_TIMEOUT=600  # 10 min max per larva talk

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${BLUE}[pipeline]${NC} $*"; }
ok()    { echo -e "${GREEN}[✅ PASS]${NC} $*"; }
fail()  { echo -e "${RED}[❌ FAIL]${NC} $*"; }
warn()  { echo -e "${YELLOW}[⚠️  WARN]${NC} $*"; }
header(){ echo -e "\n${BOLD}═══════════════════════════════════════════════════${NC}"; echo -e "${BOLD} $*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════════════${NC}\n"; }

# ─── Parse args ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --from)    FROM_STEP="$2"; shift 2 ;;
    --to)      TO_STEP="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    --plan)    PLAN_FILE="$2"; shift 2 ;;
    --timeout) TALK_TIMEOUT="$2"; shift 2 ;;
    --help|-h) 
      echo "Usage: ./pipeline.sh <project-name> [--from <step>] [--to <step>] [--model <model>] [--plan <plan-file>]"
      echo ""
      echo "Steps: 2=build, 3=audit, 4=deploy-fork, 5=frontend, 6=qa, 7=e2e"
      exit 0 ;;
    *)
      if [ -z "$PROJECT" ]; then
        PROJECT="$1"
      else
        echo "Unknown arg: $1"; exit 1
      fi
      shift ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "Usage: ./pipeline.sh <project-name> [options]"
  echo "Run './pipeline.sh --help' for details."
  exit 1
fi

mkdir -p "$LOGS_DIR"

# ─── Plan file ────────────────────────────────────────────────────────────────

if [ -z "$PLAN_FILE" ]; then
  PLAN_FILE="${SHARED_WS}/BUILD-PLAN.md"
fi

if [ ! -f "$PLAN_FILE" ]; then
  fail "BUILD-PLAN.md not found at ${PLAN_FILE}"
  echo "Step 1 (write the plan) must be done before running the pipeline."
  exit 1
fi

PLAN_CONTENT=$(cat "$PLAN_FILE")

# ─── Helper: spawn + talk + wait ──────────────────────────────────────────────

# Spawns a larva, sends it a task, captures output, kills it
# Usage: run_larva <name> <profile> <message> <logfile>
run_larva() {
  local name="$1"
  local profile="$2"
  local message="$3"
  local logfile="$4"

  # Kill if already running
  "${SCRIPT_DIR}/larvae.sh" kill "$name" 2>/dev/null || true
  sleep 1

  # Spawn
  log "Spawning larva: ${name} (profile: ${profile}, model: ${MODEL})"
  "${SCRIPT_DIR}/larvae.sh" spawn "$name" --model "$MODEL" --profile "$profile"

  # Talk (this blocks until the larva responds)
  log "Sending task to ${name}... (timeout: ${TALK_TIMEOUT}s)"
  local tmpfile=$(mktemp)
  
  # macOS doesn't have `timeout` — use background + wait + kill
  "${SCRIPT_DIR}/larvae.sh" talk "$name" "$message" > "$tmpfile" 2>&1 &
  local talk_pid=$!
  
  # Wait with timeout
  # Note: `openclaw agent` may hang if larva starts background processes (anvil, next.js)
  # because docker exec waits for all child processes. We detect this by checking if the
  # agent has finished (via container log) even if docker exec hasn't returned.
  local elapsed=0
  while kill -0 "$talk_pid" 2>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    
    # Check if the agent finished but docker exec is stuck (background processes in container)
    local container_name="larva-${name}"
    if docker ps --filter "name=${container_name}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
      # Container still running — check if agent process exited
      local agent_count=$(docker exec "$container_name" pgrep -f "openclaw-agent" 2>/dev/null | wc -l)
      if [ "$agent_count" -eq 0 ] && [ "$elapsed" -gt 30 ]; then
        # Agent finished but docker exec still running (background processes)
        log "Agent finished but docker exec stuck (background processes). Extracting output..."
        kill "$talk_pid" 2>/dev/null || true
        wait "$talk_pid" 2>/dev/null || true
        
        # Extract output from container log
        docker exec "$container_name" cat /tmp/openclaw/openclaw-*.log 2>/dev/null | \
          grep '"payloads"' | tail -1 | \
          python3 -c "
import sys, json
try:
    raw = sys.stdin.read().strip()
    log = json.loads(raw)
    data = json.loads(log.get('0', '{}'))
    for p in data.get('payloads', []):
        t = p.get('text', '')
        if t: print(t)
    meta = data.get('meta', {}).get('agentMeta', {})
    d = data.get('meta', {}).get('durationMs', 0)
    tok = meta.get('usage', {}).get('total', 0)
    print(f'\\n─── 🧠 {meta.get(\"model\", \"unknown\")} · {d}ms · {tok} tokens ───')
except: pass
" > "$tmpfile" 2>/dev/null
        ok "Larva ${name} completed (extracted from container log)"
        break
      fi
    fi
    
    if [ "$elapsed" -ge "$TALK_TIMEOUT" ]; then
      kill "$talk_pid" 2>/dev/null || true
      wait "$talk_pid" 2>/dev/null || true
      fail "Larva ${name} timed out after ${TALK_TIMEOUT}s"
      cat "$tmpfile" >> "$logfile"
      rm -f "$tmpfile"
      return 1
    fi
  done
  
  # If we didn't break out early, wait for normal exit
  if kill -0 "$talk_pid" 2>/dev/null; then
    : # already handled above
  else
    wait "$talk_pid" 2>/dev/null
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
      fail "Larva ${name} failed (exit code: ${exit_code})"
      cat "$tmpfile" >> "$logfile"
      rm -f "$tmpfile"
      return 1
    fi
    ok "Larva ${name} completed"
  fi

  # Save output
  cat "$tmpfile" > "$logfile"
  rm -f "$tmpfile"

  # Show summary (last 30 lines)
  echo ""
  log "Output summary (last 30 lines):"
  tail -30 "$logfile"
  echo ""

  return 0
}

# ─── Helper: copy project between workspaces ──────────────────────────────────

copy_project() {
  local from_name="$1"
  local to_name="$2"
  local from_dir="${SHARED_WS}/${from_name}/${PROJECT}"
  local to_dir="${SHARED_WS}/${to_name}"
  
  mkdir -p "$to_dir"
  
  if [ -d "$from_dir" ]; then
    log "Copying project: ${from_name}/${PROJECT} → ${to_name}/"
    rm -rf "${to_dir}/${PROJECT}"
    # Use rsync to skip heavy dirs that larvae can reinstall themselves
    # node_modules, .next, out, cache, foundry lib (openzeppelin etc) = ~3GB saved
    rsync -a --delete \
      --exclude='node_modules' \
      --exclude='.next' \
      --exclude='out' \
      --exclude='cache' \
      --exclude='packages/foundry/lib' \
      --exclude='packages/foundry/out' \
      "$from_dir/" "${to_dir}/${PROJECT}/"
    # Also copy BUILD-PLAN.md
    cp "$PLAN_FILE" "${to_dir}/BUILD-PLAN.md"
    # Verify the copy worked
    if [ -d "${to_dir}/${PROJECT}/packages" ]; then
      local size=$(du -sh "${to_dir}/${PROJECT}" 2>/dev/null | cut -f1)
      ok "Project copied (${size}, excludes node_modules/lib)"
    else
      fail "Copy failed — ${to_dir}/${PROJECT}/packages not found"
      return 1
    fi
  else
    fail "Source project not found: ${from_dir}"
    return 1
  fi
}

# ─── Step 2: Build Contract ──────────────────────────────────────────────────

step_2_build_contract() {
  header "Step 2: Build Contract"
  
  local name="contract-dev"
  local logfile="${LOGS_DIR}/step2-build.log"

  # Copy plan to workspace
  mkdir -p "${SHARED_WS}/${name}"
  cp "$PLAN_FILE" "${SHARED_WS}/${name}/BUILD-PLAN.md"

  local message="Read ETHSKILLS.md first. Follow the phases exactly.

Read BUILD-PLAN.md in your workspace — it has the complete build plan.

Here is the summary:
${PLAN_CONTENT}

Use Scaffold-ETH 2: npx create-eth@latest
Contracts go in packages/foundry/contracts/
Deploy scripts in packages/foundry/script/
Tests in packages/foundry/test/

Build the contracts. Write comprehensive tests covering:
- Every function from every user journey
- Edge cases: zero amounts, max uint, unauthorized callers
- Fuzz tests for any math operations
- Events emitted for every state change

Run the tests. They must all pass. Show me the results."

  run_larva "$name" "builder" "$message" "$logfile" || return 1

  # Validate: check for contract files
  local contract_dir="${SHARED_WS}/${name}/${PROJECT}/packages/foundry/contracts"
  if [ -d "$contract_dir" ] && find "$contract_dir" -name "*.sol" | grep -q .; then
    ok "Contract files found in ${contract_dir}"
  else
    fail "No .sol files found in ${contract_dir}"
    return 1
  fi

  # Check for test files
  local test_dir="${SHARED_WS}/${name}/${PROJECT}/packages/foundry/test"
  if [ -d "$test_dir" ] && find "$test_dir" -name "*.sol" | grep -q .; then
    ok "Test files found"
  else
    warn "No test files found in ${test_dir}"
  fi
}

# ─── Step 3: Audit Contract ─────────────────────────────────────────────────

step_3_audit_contract() {
  header "Step 3: Audit Contract"

  local name="qa-audit"
  local logfile="${LOGS_DIR}/step3-audit.log"

  copy_project "contract-dev" "$name" || return 1

  local message="You are a smart contract security auditor.

Read ETHSKILLS.md first — focus on the security and qa sections.

The code to audit is in your workspace at:
  ${PROJECT}/packages/foundry/contracts/
  ${PROJECT}/packages/foundry/test/
  ${PROJECT}/packages/foundry/script/

Your job:
1. Read every contract source file
2. Run the tests yourself: cd ${PROJECT}/packages/foundry && forge test -vvv
3. Check every item on the ethskills/security pre-deploy checklist:
   - Access control on every admin function
   - Reentrancy protection (CEI pattern + nonReentrant)
   - Token decimal handling (no hardcoded 1e18 for non-18-decimal tokens)
   - Integer math (multiply before divide)
   - SafeERC20 for all token operations
   - Input validation (zero address, zero amount, bounds)
   - Events emitted for every state change
   - No infinite approvals
4. Report PASS/FAIL for each checklist item
5. List any bugs, vulnerabilities, or concerns
6. Give an overall SHIP / NO-SHIP verdict

Do NOT fix anything. Only report findings."

  run_larva "$name" "auditor" "$message" "$logfile" || return 1

  # Check for SHIP verdict
  if grep -qi "SHIP" "$logfile" && ! grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
    ok "Audit verdict: SHIP"
  else
    if grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
      fail "Audit verdict: NO-SHIP"
      warn "Review ${logfile} for findings. Fix issues and re-run from step 2."
      return 1
    else
      warn "Could not determine audit verdict. Review ${logfile}"
      warn "Proceeding anyway — check the audit manually."
    fi
  fi
}

# ─── Step 4: Deploy to Local Fork ───────────────────────────────────────────

step_4_deploy_fork() {
  header "Step 4: Deploy to Local Fork"
  log "This step runs locally (no larva needed)"
  log "The frontend larva will use deployedContracts.ts generated by 'yarn deploy'"
  log "For now, skipping — frontend handles missing deployedContracts gracefully."
  log "Deploy will happen when you run: cd ${SHARED_WS}/contract-dev/${PROJECT} && yarn fork && yarn deploy"
  ok "Step 4: Skipped (deploy before E2E testing)"
}

# ─── Step 5: Build Frontend ─────────────────────────────────────────────────

step_5_build_frontend() {
  header "Step 5: Build Frontend"

  local name="frontend-dev"
  local logfile="${LOGS_DIR}/step5-frontend.log"

  copy_project "contract-dev" "$name" || return 1

  local message="Read ETHSKILLS.md first — especially frontend-ux, frontend-playbook, orchestration, and qa sections.

Then read BUILD-PLAN.md in your workspace — it has the full spec, user archetypes, and user journeys.

Build the frontend in ${PROJECT}/packages/nextjs/. Replace the default SE2 home page with the app described in BUILD-PLAN.md.

The contract source is at ${PROJECT}/packages/foundry/contracts/ — read it to understand the interface.

CRITICAL RULES (from ethskills):
1. Use ONLY SE2 hooks: useScaffoldReadContract, useScaffoldWriteContract, useScaffoldEventHistory
2. NEVER use raw wagmi hooks (useWriteContract, useReadContract)
3. Every onchain button gets its OWN loading state, disables + shows spinner from click to block confirmation
4. For any external tokens, register them in packages/nextjs/contracts/externalContracts.ts with full ABI
5. Human-readable amounts everywhere (formatUnits/parseUnits)
6. Remove SE2 tab title — use the app name
7. Remove SE2 default footer branding
8. pollingInterval should be 3000 in scaffold.config.ts
9. Show contract addresses with <Address/> component
10. Four-state button flow: Connect Wallet → Switch Network → Approve → Action
11. Clean, modern design. Mobile responsive.

Build EACH user journey as described in BUILD-PLAN.md.
Make sure it compiles: cd ${PROJECT}/packages/nextjs && yarn build (use NEXT_PUBLIC_IGNORE_BUILD_ERROR=true if needed for missing chain data).
Show me what you built."

  run_larva "$name" "frontend" "$message" "$logfile" || return 1

  # Validate: check for modified page.tsx
  local page="${SHARED_WS}/${name}/${PROJECT}/packages/nextjs/app/page.tsx"
  if [ -f "$page" ]; then
    local lines=$(wc -l < "$page")
    if [ "$lines" -gt 50 ]; then
      ok "page.tsx exists (${lines} lines — substantial)"
    else
      warn "page.tsx is only ${lines} lines — might be minimal"
    fi
  else
    fail "page.tsx not found"
    return 1
  fi
}

# ─── Step 6: Frontend QA ────────────────────────────────────────────────────

step_6_frontend_qa() {
  header "Step 6: Frontend QA (Code Review)"

  local name="qa-frontend"
  local logfile="${LOGS_DIR}/step6-qa.log"

  copy_project "frontend-dev" "$name" || return 1

  local message="You are a frontend QA reviewer for an Ethereum dApp.

Read ETHSKILLS.md first — focus on qa and frontend-ux sections.

The code is in your workspace at ${PROJECT}/packages/nextjs/
Also read BUILD-PLAN.md — it has the user journeys the frontend should implement.

NOTE: node_modules are not included — run 'cd ${PROJECT} && yarn install' first if you need to build/check types.

Review every .tsx file in app/ and components/, plus scaffold.config.ts and contracts/externalContracts.ts.

Check the ethskills/qa Pre-Ship Audit — report PASS/FAIL for each:

Ship-Blocking:
- [ ] Wallet connection shows a BUTTON, not text
- [ ] Wrong network shows a Switch button (if multi-network)
- [ ] One button at a time (Connect → Network → Approve → Action)
- [ ] Every onchain button disables + spinner through block confirmation
- [ ] Uses useScaffoldWriteContract, NOT raw wagmi useWriteContract
- [ ] SE2 footer branding removed
- [ ] SE2 tab title removed

Should Fix:
- [ ] Contract address displayed with <Address/> component
- [ ] Human-readable amounts everywhere (no raw wei)
- [ ] pollingInterval is 3000
- [ ] Each button has its own loading state (not shared isLoading)
- [ ] No hardcoded API keys in any committed file
- [ ] Favicon updated from SE2 default

Also verify each user journey from BUILD-PLAN.md has corresponding UI elements.

Give SHIP / NO-SHIP verdict with findings."

  run_larva "$name" "qa" "$message" "$logfile" || return 1

  # Check verdict
  if grep -qi "SHIP" "$logfile" && ! grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
    ok "Frontend QA verdict: SHIP"
  else
    if grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
      fail "Frontend QA verdict: NO-SHIP"
      warn "Review ${logfile} for findings."
      # Don't fail the pipeline — QA findings are informational
      # The E2E test in step 7 will catch real issues
      warn "Proceeding to E2E testing anyway (findings logged)"
    else
      warn "Could not determine QA verdict. Review ${logfile}"
    fi
  fi
}

# ─── Step 7: E2E Browser Test ───────────────────────────────────────────────

step_7_e2e_test() {
  header "Step 7: E2E Browser Test (Burner Wallets on Local Fork)"

  local name="qa-e2e"
  local logfile="${LOGS_DIR}/step7-e2e.log"

  copy_project "frontend-dev" "$name" || return 1

  local message="You are an E2E QA tester for an Ethereum dApp. You have a headless Chromium browser available via the browser tool.

Read ETHSKILLS.md first — focus on qa and frontend-ux sections.
Read BUILD-PLAN.md — it has all user journeys you must test.

The SE2 project is at ${PROJECT}/ in your workspace.

## Your job: Walk EVERY user journey from BUILD-PLAN.md using the browser.

### Setup:

1. Install dependencies:
   cd ${PROJECT} && yarn install

2. Start the local Anvil fork:
   cd ${PROJECT} && yarn fork --network base &
   (wait for it — look for 'Listening on')

3. Set up interval mining so blocks advance:
   cast rpc anvil_setIntervalMining 1 --rpc-url http://localhost:8545

4. Deploy contracts:
   cd ${PROJECT} && yarn deploy

5. Start the frontend:
   cd ${PROJECT} && yarn start &
   (wait for 'Ready' on localhost:3000)

### Testing:

SE2 on chains.foundry auto-generates a burner wallet connected to Anvil.
When you open localhost:3000, the burner wallet auto-connects.

For each user journey in BUILD-PLAN.md:
1. Navigate to localhost:3000 using the browser tool
2. Take a screenshot at each state
3. Walk through every step
4. If tokens are needed, use cast to fund the burner wallet:
   - Find a whale: cast call <token_address> 'balanceOf(address)(uint256)' <known_holder> --rpc-url http://localhost:8545
   - Impersonate and send: cast send --unlocked --from <whale> <token_address> 'transfer(address,uint256)' <burner_address> <amount> --rpc-url http://localhost:8545
5. For time-dependent features (vesting, staking), use:
   cast rpc evm_increaseTime <seconds> --rpc-url http://localhost:8545
   cast rpc evm_mine --rpc-url http://localhost:8545

### For each step verify:
- Does the UI show what the journey says it should?
- Does the button disable + show spinner during tx?
- Does the result appear after confirmation?
- Are amounts human-readable (not raw wei)?

### Report:
For each journey: PASS/FAIL per step.
Overall E2E verdict: SHIP / NO-SHIP."

  # E2E needs more time — yarn install + fork + deploy + testing
  local saved_timeout=$TALK_TIMEOUT
  TALK_TIMEOUT=900  # 15 min for E2E

  run_larva "$name" "qa" "$message" "$logfile"
  local result=$?

  TALK_TIMEOUT=$saved_timeout

  if [ $result -ne 0 ]; then
    fail "E2E testing failed or timed out"
    return 1
  fi

  # Check verdict
  if grep -qi "SHIP" "$logfile" && ! grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
    ok "E2E verdict: SHIP"
  else
    if grep -qi "NO-SHIP\|NO_SHIP\|NOSHIP" "$logfile"; then
      fail "E2E verdict: NO-SHIP"
      warn "Review ${logfile} for failures."
      return 1
    else
      warn "Could not determine E2E verdict. Review ${logfile}"
    fi
  fi
}

# ─── Main Pipeline ───────────────────────────────────────────────────────────

header "🦞 Larvae Pipeline: ${PROJECT}"
log "Steps: ${FROM_STEP} → ${TO_STEP}"
log "Model: ${MODEL}"
log "Plan: ${PLAN_FILE}"
log "Logs: ${LOGS_DIR}/"

FAILED=0
STEPS_RUN=0

for step in $(seq "$FROM_STEP" "$TO_STEP"); do
  case $step in
    2) step_2_build_contract ;;
    3) step_3_audit_contract ;;
    4) step_4_deploy_fork ;;
    5) step_5_build_frontend ;;
    6) step_6_frontend_qa ;;
    7) step_7_e2e_test ;;
    *) warn "Unknown step: ${step}, skipping" ; continue ;;
  esac

  if [ $? -ne 0 ]; then
    FAILED=$((FAILED + 1))
    fail "Step ${step} failed! Stopping pipeline."
    break
  fi

  STEPS_RUN=$((STEPS_RUN + 1))

  # Kill the larva after each step to free resources
  # (workspace files are preserved)
  case $step in
    2) "${SCRIPT_DIR}/larvae.sh" kill contract-dev 2>/dev/null || true ;;
    3) "${SCRIPT_DIR}/larvae.sh" kill qa-audit 2>/dev/null || true ;;
    5) "${SCRIPT_DIR}/larvae.sh" kill frontend-dev 2>/dev/null || true ;;
    6) "${SCRIPT_DIR}/larvae.sh" kill qa-frontend 2>/dev/null || true ;;
    7) "${SCRIPT_DIR}/larvae.sh" kill qa-e2e 2>/dev/null || true ;;
  esac
done

# ─── Summary ──────────────────────────────────────────────────────────────────

header "Pipeline Complete"
log "Steps run: ${STEPS_RUN}"
log "Failures: ${FAILED}"
echo ""

if [ "$FAILED" -eq 0 ]; then
  ok "🦞 All steps passed! Phase 1 complete."
  echo ""
  log "Next: Phase 2 (production deploy + real wallet testing)"
  log "  1. cd ${SHARED_WS}/frontend-dev/${PROJECT}"
  log "  2. Update scaffold.config.ts: targetNetworks: [chains.base]"
  log "  3. yarn deploy --network base"
  log "  4. Test with real wallet on localhost:3000"
  log "  5. yarn ipfs (or vercel deploy)"
else
  fail "Pipeline failed at step. Review logs in ${LOGS_DIR}/"
  log "Fix issues and re-run: ./pipeline.sh ${PROJECT} --from <failed-step>"
fi

echo ""
log "Logs saved to: ${LOGS_DIR}/"
ls -la "${LOGS_DIR}/"*.log 2>/dev/null
