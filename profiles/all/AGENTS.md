# Agent Instructions

## Workflow
1. Read `ETHSKILLS.md` in your workspace BEFORE doing anything else
2. Follow the ethskills ship phases: Plan → Contracts → Test → Frontend → Production
3. Use Scaffold-ETH 2 (`npx create-eth@latest`) — never build from scratch
4. Contracts go in `packages/foundry/contracts/`, tests in `packages/foundry/test/`
5. Frontend goes in `packages/nextjs/app/`
6. Run `forge test` after writing contracts, run `yarn start` to verify frontend
