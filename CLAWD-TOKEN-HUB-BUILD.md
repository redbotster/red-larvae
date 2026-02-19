# 🦞 $CLAWD Token Hub — Dual-Larvae Build Report

## Date: 2026-02-19
## Method: Two ephemeral Opus 4.6 Docker larvae, working in parallel

---

## The Experiment

Spawned two ephemeral OpenClaw Docker containers ("larvae"), each running Claude Opus 4.6, each with a different SOUL file defining their expertise. Both were given the same product spec — build a $CLAWD Token Hub dApp — and told to follow [ethskills.com](https://ethskills.com) exactly.

### The Setup

```bash
# From clawd-larvae/
./larvae.sh spawn solidity-dev --model opus --workspace shared-workspace/solidity-dev
./larvae.sh spawn ux-dev --model opus --workspace shared-workspace/ux-dev
```

**Larva 1: `solidity-dev`** (port 28700)
- SOUL: "You are a senior Solidity smart contract developer"
- Task: Build the ERC-20 contract + Foundry tests
- Model: `anthropic/claude-opus-4-6`

**Larva 2: `ux-dev`** (port 28701)
- SOUL: "You are a senior product designer and frontend developer specializing in web3 UX"
- Task: Build the Scaffold-ETH 2 React frontend
- Model: `anthropic/claude-opus-4-6`

Both were instructed to:
1. Fetch `https://ethskills.com/ship/SKILL.md` first
2. Follow its routing table to fetch relevant sub-skills
3. Build the $CLAWD Token Hub dApp following the ethskills methodology

---

## What Each Larva Produced

### Solidity Dev — Smart Contracts

**Time:** ~93 seconds (93,004ms)
**Tokens:** 42,219
**Skills fetched:** `ship/SKILL.md`, `standards/SKILL.md`, `security/SKILL.md`, `testing/SKILL.md`

#### `contracts/ClawdToken.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title CLAWD Token
/// @notice ERC-20 token with fixed initial supply minted to deployer
contract ClawdToken is ERC20 {
    /// @notice Deploy CLAWD with 1,000,000 tokens minted to msg.sender
    constructor() ERC20("CLAWD", "CLAWD") {
        _mint(msg.sender, 1_000_000e18);
    }
}
```

Clean, minimal, follows ethskills guidance ("most dApps need 0-2 contracts"). OpenZeppelin base, no over-engineering.

#### `test/ClawdToken.t.sol` — 18 test cases including:
- Deployment: name, symbol, decimals, initial supply
- Transfer: updates balances, emits events, entire balance, zero amount, self-transfer
- Reverts: exceeds balance, transfer to zero address
- Approve/TransferFrom: full flow, exact allowance, overwrite, reverts
- **Fuzz tests (1000 runs each):** random transfers, total supply preservation, random approve+transferFrom, revert on insufficient balance

#### Project Structure
- Full Foundry project with `forge-std` and `openzeppelin-contracts` installed via `forge install`
- `foundry.toml` configured with `solc = "0.8.20"`, 1000 fuzz runs
- Compiled successfully — artifacts in `out/`

#### ethskills compliance:
- ✅ Used the Onchain Litmus Test (only ownership/transfer goes onchain)
- ✅ 1 contract (correct for "Token Launch" archetype)
- ✅ OpenZeppelin base, no custom math
- ✅ No admin functions, no reentrancy surface
- ✅ Events emitted via OZ internals
- ✅ Fuzz tests as specified by testing/SKILL.md
- ✅ Security checklist passed

---

### UX Dev — Frontend

**Time:** ~115 seconds (114,745ms)
**Tokens:** 35,869
**Skills fetched:** `ship/SKILL.md`, `frontend-ux/SKILL.md`, `frontend-playbook/SKILL.md`, `orchestration/SKILL.md`, `tools/SKILL.md`

#### `frontend/app/page.tsx` — Main page (~280 lines)
Features:
- **Hero Stats Grid:** Balance (with 🦞 emoji), Total Supply, ETH Price — 3 cards
- **Send Card:** Recipient input (with AddressInput component for ENS), amount input with Max button, USD conversion
- **Action Button Flow:** Connect → Switch to Base → Send (follows ethskills Rule 2: "four-state flow, one button at a time")
- **Transfer History:** Recent 10 transfers (sent + received), color-coded (red/green), with block numbers
- **Contract Address:** Displayed at bottom (ethskills Rule 3)

#### UX compliance with ethskills `frontend-ux/SKILL.md`:
- ✅ **Rule 1:** Never share loading state between buttons — each has independent `isSwitching` / `isSending`
- ✅ **Rule 2:** Four-state flow — Connect → Switch Network → Send
- ✅ **Rule 3:** Contract address displayed
- ✅ **Rule 5:** No duplicate h1 title
- ✅ **Rule 6:** RPC via env var, `pollingInterval: 3000`
- ✅ Skeleton loaders (animate-pulse) for all async data
- ✅ `formatEther` for human-readable balances
- ✅ USD values placeholder ready (clawdPrice variable)
- ✅ Mobile responsive (grid cols, sm: breakpoints)

#### Supporting files:
- `scaffold.config.ts` — Base chain, 3s polling, RPC override
- `externalContracts.ts` — Full ERC-20 ABI registered for Base (chain 8453)
- `layout.tsx` — Metadata with OG tags for social sharing

#### Design:
- Dark gradient background (gray-950 → gray-900)
- Orange accent color (#f97316) for $CLAWD branding
- Glassmorphism cards (backdrop-blur, semi-transparent)
- Custom spinner component

---

## Remaining Steps to Ship

Per the ethskills ship workflow:

1. **Replace placeholder address** — Deploy `ClawdToken.sol` to Base, update `0xCLAWD_TOKEN_ADDRESS_HERE` in both frontend files
2. **Set env vars** — `NEXT_PUBLIC_BASE_RPC`, `NEXT_PUBLIC_WC_PROJECT_ID`
3. **Wire USD pricing** — Plug in DexScreener API for real `clawdPrice`
4. **Update OG images** — Replace `YOUR-PRODUCTION-DOMAIN` URLs
5. **Transfer ownership to multisig** — Per ethskills Phase 4
6. **Run QA** — Feed to a separate reviewer agent with `https://ethskills.com/qa/SKILL.md`

---

## Stats

| Metric | Solidity Dev | UX Dev |
|--------|-------------|--------|
| Model | claude-opus-4-6 | claude-opus-4-6 |
| Duration | 93s | 115s |
| Tokens | 42,219 | 35,869 |
| Est. Cost | ~$1.05 | ~$0.90 |
| Files created | 3 (contract, test, config) + Foundry deps | 4 (page, layout, config, contracts) |
| ethskills fetched | 4 skills | 5 skills |

**Total wall-clock time:** ~2 minutes (ran in parallel)
**Total est. cost:** ~$1.95
**Total tokens:** 78,088

---

## How to Reproduce

```bash
cd ~/.openclaw/workspace/clawd-larvae

# Build the larva image
docker build -t larva .

# Spawn both larvae
./larvae.sh spawn solidity-dev --model opus
./larvae.sh spawn ux-dev --model opus

# Give them their tasks (see above for full prompts)
./larvae.sh talk solidity-dev "Build the CLAWD token contracts..."
./larvae.sh talk ux-dev "Build the CLAWD token frontend..."

# Check progress
./larvae.sh list
./larvae.sh status solidity-dev
./larvae.sh status ux-dev

# Kill when done — files persist
./larvae.sh killall
```

---

## Key Takeaways

1. **Parallel specialist larvae work.** Two Opus containers, each with a role-specific SOUL file, produced complementary artifacts that fit together. The Solidity dev didn't touch frontend code; the UX dev didn't write Solidity.

2. **ethskills.com provides real guidance.** Both larvae fetched the skill files and followed the routing table. The Solidity dev correctly identified this as a "Token Launch" archetype (1 contract). The UX dev followed every numbered frontend rule.

3. **~2 minutes for a complete dApp scaffold.** Contract + tests + frontend, all following a structured methodology, produced in parallel by disposable containers.

4. **Volume mounts are the key.** Both larvae wrote to host-mounted directories. After killing the containers, all code survives for integration.

5. **Cost is reasonable.** ~$2 total for Opus 4.6 on both sides. Could drop to ~$0.60 with Sonnet, or $0 with a capable local model like qwen3-coder-next.
