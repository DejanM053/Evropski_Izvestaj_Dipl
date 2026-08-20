# Progress

## Current phase

Phase 1 — Contract + Hardhat tests

## Phases (from master_plan.md §8)

- [x] Phase 0 — Repository restructure (mobile/backend/blockchain split, root config)
- [x] Phase 1 — Contract + Hardhat tests
- [ ] Phase 2 — Docker Compose + backend skeleton + `/api/health`
- [ ] Phase 3 — Session + report CRUD + Socket.IO sync
- [ ] Phase 4 — GridFS uploads + hashing
- [ ] Phase 5 — Design system → Flutter theme + widgets
- [ ] Phase 6 — Screens 1–4 (session pairing)
- [ ] Phase 7 — Screens 5–9 (form, circumstances, sketch, photos)
- [ ] Phase 8 — Screens 10–11 (review + signatures)
- [ ] Phase 9 — PDF generation
- [ ] Phase 10 — Finalize + anchor + screens 12–13
- [ ] Phase 11 — Verify endpoint + screens 14–15
- [ ] Phase 12 — Testnet deploy + README + demo script

## Decisions

- Pinned Hardhat to 2.29.1 (with hardhat-toolbox 6.1.2) instead of the
  default Hardhat 3 install: HH3's ESM config, node:test runner, and
  viem-first networking don't match the plan's `npx hardhat node` /
  chai-matcher conventions.
- `scripts/deploy.js` writes `{ address, abi }` as one JSON object to
  `backend/src/abi/AccidentRegistry.json` (not two separate files), since
  the backend's chain.service will need both to instantiate an ethers
  Contract.
- Only a `sepolia` network entry was added to `hardhat.config.js` (plan
  allows Sepolia or Polygon Amoy); reads `RPC_URL`/`PRIVATE_KEY` from env,
  no `.env.example` yet since that's part of Phase 2 infra work.

## Known issues

(none yet)
