# Progress

## Current phase

Phase 3 — Session + report CRUD + Socket.IO sync

## Phases (from master_plan.md §8)

- [x] Phase 0 — Repository restructure (mobile/backend/blockchain split, root config)
- [x] Phase 1 — Contract + Hardhat tests
- [x] Phase 2 — Docker Compose + backend skeleton + `/api/health`
- [x] Phase 3 — Session + report CRUD + Socket.IO sync
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
- `/api/health` calls `verify(ZeroHash, ZeroHash)` as its chain read: it's
  the one contract method that never reverts regardless of args, so it
  cleanly distinguishes "no contract at this address" (decode error) from
  "contract present" without needing a known valid reportId.
- `CONTRACT_ADDRESS` placeholder in `.env.example` is the zero address, not
  blank, so `config.js`'s presence-only fail-fast check passes on a fresh
  clone and the backend can start before the contract is deployed;
  `/api/health` then honestly reports `chain` as an error until a real
  address is set.
- `.env` is read via `env_file:` in docker-compose, not baked into images,
  so picking up a new `CONTRACT_ADDRESS` only needs `docker compose up -d
  backend` (recreate), not a rebuild — confirmed `--build` on a scoped
  service still rebuilds/recreates its `depends_on` services too, which
  would reset the Hardhat node's in-memory chain and un-deploy the
  contract. Documented `up -d backend` without `--build` in the README.
- `Session.sessionCode` has no hard unique DB index. §5.3 asks for
  uniqueness "among non-expired sessions," and Mongo's TTL reaper runs on a
  ~60s cycle, so a hard unique index would occasionally block reusing a code
  from a session that's logically expired but not yet physically deleted.
  Uniqueness is instead enforced at generation time: check-for-collision
  against non-expired sessions, retry up to 10 times. Non-unique index kept
  for lookup performance.
- Split `src/index.js` into `src/app.js` (pure factory: builds the Express +
  Socket.IO app, no `.listen()`/Mongo connect) and a thin `src/index.js`
  entrypoint, purely so integration tests can `createApp()` and drive it
  with supertest/socket.io-client without a real process boot.
- Integration tests (`backend/test/`) run against the real dockerized Mongo
  on `localhost:27017` (db `accident-report-test`), not
  `mongodb-memory-server` — reuses infra already verified working in Phase
  2 instead of adding a new dependency that needs a binary download.
  **Requires `docker compose up -d mongo` (or any local mongod on 27017)
  before `npm test`.**
- `party:ready` only persists the per-party `ready` flag and rebroadcasts
  `party:status`; it does **not** auto-advance `Session.status` past
  `"joined"`. §5.3 doesn't specify the exact trigger for
  filling→review→signing→finalizing→sealed, and those transitions depend on
  routes this phase explicitly excludes (review confirmation, signatures,
  finalize) — deferred rather than guessed. See `.claude/rules/backend.md`
  for the full socket contract and other scope gaps (status/report status
  not synced, `?deviceId=` filter is a no-op).

## Known issues

- `GET /api/reports?deviceId=` doesn't filter — no `deviceId` field exists
  anywhere in §5.1's schemas yet. Needs a schema decision before the mobile
  client's local-deviceId history scoping (§6 client rules) can work.
