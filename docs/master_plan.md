# Master Implementation Prompt — Roadside Accident Report App

## 0. Role & goal

You are implementing a complete, working bachelor-thesis project: a mobile app that digitizes the European Accident Statement ("blue-yellow report" / evropski izveštaj), lets two drivers jointly fill and sign a report in a shared live session, generates a PDF, stores documents in MongoDB, and anchors their SHA-256 hashes on a blockchain so the reports are provably unaltered.

**Build for correctness and demonstrability, not for production scale.** No Kubernetes, no microservices, no auth providers, no CI/CD, no analytics. Every feature below must actually work end to end and be demonstrable in a live defense. Prefer boring, well-documented libraries over clever ones. Write code a reviewer can read.

---

## 1. Design import (do this first)

Use the claude_design MCP (https://api.anthropic.com/v1/design/mcp, auth via /design-login) to import this project:
https://claude.ai/design/p/78016f84-06e4-4866-bbc0-818cdb195c9d?file=Accident+Report+App.dc.html
Focus on these files (the whole project is readable):
- `Accident Report App.dc.html`
Also read these files the selection imports:
- `android-frame.jsx`
- `support.js`
Implement: `Accident Report App.dc.html`

**How to use the design:** extract the design system first — color tokens, type scale, spacing scale, border radii, and the component set (buttons, inputs, checkbox grid, cards, status chips, signature pad, headers). Encode these as a Flutter `ThemeData` plus a small set of reusable widgets in `lib/theme/` and `lib/widgets/` **before** building screens. Every screen must then be assembled from those shared widgets — do not restyle per screen. Match the design's screens 1:1 (see §6). If the design lacks a state the app needs (loading, error, offline, empty), derive it from the existing tokens rather than inventing new styling.

---

## 2. Tech stack (fixed — do not substitute)

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

Key Flutter packages: `qr_flutter`, `mobile_scanner`, `signature`, `image_picker`, `socket_io_client`, `dio` or `http`, `provider` or `riverpod` (pick one, use it consistently), `path_provider`, `open_filex`.

**Users never touch a wallet.** The backend holds a single funded key and submits all transactions. No user accounts, no passwords, no KYC — identity in a report is just typed-in data plus a signature.

---

## 3. Repository structure

```
accident-report/
├── docker-compose.yml
├── .env.example
├── README.md                  # setup + demo script
├── blockchain/
│   ├── contracts/AccidentRegistry.sol
│   ├── scripts/deploy.js
│   ├── test/registry.test.js
│   ├── hardhat.config.js
│   └── Dockerfile
├── backend/
│   ├── src/
│   │   ├── index.js           # express + socket.io bootstrap
│   │   ├── config.js          # env loading/validation
│   │   ├── models/            # mongoose schemas
│   │   ├── routes/            # REST controllers
│   │   ├── sockets/           # session room handlers
│   │   ├── services/
│   │   │   ├── pdf.service.js
│   │   │   ├── hash.service.js
│   │   │   ├── chain.service.js
│   │   │   └── storage.service.js   # GridFS wrapper
│   │   └── abi/AccidentRegistry.json
│   ├── package.json
│   └── Dockerfile
└── mobile/                    # flutter app
    └── lib/
        ├── main.dart
        ├── theme/             # tokens from Claude Design
        ├── widgets/           # shared components
        ├── models/            # dart mirrors of backend schemas
        ├── services/          # api_client, socket_client, local_store
        └── screens/           # one folder per screen in §6
```

---

## 4. Smart contract (Phase 1 — build and test this first)

`AccidentRegistry.sol`. Keep it minimal; **never store personal data on-chain — only hashes, IDs, and timestamps.**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AccidentRegistry {
    struct Record {
        bytes32 pdfHash;
        bytes32 bundleHash;   // hash over all attachment hashes
        uint256 timestamp;
        address submitter;
    }

    mapping(bytes32 => Record) private records;

    event ReportAnchored(
        bytes32 indexed reportId,
        bytes32 pdfHash,
        bytes32 bundleHash,
        uint256 timestamp
    );

    function anchor(bytes32 reportId, bytes32 pdfHash, bytes32 bundleHash) external {
        require(records[reportId].timestamp == 0, "already anchored");
        records[reportId] = Record(pdfHash, bundleHash, block.timestamp, msg.sender);
        emit ReportAnchored(reportId, pdfHash, bundleHash, block.timestamp);
    }

    function getRecord(bytes32 reportId)
        external view returns (bytes32, bytes32, uint256, address)
    {
        Record memory r = records[reportId];
        require(r.timestamp != 0, "not found");
        return (r.pdfHash, r.bundleHash, r.timestamp, r.submitter);
    }

    function verify(bytes32 reportId, bytes32 pdfHash) external view returns (bool) {
        return records[reportId].pdfHash == pdfHash && records[reportId].timestamp != 0;
    }
}
```

Hardhat tests (`npx hardhat test`) must cover: successful anchor + event emission; rejection of a duplicate anchor for the same `reportId`; `verify` returns true for the correct hash and false for a tampered one; `getRecord` reverts for an unknown ID. Deploy script writes the address to stdout and to `backend/src/abi/` alongside the ABI.

---

## 5. Backend

### 5.1 Data model (Mongoose)

**`Session`** — ephemeral coordination object.
```
_id, sessionCode (6-char, human-readable, uppercase),
status: 'waiting' | 'joined' | 'filling' | 'review' | 'signing' | 'finalizing' | 'sealed' | 'abandoned',
partyA: { socketId, joinedAt, ready }, partyB: { ... },
reportId (ObjectId), createdAt, expiresAt (TTL index, e.g. 24h)
```

**`Report`** — the domain object.
```
_id, sessionId, status,
accident: { dateTime, location {address, lat, lng}, injuries: bool,
            otherVehicleDamage: bool, thirdPartyDamage: bool, witnesses: [{name, phone}] },
partyA: {
  driver:   { firstName, lastName, address, phone, email, licenceNumber, licenceCategory, licenceValidUntil },
  vehicle:  { make, model, plate, country, vin },
  insurer:  { company, policyNumber, greenCardNumber, validFrom, validTo, agency },
  policyholder: { name, address, phone },   // if different from driver
  circumstances: [int],                      // indices of checked boxes
  visibleDamage: string,
  remarks: string,
  signature: { fileId, signedAt },
  confirmedReview: bool
},
partyB: { ...same shape... },
sketch: { fileId },                 // PNG of scene diagram
photos: [{ fileId, caption, party, takenAt }],
pdf: { fileId, sha256, generatedAt },
attachmentHashes: [{ fileId, sha256, kind }],
bundleHash,
chain: { txHash, blockNumber, contractAddress, network, anchoredAt },
createdAt, sealedAt
```

Once `status === 'sealed'`, the report is immutable: **all mutating routes and socket handlers must reject writes to a sealed report.** Enforce this in one place (middleware/guard), not scattered.

### 5.2 REST endpoints

```
POST   /api/sessions                      -> create session, returns {sessionId, sessionCode, reportId}
POST   /api/sessions/:code/join           -> join as party B
GET    /api/sessions/:id                  -> current session + report state
POST   /api/reports/:id/photos            -> multipart upload -> GridFS, returns fileId + sha256
POST   /api/reports/:id/sketch            -> PNG upload
POST   /api/reports/:id/signature         -> PNG upload, {party}
POST   /api/reports/:id/finalize          -> generate PDF, hash, store, anchor on-chain
GET    /api/reports/:id                   -> full report JSON (incl. chain info)
GET    /api/reports/:id/pdf               -> stream PDF from GridFS
GET    /api/reports/:id/verify            -> integrity check result (see 5.5)
GET    /api/reports                       -> history list (filter by ?deviceId= or ?plate=)
GET    /api/files/:fileId                 -> stream any stored file
GET    /api/health                        -> {mongo: ok, chain: ok, contract: address}
```

`/api/health` matters more than it looks — it's how you prove the whole stack is live during the demo.

### 5.3 Socket.IO — live session sync

Room name = `sessionId`. Events:

| Direction | Event | Payload |
|---|---|---|
| C→S | `session:join` | `{sessionId, party}` |
| S→C | `session:state` | full session + report snapshot (sent on join) |
| C→S | `report:patch` | `{path, value}` — e.g. `partyA.vehicle.plate` |
| S→C | `report:patched` | `{path, value, by}` — broadcast to the room |
| C→S | `party:ready` | `{party, stage}` |
| S→C | `party:status` | `{party, stage, ready}` — drives the "other driver is filling in…" header |
| S→C | `report:locked` | emitted when both signatures are in |
| S→C | `report:sealed` | `{pdfFileId, txHash, blockNumber}` |
| S→C | `session:error` | `{code, message}` |

Rules: a party may only patch **its own** subtree (`partyA.*` for A, `partyB.*` for B); shared subtrees (`accident.*`, `sketch`) are patchable by both, last-write-wins with broadcast. Persist every patch to Mongo immediately so a reconnecting client recovers state via `session:state`. Reject all patches when status is `signing` or later.

### 5.4 Finalize pipeline (`POST /api/reports/:id/finalize`)

Run as an ordered, logged pipeline — each step must be visible in server logs for the demo:

1. Validate both parties have `confirmedReview` and a stored signature. Reject otherwise.
2. Set status `finalizing`; lock the report.
3. Generate the PDF (§5.6) → buffer.
4. `sha256(pdfBuffer)` → `pdf.sha256`.
5. Store the PDF in GridFS → `pdf.fileId`.
6. Compute `sha256` of every attachment (photos, sketch, both signature PNGs) → `attachmentHashes`.
7. `bundleHash = sha256(concat(sorted(attachmentHashes)))`.
8. `reportId32 = bytes32` derived from the Mongo `_id` (pad/hash it deterministically — document the choice).
9. Call `anchor(reportId32, pdfHash, bundleHash)`; await the receipt; store `txHash`, `blockNumber`, `contractAddress`, `network`.
10. Status → `sealed`, set `sealedAt`, emit `report:sealed`.

If step 9 fails (RPC down, out of gas), leave status `finalizing`, store the error, and expose a retry — do **not** silently mark it sealed. The PDF already exists at that point, so retry only re-runs the anchor.

### 5.5 Verification (`GET /api/reports/:id/verify`)

This is the thesis centerpiece. Implementation:

1. Pull the PDF bytes back out of GridFS.
2. Recompute SHA-256.
3. Read the on-chain record via `getRecord(reportId32)`.
4. Recompute every attachment hash and rebuild `bundleHash`.
5. Return:
```json
{
  "reportId": "...",
  "pdf":   { "storedHash": "...", "recomputedHash": "...", "onChainHash": "...", "match": true },
  "bundle":{ "recomputedHash": "...", "onChainHash": "...", "match": true },
  "attachments": [ { "fileId": "...", "kind": "photo", "match": true } ],
  "chain": { "txHash": "...", "blockNumber": 123, "network": "sepolia", "anchoredAt": "..." },
  "verdict": "VERIFIED" | "TAMPERED" | "NOT_ANCHORED"
}
```
Per-attachment results let you demonstrate *which* file was altered, not just that something was.

### 5.6 PDF generation

Layout must mirror the European Accident Statement so it's recognizable to a committee: header with report ID, date/time, location; two columns for Party A / Party B (driver, vehicle, insurer, policyholder); the circumstances grid with checked boxes marked and a per-column count; visible damage and remarks; witnesses; the embedded scene sketch; a photo appendix with captions; both signature images with timestamps; and a footer block containing the report ID, PDF SHA-256, contract address, network, and transaction hash in monospace.

Note in code (and in your thesis) the ordering subtlety: the tx hash cannot be inside the hashed PDF, since hashing must precede anchoring. Put the tx hash in a *separate* verification page/appendix appended after anchoring, or reference it only via the verify endpoint — pick one and document why. Simplest correct choice: the hashed PDF contains everything except chain data; chain data is shown in-app and on the verify screen.

---

## 6. Flutter app — screens

Build these to match the imported design, sharing the theme and widget set from §1.

1. **Home** — new report / history / verify entry points.
2. **Create session (A)** — QR (`qr_flutter`) + 6-char fallback code, waiting state, cancel.
3. **Join session (B)** — camera scan (`mobile_scanner`) + manual code entry with validation.
4. **Session shell** — persistent header with both parties' live stage/progress; wraps screens 5–9.
5. **Accident details** (shared) — date/time picker, location (GPS autofill + manual override), injuries/other-damage/third-party toggles, witnesses.
6. **My details** — driver, vehicle, insurer, policyholder; per-field validation (plate format, dates, required fields); patches stream over the socket as the user types (debounced ~400ms).
7. **Circumstances** — touch-friendly checkbox grid, live count per party, mirroring the statement's standard boxes.
8. **Sketch** — draggable car icons + impact-point marker on a road outline; export the canvas as PNG on save.
9. **Photos** — capture/pick, caption each, grid preview, delete before lock; upload immediately, show per-file progress.
10. **Review** — full assembled report from both sides, read-only, explicit "I confirm this is accurate" action; shows the other party's confirmation state live.
11. **Signature** — full-screen pad (`signature` package), clear/redo, submit; locked confirmation state once both are in.
12. **Finalizing** — honest step-by-step progress driven by real server events (generating PDF → hashing → storing → anchoring), with a retry path on failure.
13. **Report complete** — PDF preview/open/share, sealed indicator, monospace tx hash + copy button, block-explorer deep link when on a testnet.
14. **Verify** — pick a report, run verification, render VERIFIED / TAMPERED / NOT_ANCHORED states with the hash comparison shown side by side and per-attachment rows.
15. **History** — past reports (date, other party, plate, status), empty state, tap through to 13/14.

**Client rules:** store a locally generated `deviceId` (uuid, persisted) to scope history; never store secrets; treat the backend as the only source of truth; handle socket disconnect with reconnect + `session:state` resync and a visible "reconnecting" banner; block all edit affordances when status ≥ `signing`.

---

## 7. Infrastructure

`docker-compose.yml` with three services: `mongo` (volume-persisted), `hardhat` (`npx hardhat node --hostname 0.0.0.0`), `backend` (depends on both). Backend env: `MONGO_URI`, `RPC_URL`, `CONTRACT_ADDRESS`, `PRIVATE_KEY`, `CHAIN_NETWORK`, `PORT`. Provide `.env.example` with safe placeholders and never commit a real key.

Networking for the Flutter client: emulator → `http://10.0.2.2:3000`; USB device → `adb reverse tcp:3000 tcp:3000`; Wi-Fi → LAN IP. Read the base URL from `--dart-define=API_URL=...`, never hardcode.

---

## 8. Build order

| Phase | Deliverable | Done when |
|---|---|---|
| 1 | Contract + Hardhat tests | `npx hardhat test` green |
| 2 | Docker Compose + backend skeleton + `/api/health` | health returns mongo ok + contract address |
| 3 | Session + report CRUD + Socket.IO sync | two REST/WS clients see each other's patches |
| 4 | GridFS uploads + hashing | file upload returns a stable sha256 |
| 5 | Design system → Flutter theme + widgets | components render standalone |
| 6 | Screens 1–4 (session pairing) | two devices pair via QR |
| 7 | Screens 5–9 (form, circumstances, sketch, photos) | full report fillable from two devices |
| 8 | Screens 10–11 (review + signatures) | report locks after both sign |
| 9 | PDF generation | PDF matches the statement layout |
| 10 | Finalize + anchor + screens 12–13 | tx confirmed on local chain |
| 11 | Verify endpoint + screens 14–15 | tamper demo flips to TAMPERED |
| 12 | Testnet deploy + README + demo script | explorer link works publicly |

---

## 9. Testing & the defense demo

Automated: Hardhat contract tests; a handful of backend integration tests (create session → join → patch → sign → finalize → verify) using Jest + supertest against a test database; Flutter widget tests for the signature pad and circumstances grid.

**Demo script to include in the README** — rehearse this:
1. `docker compose up -d`, show `/api/health`.
2. Phone A creates a session; phone B scans the QR.
3. Both fill their halves — point out live sync in the header.
4. Add photos and sketch; review; both sign.
5. Show the finalize log: hash → store → anchor; show the tx on the block explorer.
6. Open the verify screen → **VERIFIED**.
7. In `mongosh`, flip one byte of the stored PDF (or swap a photo).
8. Re-run verify → **TAMPERED**, with the specific file flagged.

That last pair of steps is the entire argument of the thesis made visible in 30 seconds.

---

## 10. Out of scope (do not build)

User accounts, passwords, OAuth; user-held wallets or gas payment; insurance-company or police API integrations; multi-language i18n beyond a single locale; offline-first sync/CRDTs; push notifications; iOS build; admin dashboards; rate limiting, monitoring, CI/CD.

## 11. Acceptance checklist

- [ ] Two physical devices complete a report end to end over the network.
- [ ] Report becomes immutable after both signatures; server rejects late writes.
- [ ] PDF is generated and matches the statement structure with photos, sketch, and both signatures embedded.
- [ ] PDF and every attachment have stored SHA-256 hashes.
- [ ] Hash + bundle hash are anchored on-chain with a retrievable tx hash.
- [ ] No personal data is written on-chain.
- [ ] Verification passes on an untouched report and fails on a tampered one, identifying the affected file.
- [ ] `docker compose up` brings the whole backend stack up from a clean clone.
- [ ] README documents setup, env vars, deploy, and the demo script.