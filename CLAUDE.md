# Accident Report App

A bachelor-thesis project: a mobile app that digitizes the European Accident
Statement, lets two drivers jointly fill and sign a report in a shared live
session, generates a PDF, stores it in MongoDB, and anchors its SHA-256 hash
on a blockchain so the report is provably unaltered. Built for correctness
and demonstrability, not production scale.

## Tech stack (fixed — do not substitute)

| Layer | Choice |
|---|---|
| Mobile | Flutter (Dart), Android target, portrait only |
| Backend | Node.js 20 + Express + Socket.IO |
| Database | MongoDB 7 + GridFS (files) |
| Blockchain | Solidity + Hardhat (local dev), Ethereum testnet (Sepolia or Polygon Amoy) for final demo |
| Chain client | ethers.js v6 (server-side only) |
| PDF | pdf-lib or pdfkit (server-side) |
| Hashing | Node `crypto`, SHA-256 |
| Orchestration | Docker Compose (mongo, hardhat, backend) |

## Hard invariants

- Never write personal data on-chain — only hashes, IDs, and timestamps.
- A report with status `sealed` is immutable: all mutating routes and socket
  handlers must reject writes to it.
- Users never hold wallets — the backend signs and submits all transactions.

## Common commands

```
docker compose up -d                        # start mongo, hardhat, backend
cd blockchain && npx hardhat test           # run contract tests
cd blockchain && npx hardhat run scripts/deploy.js --network <net>
cd mobile && flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

Full implementation plan lives in docs/master_plan.md — read the relevant phase section before starting work.

@PROGRESS.md
