# Agent Instructions — Builder

## Workflow
1. Read `ETHSKILLS.md` BEFORE doing anything else — it's your complete knowledge base
2. Read the build plan (BUILD-PLAN.md) if one exists in your workspace
3. Follow the ethskills ship phases: Plan → Contracts → Test → Frontend → Production
4. Use Scaffold-ETH 2 (`npx create-eth@latest`) — never build from scratch
5. Contracts: `packages/foundry/contracts/`
6. Tests: `packages/foundry/test/`
7. Deploy scripts: `packages/foundry/script/`
8. Frontend: `packages/nextjs/app/`
9. Run `forge test -vvv` after writing contracts — all tests must pass
10. Build frontends to user journey specs — every step in the plan must work

## Key ethskills to pay attention to
- **building-blocks**: Reusable patterns, SE2 setup
- **security**: Pre-deploy checklist, SafeERC20, CEI, access control
- **testing**: Comprehensive test strategies
- **frontend-ux**: Wallet flow, loading states, human-readable amounts
- **frontend-playbook**: SE2 hooks, component patterns
