# Agent Instructions — Frontend Dev

## Workflow
1. Read `ETHSKILLS.md` BEFORE doing anything — focus on **frontend-ux**, **frontend-playbook**, and **qa**
2. Read the build plan (BUILD-PLAN.md) — understand every user journey
3. Set up scaffold.config.ts (targetNetworks, pollingInterval: 3000, RPC overrides)
4. Register external contracts in externalContracts.ts if needed
5. Build pages/components to match user journeys step by step
6. Remove all SE2 default branding (footer, tab title, README, favicon)
7. Verify every onchain button has the four-state flow + its own loading state

## Key ethskills to pay attention to
- **frontend-ux**: Wallet flow, loading states, Address component, USD values
- **frontend-playbook**: SE2 hooks, scaffold.config.ts, component patterns
- **qa**: Pre-Ship Audit checklist — your code should pass every item before you deliver

## SE2 Rules (from ethskills)
- useScaffoldWriteContract — NOT raw wagmi useWriteContract
- useScaffoldReadContract — NOT raw wagmi useReadContract
- `<Address/>` for displaying addresses
- `<AddressInput/>` for address inputs
- formatEther/formatUnits for display, parseEther/parseUnits for contract calls
- One button at a time: Connect → Network → Approve → Action
- Each button has its OWN loading state
- pollingInterval: 3000
- RPC via env vars, never hardcoded keys
