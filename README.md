# Accident Report App

A bachelor-thesis project: a mobile app that digitizes the European Accident
Statement, lets two drivers jointly fill and sign a report in a shared live
session, generates a PDF, stores it in MongoDB, and anchors its SHA-256 hash
on a blockchain so the report is provably unaltered.

See [CLAUDE.md](CLAUDE.md) for the tech stack and hard invariants, and
[docs/master_plan.md](docs/master_plan.md) for the full implementation plan.

## Running locally

1. Copy the env template and fill in the placeholders you need:
   ```
   cp .env.example .env
   ```
2. Start Mongo, the local Hardhat node, and the backend:
   ```
   docker compose up -d --build
   ```
   At this point `GET http://localhost:3000/api/health` will report `chain`
   as an error — no contract is deployed at the placeholder address yet.
3. Deploy `AccidentRegistry` to the local node (from the host, against the
   port docker compose exposed):
   ```
   cd blockchain
   npm install   # first time only
   npx hardhat run scripts/deploy.js --network localhost
   ```
   This prints the deployed contract address and writes the ABI to
   `backend/src/abi/AccidentRegistry.json`.
4. Copy the printed address into `.env` as `CONTRACT_ADDRESS`.
5. Restart the backend so it picks up the new address — use `up`, not
   `restart`, since only `up` re-reads `.env`. **Don't add `--build` here**:
   because `backend` depends on `hardhat`, `--build` also rebuilds and
   recreates the `hardhat` container, which wipes its in-memory chain and
   un-deploys the contract you just anchored the address to.
   ```
   docker compose up -d backend
   ```
6. Confirm the whole stack is live:
   ```
   curl http://localhost:3000/api/health
   ```
   A healthy response looks like:
   ```json
   { "mongo": "ok", "chain": "ok", "contract": "0x...", "network": "localhost" }
   ```
