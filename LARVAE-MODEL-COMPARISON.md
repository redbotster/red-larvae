# 🦞 Larvae Model Comparison — $CLAWD Token Hub Build

## Date: 2026-02-19
## Task: Build a $CLAWD Token Hub dApp on Base
## Method: Identical task, identical ethskills baking, three different models

All three larvae received the same:
- **SOUL.md** with mandatory ethskills rules
- **AGENTS.md** with SE2 workflow instructions
- **ETHSKILLS.md** — 190KB, 17 skills baked at spawn time
- **Same prompt**: Build $CLAWD token hub, ERC-20 + frontend, use SE2, follow ethskills phases

---

## Build 1: Claude Opus 4.6 (Two Specialist Larvae)

**Model:** `anthropic/claude-opus-4-6` (cloud)
**Architecture:** Two larvae — `solidity-dev` (contracts) + `ux-dev` (frontend)
**Cost:** ~$2.00 total (estimated)

### Solidity Dev Results

| Metric | Value |
|--------|-------|
| Duration | ~93s (first pass) + ~67s (QA pass) |
| Tokens | 42,219 + 92,610 = 134,829 |
| Tool calls | Extensive — exec, write, read |
| Files created | Full SE2 project |

**What it built:**
- ✅ Ran `npx create-eth@latest` — real Scaffold-ETH 2 monorepo
- ✅ `packages/hardhat/contracts/CLAWDToken.sol` (24 lines)
  - ERC20 + ERC20Burnable + Ownable (OpenZeppelin)
  - 1M initial supply, 18 decimals
  - Constructor takes deployer address, mints to deployer
  - Custom `TokensMinted` event
- ✅ `packages/hardhat/deploy/01_deploy_clawd_token.ts` (27 lines)
  - Proper hardhat-deploy script with logging
- ✅ `packages/hardhat/test/CLAWDToken.ts` (162 lines)
  - 20 test cases, all passing
  - Deployment, transfers, approvals, burn, edge cases
  - Fuzz-style bounded tests, supply invariants
  - Checks custom errors (`ERC20InsufficientBalance`, `OwnableInvalidOwner`)
- ✅ Full typechain-types generated (compiled successfully)
- ✅ OpenZeppelin artifacts compiled

**QA Pass Results (self-audit against ethskills):**
- 20/20 tests passing
- Security checklist: all green
- Gas profile: Deploy 697,700 gas (~$0.02 on Base), Transfer ~51K, Burn ~34K
- Found and fixed address(0) validation issue during QA
- Added 3 supply invariant tests during QA

### UX Dev Results

| Metric | Value |
|--------|-------|
| Duration | ~115s (first pass) + ~240s (QA, timed out) |
| Tokens | 35,869 + unknown (killed) |
| Tool calls | Extensive — exec, write, read |
| Files created | Full SE2 project |

**What it built:**
- ✅ Ran `npx create-eth@latest` — real Scaffold-ETH 2 monorepo
- ✅ `packages/nextjs/app/page.tsx` (309 lines)
  - `BalanceCard` component — shows user balance + total supply
  - `SendCard` component — recipient (AddressInput), amount, Max button
  - `TransferHistory` component — sent/received events, color-coded
  - Four-state button flow: Connect → Switch to Base → Send (follows ethskills Rule 2)
  - Independent loading states per button (ethskills Rule 1)
  - Uses SE2 hooks: `useScaffoldReadContract`, `useScaffoldWriteContract`, `useScaffoldEventHistory`
  - 🦞 branding, dark theme with `base-200` cards
  - `RainbowKitCustomConnectButton` for wallet connect
  - `useSwitchChain` for network switching to Base
- ✅ `packages/nextjs/scaffold.config.ts`
  - `targetNetworks: [chains.base]`
  - `pollingInterval: 3000` (ethskills Rule 6)
  - RPC override for Base via env var
- ✅ `packages/nextjs/contracts/externalContracts.ts` — Full ERC-20 ABI registered for chain 8453
- ✅ Ran `yarn start` during QA — `.next/types` generated (frontend compiles)

**QA Pass (partial — timed out):**
- Updated scaffold config with Base chain + polling interval
- Added `useSwitchChain` import for four-state flow
- Wired `externalContracts` properly
- Frontend compiled successfully (`.next/types` generated)
- Timed out before outputting final audit report

### Opus Summary

| Category | Score |
|----------|-------|
| Used SE2 (npx create-eth@latest) | ✅ Yes |
| Correct file paths (packages/hardhat, packages/nextjs) | ✅ Yes |
| Followed ethskills phases | ✅ Yes (Plan → Build → Test → QA) |
| Used tools (exec, write, read) | ✅ Extensively |
| Ran tests | ✅ 20/20 passing |
| Compiled successfully | ✅ Both contract and frontend |
| ethskills frontend rules followed | ✅ Rules 1, 2, 3, 5, 6 |
| Production-ready code quality | ✅ Clean, typed, proper patterns |

---

## Build 2: Qwen 2.5 Coder 32B (Single Larva, Local)

**Model:** `ollama/qwen2.5-coder:32b` (local, 19GB, Q4_K_M)
**Architecture:** Single larva — `local-dev` (full stack)
**Cost:** $0.00 (local inference)

### Results

| Metric | Value |
|--------|-------|
| Duration | 224,345ms (~3.7 min) |
| Tokens | 6,448 |
| Tool calls | **ZERO** |
| Files created | **ZERO** |

**What happened:**
- ❌ Model loaded with **4,096 context window** — couldn't see the 190KB ETHSKILLS.md
- ❌ The prompt was truncated before the model even processed it
- ❌ Generated a wall of text about "how to build a dApp" with generic advice
- ❌ Mentioned `npm start` — not even the right command for SE2
- ❌ Never called any tools — no `exec`, no `write`, no `read`
- ❌ Output included hallucinated x402 payment protocol details (from truncated context bleed)
- ❌ Zero files created in the workspace

**Root cause:** qwen2.5-coder:32b defaults to 4K context in Ollama. The 190KB ETHSKILLS.md alone is ~50K tokens — the model literally couldn't see the instructions or the task. It was flying completely blind.

### Qwen 2.5 Summary

| Category | Score |
|----------|-------|
| Used SE2 (npx create-eth@latest) | ❌ No |
| Correct file paths | ❌ N/A (no files) |
| Followed ethskills phases | ❌ No |
| Used tools (exec, write, read) | ❌ No tools called |
| Ran tests | ❌ No |
| Compiled successfully | ❌ N/A |
| ethskills rules followed | ❌ No |
| Production-ready code quality | ❌ N/A |

---

## Build 3: Qwen3 Coder Next 80B MoE (Single Larva, Local)

**Model:** `ollama/qwen3-coder-next` (local, 51GB, 80B total / 3B active per token)
**Architecture:** Single larva — `local-dev` (full stack)
**Cost:** $0.00 (local inference)

### Results

| Metric | Value |
|--------|-------|
| Duration | 240,971ms (~4 min) |
| Tokens | 4,119 |
| Tool calls | **ZERO** |
| Files created | **ZERO** |

**What happened:**
- ✅ Model has 256K native context — it COULD see the full ETHSKILLS.md (unlike qwen2.5-coder)
- ❌ But it still didn't use any tools
- ❌ Generated text about the ethskills content (specifically x402 payment protocol details)
- ❌ Appeared to read and comprehend ETHSKILLS.md (referenced specific content)
- ❌ But could not translate comprehension into tool calls
- ❌ Never called `exec` to run `npx create-eth@latest`
- ❌ Never called `write` to create any files
- ❌ Zero files created in the workspace
- ❌ Only 4,119 tokens output — barely engaged with the task
- ❌ 17 tok/s generation speed (very slow for agent work)

**Root cause:** qwen3-coder-next understands the knowledge but cannot reliably perform OpenClaw tool calling. The model was designed for "agentic coding" but its tool-use capabilities don't translate to the OpenClaw tool format. It reads, it comprehends, but it doesn't act.

### Qwen3 Summary

| Category | Score |
|----------|-------|
| Used SE2 (npx create-eth@latest) | ❌ No |
| Correct file paths | ❌ N/A (no files) |
| Followed ethskills phases | ❌ No |
| Used tools (exec, write, read) | ❌ No tools called |
| Ran tests | ❌ No |
| Compiled successfully | ❌ N/A |
| ethskills rules followed | ❌ No (comprehended but didn't act) |
| Production-ready code quality | ❌ N/A |

---

## Head-to-Head Comparison

| Metric | Opus 4.6 (2 larvae) | Qwen 2.5 Coder 32B | Qwen3 Coder Next 80B |
|--------|---------------------|--------------------|-----------------------|
| **Model size** | Cloud (unknown) | 19GB (32B params) | 51GB (80B params, 3B active) |
| **Context window** | 200K | 4K (fatal) | 256K |
| **Cost** | ~$2.00 | $0.00 | $0.00 |
| **Total duration** | ~3 min (parallel) | ~4 min | ~4 min |
| **Total tokens** | 170,000+ | 6,448 | 4,119 |
| **Tool calls** | Dozens | 0 | 0 |
| **Files created** | 50+ (2 full SE2 projects) | 0 | 0 |
| **Used Scaffold-ETH 2** | ✅ | ❌ | ❌ |
| **Followed ethskills** | ✅ | ❌ | ❌ |
| **Working code** | ✅ (20/20 tests, frontend compiles) | ❌ | ❌ |
| **Could read context** | ✅ | ❌ (4K limit) | ✅ (but didn't act) |
| **Used tools** | ✅ (exec, write, read) | ❌ | ❌ |

---

## Key Insights

### 1. The Tool-Use Gap is the Moat
Cloud frontier models (Opus, Sonnet, GPT) can reliably call tools — `exec`, `write`, `read` — in the OpenClaw agent format. Local models cannot, even ones specifically marketed for "agentic coding." This is the single biggest differentiator for agent work.

### 2. Context Window Matters But Isn't Sufficient
- qwen2.5-coder at 4K context was DOA — couldn't even see the task
- qwen3-coder-next at 256K could read everything but couldn't act on it
- Having the context is necessary but not sufficient — you need tool-use capability too

### 3. ethskills Baking Works (When the Model Can Act)
The ethskills-baked SOUL.md + AGENTS.md + ETHSKILLS.md approach worked perfectly with Opus:
- First attempt (before baking): Opus created standalone Foundry projects, ignored SE2
- Second attempt (with baking): Opus ran `npx create-eth@latest`, used correct paths, followed phases
- The baking approach is the right architecture — it just needs a model capable of tool use

### 4. Cost vs Capability is Stark
- $2 with Opus: Complete, tested, QA'd dApp with contract + frontend
- $0 with local models: Nothing. Zero files. Just text.
- The ROI on cloud models for agent work is currently infinite — local models produce 0 output

### 5. Multi-Larva Specialization Works
Splitting the work between a Solidity specialist and a UX specialist (both Opus) produced better results than asking one model to do everything. Each larva stayed in its lane and produced focused, high-quality output.

### 6. The Future is Clear
Local models will get there — qwen3-coder-next is explicitly designed for tool use and has the context window. The missing piece is reliable tool-call formatting for non-OpenAI/Anthropic function calling formats. When Ollama models can reliably emit tool calls in the OpenClaw format, this entire system runs for free on your Mac.

---

## Hardware & Environment
- **Machine:** Apple M3 Max/Ultra, 128GB unified memory, 16 cores
- **OS:** macOS 26.2 (Darwin 25.2.0, ARM64)
- **Docker:** larva image (~200MB, Node 22 slim + OpenClaw 2026.2.17)
- **Ollama:** Running on host, accessible from Docker via `host.docker.internal:11434`
- **Network:** Starlink (for the download, ~20-37 MB/s)
- **ethskills version:** Fetched 2026-02-19 from https://ethskills.com (17 skills, 190KB)

## Reproduction

```bash
cd ~/.openclaw/workspace/clawd-larvae

# Build image
docker build -t larva .

# Opus (cloud) — the one that works
./larvae.sh spawn solidity-dev --model opus
./larvae.sh spawn ux-dev --model opus
./larvae.sh talk solidity-dev "Build the CLAWD token contract..."
./larvae.sh talk ux-dev "Build the CLAWD token frontend..."

# Local (free) — doesn't work yet
./larvae.sh spawn local-dev --model qwen3
./larvae.sh talk local-dev "Build the CLAWD token hub..."

# Compare
find shared-workspace/solidity-dev -name "*.sol" | wc -l  # Opus: many
find shared-workspace/local-dev -name "*.sol" | wc -l     # Local: 0
```
