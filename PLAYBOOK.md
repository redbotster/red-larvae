# 🦞 Larvae dApp Playbook

> The complete build pipeline for shipping Ethereum dApps with clawd-larvae.
> Follow this document step by step. Every build starts here.

---

## The Problem This Solves

AI agents build apps that are unusable. They generate code that compiles but nobody can actually use. The contract works but the frontend is broken. The frontend loads but the user can't figure out what to do. The approve flow is missing. The button doesn't disable. The network switch doesn't work. The transfer history is empty.

**This playbook fixes that by starting every build with a plan and user journeys.** Before a single line of code is written, we know exactly who uses the app, what they do, and what every screen looks like at every step. Then we build to that spec, test against it, and don't ship until every journey works end to end.

---

## The Three-Phase System (from ethskills.com/orchestration)

Every build follows three phases. **Never skip or combine them.** If you find a bug in a later phase, go back to the appropriate earlier phase and fix it there.

| Phase | Environment | What Happens |
|-------|-------------|-------------|
| **Phase 1: Local** | `yarn fork` + `yarn deploy` + `yarn start` | Contracts + frontend on localhost against a fork of the target chain. All development and testing happens here. Iterate fast. |
| **Phase 2: Live Contracts + Local UI** | Contracts on Base/Arbitrum + frontend on localhost | Deploy contracts to the real network. Point the local frontend at them. Test every user journey with real wallets on the real chain. Small amounts. |
| **Phase 3: Production** | Everything live | Deploy frontend to IPFS (`yarn ipfs`) or Vercel. Set up production URL (ENS subdomain or domain). Test every user journey again on the live site. Share with beta testers. Ship. |

**Phase transition rules:**
- Phase 3 bug → go back to Phase 2 (fix with local UI + live contracts)
- Phase 2 contract bug → go back to Phase 1 (fix locally, write regression test, redeploy)
- Never hack around bugs in production

---

## Step 1: Write the Plan

**Before spawning any larvae, the parent agent writes a complete build plan.**

This is the most important step. A clear plan prevents the #1 failure mode: building something that technically works but nobody can use.

### 1a. Identify User Archetypes

Every dApp has different types of users. List them all. For each one, identify:
- **Who they are** — what's their role?
- **What they want** — what's their goal?
- **What they need** — what do they bring (tokens, ETH, permissions)?

**Example — DEX:**
| Archetype | Who | Goal | Needs |
|-----------|-----|------|-------|
| Swapper | Regular user | Exchange Token A for Token B | Wallet + Token A |
| Liquidity Provider (LP) | DeFi user | Earn fees by providing liquidity | Wallet + both tokens |
| Admin | Protocol owner | Set fees, pause in emergency | Owner wallet |

**Example — Staking App:**
| Archetype | Who | Goal | Needs |
|-----------|-----|------|-------|
| Staker | Token holder | Stake tokens to earn rewards | Wallet + tokens |
| Claimer | Active staker | Claim accumulated rewards | Wallet + staked position |
| Admin | Contract owner | Set reward rates, fund rewards pool | Owner wallet + reward tokens |

**Example — NFT Mint:**
| Archetype | Who | Goal | Needs |
|-----------|-----|------|-------|
| Minter | Collector | Mint an NFT | Wallet + ETH for mint price |
| Holder | NFT owner | View their NFTs, see metadata | Wallet + minted NFT |
| Admin | Creator | Set mint price, reveal, withdraw | Owner wallet |

### 1b. Write User Journeys

For EACH archetype, write out the exact step-by-step journey. Every click. Every screen state. Every transaction. This is what we build to and test against.

**The journey format:**
```
[Archetype Name] Journey:
1. Land on app → see [what they see]
2. Click [button] → [what happens]
3. [Next step] → [what happens]
...
N. Done → [final state]
```

**Example — DEX Swapper Journey:**
```
Swapper Journey:
1. Land on app → see swap card with "From" token selector, amount input, "To" token selector, output preview
2. No wallet connected → see big "Connect Wallet" button where the swap button would be
3. Click Connect Wallet → RainbowKit modal opens, pick wallet
4. Connected but wrong network → button changes to "Switch to Base"
5. Click Switch to Base → wallet prompts network switch, button updates
6. Select input token (e.g. USDC) → token selector dropdown, shows user's balance
7. Enter amount → see output amount update in real-time, see USD values for both
8. If first time using this token → button shows "Approve USDC" (not swap button yet)
9. Click Approve → button shows spinner "Approving...", disabled, wallet pops up
10. Sign in wallet → button stays "Approving..." until tx confirms onchain
11. Approval confirmed → button changes to "Swap"
12. Click Swap → button shows spinner "Swapping...", disabled, wallet pops up
13. Sign in wallet → button stays "Swapping..." until tx confirms
14. Swap confirmed → success message, balances update, swap card resets
15. See tx in transfer history below the swap card
```

**Example — DEX LP Journey:**
```
LP Journey:
1. Land on app → see "Pools" or "Liquidity" tab
2. Click Liquidity tab → see list of pools with APY, TVL
3. Click a pool → see pool details, "Add Liquidity" card
4. Not connected → Connect Wallet button
5. Connected, wrong network → Switch to Base button
6. Enter amounts for both tokens → see pool share preview, USD values
7. Need to approve Token A → "Approve Token A" button
8. Approve Token A → spinner, wallet, wait for confirm
9. Need to approve Token B → "Approve Token B" button
10. Approve Token B → spinner, wallet, wait for confirm
11. Both approved → "Add Liquidity" button
12. Click Add Liquidity → spinner, wallet, confirm
13. Done → see LP position in "Your Positions" section, see pool share %
```

### 1c. Define the Contract Interface

From the user journeys, extract every onchain action:

```
Contract: SwapRouter
  - swap(tokenIn, tokenOut, amountIn, minAmountOut) → called by Swapper at step 12
  - getAmountOut(tokenIn, tokenOut, amountIn) → read by UI at step 7

Contract: LiquidityPool
  - addLiquidity(tokenA, tokenB, amountA, amountB) → called by LP at step 11
  - removeLiquidity(tokenA, tokenB, shares) → called by LP when withdrawing
  - getPoolInfo() → read by UI at step 2
```

Every function maps to a specific step in a specific user journey. If a function doesn't map to any journey step, question whether it's needed.

### 1d. Define Testing Values

For local development, define smaller/faster values:

```
Testing overrides:
  - Mint price: 0.001 ETH (production: 0.05 ETH)
  - Staking period: 60 seconds (production: 7 days)
  - Min stake: 1 token (production: 100 tokens)
  - Reward rate: 1 token/minute (production: 100 tokens/day)
```

These get used in Phase 1. Production values get set in Phase 2/3.

### 1e. Write It All Down

The parent agent writes this plan to `shared-workspace/BUILD-PLAN.md`. This file gets copied into every larva's workspace so they all work from the same spec.

---

## Step 2: Build the Contract

Spawn the contract developer larva:

```bash
./larvae.sh spawn contract-dev --model opus --profile builder
```

Give it the plan. Be SPECIFIC:

```
Read ETHSKILLS.md first. Follow the phases exactly.

Here is the build plan:
[paste from BUILD-PLAN.md — archetypes, journeys, contract interface, testing values]

Use Scaffold-ETH 2: npx create-eth@latest
Contracts go in packages/foundry/contracts/
Deploy scripts in packages/foundry/script/
Tests in packages/foundry/test/

Build the contracts. Write comprehensive tests covering:
- Every function from every user journey
- Edge cases: zero amounts, max uint, unauthorized callers, self-transfers
- Fuzz tests for any math operations
- Access control: non-owner can't call admin functions
- Events emitted for every state change

Run the tests. They must all pass. Show me the results.
```

**Parent validates after completion:**
- [ ] SE2 monorepo exists (`packages/foundry/` present)
- [ ] Contract files in `packages/foundry/contracts/`
- [ ] Deploy script in `packages/foundry/script/`
- [ ] Test file in `packages/foundry/test/`
- [ ] Tests were actually run (look for pass/fail output)
- [ ] All tests pass
- [ ] No hallucinated addresses
- [ ] Contract interface matches the build plan

---

## Step 3: Audit the Contract

Spawn a SEPARATE QA larva with FRESH context. **Never audit with the same agent that built the code.** Fresh eyes catch what the builder is blind to.

```bash
./larvae.sh spawn qa-audit --model opus --profile auditor
```

Copy the project into the QA workspace:
```bash
cp -r shared-workspace/contract-dev/<project> shared-workspace/qa-audit/
```

Prompt the QA larva:
```
You are a smart contract security auditor.

Read ETHSKILLS.md first — focus on the security and qa sections.

The code to audit is in your workspace at:
  <project>/packages/foundry/contracts/
  <project>/packages/foundry/test/
  <project>/packages/foundry/script/

Your job:
1. Read every contract source file
2. Run the tests yourself: cd <project> && forge test -vvv
3. Run slither if available: slither .
4. Check every item on the ethskills/security pre-deploy checklist:
   - Access control on every admin function
   - Reentrancy protection (CEI pattern + nonReentrant)
   - Token decimal handling (no hardcoded 1e18 for non-18-decimal tokens)
   - Integer math (multiply before divide)
   - SafeERC20 for all token operations
   - Input validation (zero address, zero amount, bounds)
   - Events emitted for every state change
   - No infinite approvals
5. Report PASS/FAIL for each checklist item
6. List any bugs, vulnerabilities, or concerns
7. Give an overall SHIP / NO-SHIP verdict

Do NOT fix anything. Only report findings.
```

**Parent reviews the audit report.** There are three outcomes:

### Outcome A: SHIP — All Clear
Move to Step 4.

### Outcome B: NO-SHIP — Real Issues
Send the findings back to the contract-dev larva:
```bash
./larvae.sh talk contract-dev "Audit found these issues:
1. [finding]
2. [finding]
Fix them. Run tests. Confirm all pass."
```
Then re-audit (repeat Step 3).

### Outcome C: NO-SHIP — False Positives or Known Edge Cases
Audit bots are often overzealous. Not every finding needs a fix. Common situations:
- **"No reentrancy guard on view function"** — views can't be reentered, ignore
- **"Centralization risk: owner can pause"** — that's by design, document it
- **"No timelocked admin"** — valid for MVP, document as known limitation
- **"Token doesn't handle fee-on-transfer"** — if you only support standard ERC-20s, that's fine

For each finding, decide: **Fix**, **Document as known issue**, or **Dismiss as false positive**.

Document decisions in `shared-workspace/AUDIT-NOTES.md`:
```
## Audit Notes
- Finding: "Owner can drain contract" → Fix: Added withdrawal limits
- Finding: "No timelock on admin" → Known: MVP ships without timelock, add in v2
- Finding: "Centralization risk" → Dismissed: Owner is a multisig in production
```

---

## Step 4: Deploy to Local Fork

The contract is built and audited. Now deploy it locally and prepare for frontend development.

```bash
# In the SE2 project directory:
yarn fork --network base       # Terminal 1: fork of real Base
cast rpc anvil_setIntervalMining 1  # Enable block mining for timestamps
yarn deploy                    # Terminal 2: deploy to local fork
```

**Critical:** During local development, `scaffold.config.ts` must target `chains.foundry` (chain ID 31337), NOT `chains.base`. The fork runs on Anvil locally. Switch to `chains.base` only when deploying to the real network in Phase 2.

Use the testing values from the build plan (smaller amounts, shorter times) for fast iteration.

---

## Step 5: Build the Frontend

Spawn the frontend developer larva:

```bash
./larvae.sh spawn frontend-dev --model opus --profile frontend
```

Copy the contract project (with contracts already built and deployed locally):
```bash
cp -r shared-workspace/contract-dev/<project> shared-workspace/frontend-dev/
```

**Give it the build plan AND the user journeys.** This is the key difference — the frontend dev builds to the user journeys, not to an abstract feature list.

```
Read ETHSKILLS.md first — especially frontend-ux, frontend-playbook, orchestration, and qa.

Here is the build plan with user journeys:
[paste BUILD-PLAN.md]

Build the frontend in the existing SE2 project at <project>/packages/nextjs/

CRITICAL RULES (from ethskills):

1. EVERY onchain button must disable + show spinner from click until block confirmation.
   Use useScaffoldWriteContract (NOT raw wagmi useWriteContract).
   Each button gets its OWN loading state. Never share isLoading across buttons.

2. Four-state button flow — show exactly ONE button at a time:
   Not connected → "Connect Wallet" button (RainbowKitCustomConnectButton)
   Wrong network → "Switch to Base" button
   Needs approval → "Approve [Token]" button (with spinner per rule 1)
   Ready → Action button ("Swap", "Stake", etc.)
   NEVER show "please connect your wallet" as text. Always a button.
   NEVER show Approve and Action buttons simultaneously.

3. Use <Address/> for ALL address display. Use <AddressInput/> for all address input.
   Show the deployed contract address at the bottom of the page.

4. Show USD values next to every token/ETH amount (display AND input).
   Use useNativeCurrencyPrice() for ETH price.

5. Use SE2 hooks ONLY — useScaffoldReadContract, useScaffoldWriteContract, useScaffoldEventHistory.
   Never use raw wagmi hooks (useWriteContract, useReadContract).

6. Human-readable amounts — formatEther/formatUnits for display, parseEther/parseUnits for contract calls.
   Never show raw wei to users.

7. scaffold.config.ts:
   - pollingInterval: 3000 (not the default 30000)
   - rpcOverrides via process.env (never hardcoded API keys)
   - targetNetworks: [chains.foundry] for local dev

8. Remove ALL SE2 default branding:
   - Footer: remove BuidlGuidl links, "Fork me", SE2 mentions
   - Tab title: app name, not "Scaffold-ETH 2"
   - README: about THIS project, not the SE2 template
   - Favicon: custom, not SE2 default
   - No duplicate h1 matching the header

9. Register any external contracts in externalContracts.ts BEFORE building components.

Build EACH user journey as described in the plan. The user should be able to walk through
every step of every journey exactly as written.
```

---

## Step 6: Frontend QA

Spawn a fresh QA larva for frontend review:

```bash
./larvae.sh spawn qa-frontend --model opus --profile qa
```

Copy the project:
```bash
cp -r shared-workspace/frontend-dev/<project> shared-workspace/qa-frontend/
```

```
You are a frontend QA reviewer for an Ethereum dApp.

Read ETHSKILLS.md first — focus on qa and frontend-ux sections.

The code is in your workspace. Review every .tsx file in packages/nextjs/app/
and packages/nextjs/components/, plus scaffold.config.ts and externalContracts.ts.

Check the ethskills/qa Pre-Ship Audit — report PASS/FAIL for each:

Ship-Blocking:
- [ ] Wallet connection shows a BUTTON, not text
- [ ] Wrong network shows a Switch button
- [ ] One button at a time (Connect → Network → Approve → Action)
- [ ] Every onchain button disables + spinner through block confirmation
- [ ] Uses useScaffoldWriteContract, NOT raw wagmi useWriteContract
- [ ] SE2 footer branding removed
- [ ] SE2 tab title removed
- [ ] SE2 README replaced

Should Fix:
- [ ] Contract address displayed with <Address/> component
- [ ] <AddressInput/> used for all address inputs
- [ ] USD values next to all token/ETH amounts
- [ ] OG image is absolute production URL (not localhost, not relative)
- [ ] pollingInterval is 3000
- [ ] RPC overrides set via env vars (not default SE2 key, not hardcoded)
- [ ] No hardcoded API keys in any committed file
- [ ] Favicon updated from SE2 default
- [ ] Human-readable amounts everywhere (no raw wei)
- [ ] No duplicate h1 matching header
- [ ] Each button has its own loading state (not shared isLoading)

Give SHIP / NO-SHIP verdict.
```

Fix any issues by talking to the frontend-dev larva (same as Step 3 Outcome B).

---

## Step 7: Walk Every User Journey on Localhost

**This is where most builds currently fail.** The code passes QA but the actual user experience is broken.

For EACH user archetype from the build plan, walk through their ENTIRE journey with a burner wallet on localhost:

```
For each journey in BUILD-PLAN.md:
  1. Open localhost:3000 in browser (or take a snapshot)
  2. Start with no wallet connected
  3. Follow every step in the journey
  4. At each step, verify:
     - Does the UI show what the journey says it should?
     - Does the button do what it's supposed to?
     - Does the loading state work?
     - Does the result appear?
  5. Document any step that fails or feels wrong
```

**Common failures caught at this step:**
- Approve flow doesn't transition to action button after approval confirms
- Transfer history doesn't show new transactions until page refresh
- Amount input doesn't validate (lets you enter more than your balance)
- Error when rejecting tx in wallet (UI doesn't recover)
- Network switch doesn't actually switch (button stays)
- USD values are NaN or $0.00
- Page is blank when no wallet is connected

**If ANY journey step fails:** Go back to Step 5 (frontend) or even Step 2 (contract) if the issue is in the contract. Fix it. Re-test. This loop is normal and expected — don't skip it.

---

## Step 8: Deploy Contracts to Target Network (Phase 2)

Once all journeys work on localhost:

```bash
# Update scaffold.config.ts
targetNetworks: [chains.base]  # Switch from chains.foundry to real chain

# Generate deployer wallet
yarn generate
yarn account  # Get the address, send ETH to it

# Deploy to real Base
yarn deploy --network base

# Verify on block explorer
yarn verify --network base
```

**Use production values now** — real mint prices, real staking periods, real minimum amounts. Update the deploy script or constructor args.

**Post-deploy checks:**
- [ ] Contract verified on BaseScan
- [ ] All read functions return expected values
- [ ] One small test transaction works

---

## Step 9: Test Every Journey on Real Network with Local UI

**Keep the frontend on localhost but pointed at the real Base contracts.** This is Phase 2 of the three-phase system.

Walk through EVERY user journey again, but now with:
- Real wallets (not burner wallets)
- Real tokens on Base
- Small real amounts ($1-$10)
- Real gas costs

```
For each journey in BUILD-PLAN.md:
  1. Open localhost:3000 connected to Base
  2. Walk every step with a real wallet
  3. Verify every transaction actually lands onchain
  4. Check block explorer for each tx
  5. Verify events emitted correctly
  6. Document any failures
```

**If ANY step fails:** Go back to the appropriate phase:
- Frontend bug → Step 5, fix, re-test from Step 7
- Contract bug → Step 2, fix, re-test from Step 3 (re-audit!), redeploy contracts, re-test from Step 9
- Going back is normal. Going back is good. It means you caught it before users did.

---

## Step 10: Deploy Frontend to Production (Phase 3)

Once all journeys work on real Base with local UI:

### Pre-deploy checklist:
- [ ] `onlyLocalBurnerWallet: true` in scaffold.config.ts (prevents burner wallet in prod)
- [ ] OG image created (1200x630 PNG, not the SE2 default)
- [ ] OG image URL set to production domain (absolute URL)
- [ ] All production values set (not testing values)
- [ ] No secrets in committed files

### Deploy to IPFS:
```bash
cd packages/nextjs
rm -rf .next out  # ALWAYS clean first

NEXT_PUBLIC_PRODUCTION_URL="https://myapp.yourname.eth.link" \
  NODE_OPTIONS="--require ./polyfill-localstorage.cjs" \
  NEXT_PUBLIC_IPFS_BUILD=true \
  NEXT_PUBLIC_IGNORE_BUILD_ERROR=true \
  yarn build

# Verify before uploading:
ls out/*/index.html                        # Routes exist
grep 'og:image' out/index.html             # Not localhost
# If CID didn't change from last deploy, you deployed stale code!

yarn bgipfs upload out   # Save the CID
```

### Or deploy to Vercel:
```bash
cd packages/nextjs && vercel
# Root Directory: packages/nextjs
# Install Command: cd ../.. && yarn install
```

### Set up production URL:
- **ENS subdomain:** Create subdomain on app.ens.domains → set content hash to `ipfs://<CID>`
- **Custom domain:** Point DNS to Vercel or use a gateway
- **This sometimes needs a human** — if ENS transactions are needed, tell the human what to do

---

## Step 11: Test Every Journey on Live Production

**The final test. Everything is live — real contracts, real frontend, real URL.**

Walk through EVERY user journey one more time:

```
For each journey in BUILD-PLAN.md:
  1. Open the production URL in a browser
  2. Verify the site loads (not 404, not blank page)
  3. Check tab title (not "Scaffold-ETH 2")
  4. Check OG unfurl (share the link, see the preview)
  5. Walk every step of every journey with real wallets on Base
  6. Test on mobile too (wallet deep linking, responsive layout)
  7. Document any failures
```

**If anything fails:** Go back to the appropriate step. Redeploy as needed. This is normal.

**Common Phase 3 failures:**
- Routes return 404 on IPFS (missing `trailingSlash: true`)
- OG image shows localhost URL
- Burner wallet showing in production
- Different behavior on mobile vs desktop
- Wallet deep linking not working (MetaMask, Rainbow)

---

## Step 12: Redeploy with Production Values

If you used any testing overrides (smaller amounts, shorter times), now is when you set the final production values:

- Redeploy contracts with production constructor args if needed
- Update `externalContracts.ts` with new contract addresses
- Rebuild and redeploy frontend
- Re-test affected journeys

---

## Step 13: Beta Testing

Share the production URL with beta testers. Give them the user journeys and ask them to walk through each one.

Collect feedback. Common beta feedback:
- "I didn't know I needed to approve first" → improve the approve button copy
- "It looked like nothing happened" → loading state not visible enough
- "I couldn't figure out how to connect" → connect button not prominent enough

Fix issues. Go back to whatever step is needed. Redeploy.

---

## Step 14: Ship It

When beta testers can walk through every journey without confusion:

1. **Tweet the live URL** — include a screenshot/video of the main flow
2. **Post to relevant communities** — Farcaster, Discord, etc.
3. **Monitor** — watch contract events on BaseScan, check for unexpected behavior
4. **Have an incident plan** — if something goes wrong, know how to pause (if the contract supports it) and communicate

---

## Archetype Reference: User Journeys

Quick-reference user journeys for common dApp types. Use these as starting points — customize for your specific app.

### Token Launch
**Archetypes:** Buyer, Holder, Admin
```
Buyer: Connect → see token info (name, symbol, price, supply) → enter amount → approve payment token → buy → see tokens in balance
Holder: Connect → see balance → enter recipient + amount → send → see updated balance + tx in history
Admin: Connect → see admin panel (if owner) → set price / pause / withdraw → confirm tx
```

### NFT Collection
**Archetypes:** Minter, Holder, Admin
```
Minter: Connect → see collection info (name, supply, mint price, remaining) → click Mint → pay ETH → see NFT appear in "Your NFTs"
Holder: Connect → see "Your NFTs" gallery → click NFT → see metadata, traits, image → option to transfer
Admin: Connect → set base URI (reveal) → withdraw mint proceeds → set mint price
```

### Staking App
**Archetypes:** Staker, Claimer, Admin
```
Staker: Connect → see APY, total staked, your position → enter amount → approve token → stake → see position update
Claimer: Connect → see claimable rewards → click Claim → rewards added to wallet
Unstaker: Connect → see staked position → click Unstake → wait for cooldown (if any) → withdraw
Admin: Connect → set reward rate → fund reward pool → pause in emergency
```

### DAO / Governance
**Archetypes:** Voter, Proposer, Delegate, Admin
```
Voter: Connect → see active proposals → read proposal → vote For/Against/Abstain → see vote recorded
Proposer: Connect → click "New Proposal" → fill in title, description, actions → submit → proposal goes to voting
Delegate: Connect → see delegate selection → enter delegate address or self → confirm delegation
```

### Marketplace
**Archetypes:** Seller, Buyer
```
Seller: Connect → click "List Item" → select NFT → set price → approve NFT → list → see listing appear
Buyer: Connect → browse listings → click item → see details + price → buy → NFT transfers to wallet, payment to seller
```

---

## The System: How Larvae Work

### What We Have
- **clawd-larvae**: Docker containers running OpenClaw with ephemeral AI agents
- **ethskills**: 17 skills from ethskills.com baked into every larva at spawn (190KB)
- **Persistent workspaces**: `shared-workspace/<name>/` — files survive container death
- **Models**: Opus 4.6 (best, ~$2/build), Sonnet 4.5 (fast/cheap), GPT 5.2 (alternative)

### Commands
```bash
./larvae.sh spawn <name> --model opus --profile builder   # Hatch a larva with a profile
./larvae.sh talk <name> "message"         # Send it work
./larvae.sh list                          # See all larvae
./larvae.sh status <name>                 # Check health
./larvae.sh logs <name>                   # View container logs
./larvae.sh kill <name>                   # Kill one
./larvae.sh killall                       # Kill all
```

### Profiles
```
builder   → full-stack engineer: contracts + frontend + tests (all ethskills)
auditor   → security-focused Solidity auditor: finds bugs, never fixes (security + testing skills)
qa        → obsessive frontend QA: enforces ethskills/qa checklist to the letter (qa + frontend skills)
frontend  → senior frontend dev: SE2 hooks, wallet flow, UX (frontend + qa skills)
all       → generic dev with all 17 ethskills (default)
```

### Typical Larva Team
```
contract-dev  --profile builder   → builds contracts + tests
qa-audit      --profile auditor   → audits contracts (fresh context, separate from builder)
frontend-dev  --profile frontend  → builds frontend to user journey specs
qa-frontend   --profile qa        → audits frontend (fresh context)
```

### Key Rules
- **Always say "Read ETHSKILLS.md first"** in every prompt
- **Always include the build plan + user journeys** in prompts
- **Separate build from audit** — never audit with the same agent that built
- **One task per talk** — don't overload a single message
- **Copy files between workspaces** when sharing (each larva has its own directory)

---

## Known Limitations

1. **Local models can't do agent work yet** — only cloud models (Opus, Sonnet, GPT) use tools reliably
2. **No browser in containers** — larvae can't visually test frontends; QA is code-review only
3. **Single-turn talks** — each `talk` is stateless; larva sees SOUL + AGENTS + ETHSKILLS + your message
4. **190KB ethskills eats context** — for very complex tasks, keep prompts focused
5. **File sharing is manual** — `cp -r` between workspace directories
6. **Human needed for** — ENS setup, funding deployers, final visual testing, production URL setup

---

## After Every Build

Update this playbook:

1. **What journey steps failed?** Add them as warnings to the relevant step.
2. **What did QA miss?** Strengthen the QA prompts.
3. **What did the human have to fix?** Every manual fix = playbook gap. Close it.
4. **What took too long?** Find bottlenecks. Optimize.
5. **What worked great?** Document it so we repeat it.
