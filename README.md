# Accident Report App

A bachelor-thesis project: a mobile app that digitizes the European Accident
Statement ("blue-yellow report"), lets two drivers jointly fill and sign a
report in a shared live session, generates a PDF, stores it in MongoDB, and
anchors its SHA-256 hash on a blockchain so the report is provably
unaltered.

Built for correctness and demonstrability, not production scale — see
[docs/master_plan.md](docs/master_plan.md) for the full implementation plan
and [CLAUDE.md](CLAUDE.md) for the tech stack and hard invariants.

## Architecture

```
 Flutter app (party A + B, Android)
        │
        │  REST + Socket.IO
        ▼
 Node.js / Express + Socket.IO backend
        │
        ├── MongoDB 7 + GridFS
        │     (sessions, reports, photos/sketch/signatures, generated PDF)
        │
        └── ethers.js v6 (backend holds the only signing key —
              │             users never touch a wallet)
              ▼
        AccidentRegistry.sol
        (Hardhat local node, or Sepolia testnet)
```

Two drivers pair over a QR/6-character code, fill their half of the report
live (Socket.IO keeps both sides in sync), sketch the scene, attach photos,
review, and sign. On finalize, the backend generates a PDF, hashes it and
every attachment, stores everything in MongoDB/GridFS, and anchors the
PDF hash + an aggregate "bundle hash" on-chain — never any personal data,
only hashes, IDs, and timestamps (see `blockchain/contracts/AccidentRegistry.sol`).
A verify screen recomputes every hash from the stored bytes and compares
against the on-chain record, so any post-signing tampering — in the
database, not just the file — is detectable and names the specific file
affected.

## Repository layout

```
├── docker-compose.yml   # mongo, hardhat, backend
├── .env / .env.example  # shared config, read by docker compose and by
│                         # host-run scripts (blockchain deploy, backend
│                         # scripts/tamper.js)
├── blockchain/           # Solidity contract + Hardhat
├── backend/               # Express + Socket.IO + Mongoose + ethers.js
└── mobile/                 # Flutter app (Android)
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for
  `docker compose` — runs Mongo, the Hardhat node, and the backend)
- Node.js 20+ and npm (only needed on the host to run `blockchain/`'s deploy
  script and `backend/scripts/tamper.js` outside a container — the backend
  and hardhat containers bring their own Node runtime)
- [Flutter SDK](https://flutter.dev) (Android target; this project builds
  Android only, portrait orientation)
- Android Studio / Android SDK + an emulator, and/or a physical Android
  device with USB debugging enabled and `adb` on your `PATH`

## Setup from a clean clone

1. Copy the env template and fill in the placeholders:
   ```bash
   cp .env.example .env
   ```
2. Start Mongo, the local Hardhat node, and the backend:
   ```bash
   docker compose up -d --build
   ```
   At this point `GET http://localhost:3000/api/health` reports `chain` as
   an error — no contract is deployed at the placeholder zero address yet.
3. Deploy `AccidentRegistry` to the local Hardhat node (from the host,
   against the port docker compose exposed):
   ```bash
   cd blockchain
   npm install   # first time only
   npx hardhat run scripts/deploy.js --network localhost
   cd ..
   ```
   This prints the deployed contract address and writes the ABI (and that
   address, for reference) to `backend/src/abi/AccidentRegistry.json`.
4. Copy the printed address into `.env` as `CONTRACT_ADDRESS`.
5. Restart the backend so it picks up the new address — use `up`, not
   `restart`, since only `up` re-reads `.env`. **Don't add `--build` here**:
   because `backend` depends on `hardhat`, `--build` also rebuilds and
   recreates the `hardhat` container, which wipes its in-memory chain and
   un-deploys the contract you just anchored the address to.
   ```bash
   docker compose up -d backend
   ```
6. Confirm the whole stack is live:
   ```bash
   curl http://localhost:3000/api/health
   ```
   A healthy response looks like:
   ```json
   { "mongo": "ok", "chain": "ok", "contract": "0x...", "network": "localhost" }
   ```

This exact sequence (steps 2–6) was re-verified against a fresh git
worktree checkout with no other state carried over, as part of Phase 12 —
see PROGRESS.md's acceptance-checklist walkthrough.

## Environment variables

All variables live in one `.env` at the repo root, consumed by
`docker compose` (`env_file:`, not baked into the backend image — a new
value only needs `docker compose up -d backend`, not a rebuild) and by
host-run scripts (`blockchain/scripts/deploy.js`, `backend/scripts/tamper.js`)
via `dotenv`, which reads `.env` from the current working directory.

| Variable | Meaning | Local (Hardhat) value | Sepolia value |
|---|---|---|---|
| `MONGO_URI` | Mongo connection string. Inside docker compose, use the `mongo` service hostname — this only resolves from *inside* the compose network, not from the host. | `mongodb://mongo:27017/accident-report` | same |
| `RPC_URL` | JSON-RPC endpoint for the chain client. | `http://hardhat:8545` (the `hardhat` service hostname) | a public Sepolia RPC endpoint, e.g. `https://ethereum-sepolia-rpc.publicnode.com` (fallbacks: `https://rpc.sepolia.org`, `https://sepolia.drpc.org`) |
| `CONTRACT_ADDRESS` | Deployed `AccidentRegistry` address. Placeholder is the zero address until you deploy. | printed by `deploy.js --network localhost` | printed by `deploy.js --network sepolia` |
| `PRIVATE_KEY` | Backend's signing key for submitting anchor transactions. Users never hold wallets — this is the *only* key in the whole system, and the backend signs every transaction on their behalf. **Never commit a real, funded key.** | Hardhat's well-known default account #0 key (the same throwaway key every `npx hardhat node` prints) | a dedicated funded Sepolia wallet, kept out of the repo (see "Testnet deploy" below) |
| `CHAIN_NETWORK` | Human-readable label for the current chain. Drives which network's data the finalize pipeline stamps onto `report.chain.network`, and — client-side — whether the mobile app renders a block-explorer link (see below). | `localhost` | `sepolia` |
| `PORT` | Port the backend HTTP/Socket.IO server listens on. | `3000` | `3000` |

**Switching networks needs no code change** — only `.env` plus
`docker compose up -d backend` (no `--build`). `chain.service.js` builds its
`ethers` provider/contract purely from `RPC_URL`/`CONTRACT_ADDRESS`/
`PRIVATE_KEY`, with no network-name branching anywhere in the backend.
Client-side, `CHAIN_NETWORK` reaches the mobile app as `report.chain.network`
(set once, at anchor time) and both `ReportCompleteScreen` and `VerifyScreen`
key their block-explorer link off that same value via
`mobile/lib/utils/block_explorer.dart` — a network not in that small known
map (e.g. `localhost`/`hardhat` during dev) simply renders no link, rather
than a broken one. Confirmed directly in Phase 12: the same backend
container was pointed at `localhost` and then at `sepolia` with only an
`.env` edit + `docker compose up -d backend` between them, no rebuild, no
mobile code touched.

## Running all three services

```bash
docker compose up -d --build   # first time, or after a Dockerfile/dependency change
docker compose up -d           # routine start (no image rebuild)
docker compose up -d backend   # after only an .env change (see above)
docker compose logs -f backend # tail backend logs — this is where the
                                # finalize pipeline's [finalize:<step>] lines
                                # and Socket.IO activity show up
docker compose down            # stop everything (add -v to also wipe the
                                # Mongo volume and the Hardhat node's
                                # in-memory chain state)
```

Services: `mongo` (MongoDB 7, volume-persisted at `mongo-data`, exposed on
`27017`), `hardhat` (`npx hardhat node`, exposed on `8545`, **in-memory —
every restart/rebuild wipes it and un-deploys the contract**), `backend`
(Express + Socket.IO on `3000`, depends on both).

## Running the mobile app

Read `Env.apiUrl` from `--dart-define=API_URL=...` — never hardcoded. Which
`API_URL` you pass depends on how you're reaching the backend, not on which
chain network the backend is anchoring to (`CHAIN_NETWORK` is a
backend-only setting; the same mobile build works against a `localhost`- or
`sepolia`-configured backend without any mobile-side change).

```bash
cd mobile
flutter pub get   # first time only
```

**Android emulator** (the standard "party A" role for this project's own
two-device testing — see docs/master_plan.md §7):
```bash
flutter run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:3000
```
`10.0.2.2` is the emulator's standard alias for the host loopback.

**USB-connected physical device** (the standard "party B" role):
```bash
adb reverse tcp:3000 tcp:3000   # once per USB (re)connect — does not
                                 # survive a disconnect/reconnect, since the
                                 # device's transport_id changes
flutter run -d <device-id> --dart-define=API_URL=http://localhost:3000
```

**Chrome** (used during development in place of a flaky emulator on this
machine — see PROGRESS.md Phase 7):
```bash
flutter run -d chrome --dart-define=API_URL=http://localhost:3000
```

**Never run two `flutter run` invocations concurrently** against this
project — they share `mobile/build/` and can corrupt a concurrent Gradle
build. Finish one device's build before starting the next.

Pairing: the session-creating device renders a QR code (the raw 6-character
session code, no URI scheme); the joining device scans it with its camera,
or enters the 6 characters manually. No LAN/Wi-Fi networking is needed or
used anywhere in this setup.

## Testnet deploy (Sepolia)

`blockchain/hardhat.config.js` already has a `sepolia` network entry
reading `RPC_URL`/`PRIVATE_KEY` from the environment — no code change is
needed to target it, only `.env`.

1. **Fund a signer wallet.** Generate (or reuse) an Ethereum keypair for
   the backend to sign with, then fund its address with Sepolia test ETH
   via a faucet — this project used the
   [Google Cloud Web3 Sepolia faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia).
   **Never commit this key.** Treat it exactly like the local Hardhat key:
   it lives only in `.env` (gitignored), never printed to logs or chat.
2. **Point `.env` at Sepolia:**
   ```
   RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
   PRIVATE_KEY=<the funded wallet's private key>
   ```
   (`CONTRACT_ADDRESS`/`CHAIN_NETWORK` get set in the next two steps.)
3. **Deploy:**
   ```bash
   cd blockchain
   npx hardhat run scripts/deploy.js --network sepolia
   cd ..
   ```
   This submits a real transaction and costs real (test) gas — takes
   longer than the instant local deploy. Prints the deployed address and
   writes the ABI to `backend/src/abi/AccidentRegistry.json`, same as the
   local flow.
4. **Update `.env`:**
   ```
   CONTRACT_ADDRESS=<the printed address>
   CHAIN_NETWORK=sepolia
   ```
5. **Recreate the backend and confirm:**
   ```bash
   docker compose up -d backend
   curl http://localhost:3000/api/health
   # { "mongo": "ok", "chain": "ok", "contract": "0x...", "network": "sepolia" }
   ```

A real anchor + tamper/verify round-trip against this exact setup is
recorded in PROGRESS.md (Phase 12), with the resulting tx hash, block
number, and `sepolia.etherscan.io` link.

**Running `backend/scripts/tamper.js` against a live stack**: it needs
`config.MONGO_URI` to resolve, which (per the table above) is the
`mongo` service hostname — only resolvable *inside* the docker compose
network, not from the host. Run it inside the backend container:
```bash
docker compose exec backend node scripts/tamper.js <reportId> [--photo]
```
(A bare `node scripts/tamper.js` from the host — from either the repo root
or `backend/` — will fail: from `backend/` there's no `backend/.env` for
`dotenv` to find, and from the repo root it finds `.env` but then can't
resolve the `mongo` hostname. This is a real operational gotcha, not a
typo — see PROGRESS.md Phase 12.)

**Switch back to local Hardhat values afterward** so routine dev work
doesn't stay pointed at a public testnet:
```
RPC_URL=http://hardhat:8545
CONTRACT_ADDRESS=<your local deploy's address>
PRIVATE_KEY=<Hardhat's well-known default account #0 key>
CHAIN_NETWORK=localhost
```
then `docker compose up -d backend` again.

## Running the tests

```bash
# Contract tests
cd blockchain
npx hardhat test

# Backend integration tests (need a real Mongo — the dockerized one works)
docker compose up -d mongo
cd backend
npm install   # first time only
npm test

# Mobile static analysis + widget tests
cd mobile
flutter analyze
flutter test --dart-define=API_URL=http://localhost:3000
```

`flutter test` needs `--dart-define=API_URL=...` even though the tests
don't hit the network — without it `Env.apiUrl` is empty and `main.dart`
renders its "missing API_URL" error screen instead of `Home`, which the
widget test asserts against.

## Demo script

The eight-step defense demo (docs/master_plan.md §9). Steps 1 and 5–8 were
re-run for real as part of Phase 12 (Sepolia, not local Hardhat — see
PROGRESS.md for the exact tx hash/block/report id); **steps 2–4 involve two
live devices and were not re-run this phase** — they were carried out
end-to-end multiple times in Phases 6–11's own live testing (see
PROGRESS.md decisions for those phases), most recently as two complete
sealed reports in Phase 11's live two-device pass.

1. **Bring the stack up and prove it's live:**
   ```bash
   docker compose up -d
   curl http://localhost:3000/api/health
   ```
2. **Pair the two devices.** Party A (emulator) creates a session — the app
   renders a QR code and the 6-character fallback. Party B (the
   USB-connected physical phone) scans that QR off the emulator's screen
   with its real camera, or enters the code manually.
3. **Both fill their half of the report.** Accident details, driver/
   vehicle/insurer/policyholder info, circumstances — point out the
   `SessionProgressHeader`'s live "other driver is on step Y" indicator as
   evidence of the Socket.IO sync.
4. **Add photos and a scene sketch; review; both sign.** Review shows the
   full assembled report from both sides and each party's live
   confirmation state; the report locks the instant both signatures are
   in.
5. **Show the finalize log, then the transaction on a public explorer:**
   ```bash
   docker compose logs -f backend   # watch the [finalize:<step>] lines:
                                     # validate → lock → pdf → hash → store
                                     # → attachments → bundle → derive →
                                     # anchor → seal
   ```
   Then open the tx hash from the sealed report (or from `report:sealed`
   directly on-screen) at `https://sepolia.etherscan.io/tx/<txHash>` — or
   tap "Pogledaj na blok exploreru" on the app's own Report Complete /
   Verify screens, which link there automatically when `CHAIN_NETWORK` is
   a public testnet.
6. **Open the Verify screen → VERIFIED.** Recomputed PDF hash and bundle
   hash both match the on-chain record.
7. **Tamper with the stored file, not the database record:**
   ```bash
   docker compose exec backend node scripts/tamper.js <reportId>
   # or: docker compose exec backend node scripts/tamper.js <reportId> --photo
   ```
   This flips one byte of the stored PDF (or swaps a photo) directly in
   GridFS — the `Report` document's own `pdf.sha256`/`attachmentHashes`
   fields are left untouched, exactly as if only the file store, not the
   database, had been compromised.
8. **Re-run Verify → TAMPERED**, with the specific affected file/hash
   flagged (`pdf.match: false` for a tampered PDF, or the specific
   attachment entry's `match: false` for a swapped photo) — recomputed
   hash no longer equals the on-chain hash, even though the database's own
   `storedHash` field still does (proving the check isn't just comparing
   two database fields against each other).

That last pair of steps is the entire argument of the thesis made visible
in well under a minute.

## Acceptance checklist

See PROGRESS.md for the full item-by-item walkthrough (what was
demonstrated, what's a known/documented gap, and exactly what was checked
for each).
