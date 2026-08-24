---
paths: ["backend/**"]
---

# Backend rules

## Socket.IO event contract (§5.3)

Room name = the session's `_id` (string). A socket joins via `socket.join(sessionId)`
inside the `session:join` handler; `socket.data.sessionId`/`socket.data.party`
are set there and read by every later handler on that connection — a socket
that hasn't called `session:join` yet gets a `NOT_JOINED` error from
`report:patch`/`party:ready`.

Implemented in `src/sockets/session.socket.js`, one `registerSessionHandlers(io)`
call wires everything.

| Direction | Event | Payload | Notes |
|---|---|---|---|
| C→S | `session:join` | `{sessionId, party}` | `party` is `"A"` \| `"B"`, client-asserted (no auth). Sets `session.partyX.socketId`/`joinedAt`, persists, joins the room. |
| S→C | `session:state` | `{session, report}` | Sent only to the joining socket, right after `session:join`. This is the reconnect-resync path — always reflects the latest persisted Mongo state, not any in-memory cache. |
| C→S | `report:patch` | `{path, value}` | Dot-notation path, e.g. `partyA.vehicle.plate`. Applied via `report.set(path, value)` (Mongoose native dot-path setter) then `report.save()`. |
| S→C | `report:patched` | `{path, value, by}` | Broadcast to the **whole room including the sender** — the sender's own patch is echoed back as the save-confirmed value, not skipped. |
| C→S | `party:ready` | `{party, stage}` | Sets `session.partyX.ready = true` and persists. `stage` is **not** persisted (no schema field for it) — it's forwarded as-is in the broadcast, purely for the client's "other driver is on step Y" header. |
| S→C | `party:status` | `{party, stage, ready}` | Broadcast to the room on both `session:join` (stage: null) and `party:ready`. |
| S→C | `report:locked` | — (no payload) | Phase 8: emitted by `report-lock.service.js`'s `maybeLockReport` once both parties have `confirmedReview` **and** a stored `signature.fileId`. Checked after every accepted `report:patch` (`session.socket.js`) and after every signature REST upload (`uploads.js`, the one write path the socket handler never sees). Idempotent — a no-op once `report.status` is already at or past `"signing"`. |
| S→C | `report:progress` | `{step, status, error?, txHash?, skipped?}` | Phase 10: emitted by `finalize.service.js`'s `runFinalize` at the start (`status: "active"`) and end (`"done"`/`"error"`) of each §5.4 pipeline step. `step` is one of `validate`/`lock`/`pdf`/`hash`/`store`/`attachments`/`bundle`/`derive`/`anchor`/`seal` — an opaque key, same convention as `party:ready`'s `stage`: the server never sends a display label, clients own their own copy of what each key means. On an anchor-only retry (see below), the already-durable steps (`lock` through `bundle`) are replayed as instantly-`"done"` events with `skipped: true` rather than staying silent, so a client that only tracks what it's seen over the socket doesn't render them as stuck pending. |
| S→C | `report:sealed` | `{pdfFileId, txHash, blockNumber, contractAddress, network, anchoredAt}` | Phase 10. Extends the minimal shape in docs/master_plan.md §5.3 (`{pdfFileId, txHash, blockNumber}`) with the rest of the `chain` record, so **every** connected client — not just whichever one's own `POST /finalize` happened to complete the pipeline — can render the full sealed state without a follow-up REST call. Broadcast to the whole room once, from `runFinalize`'s step 10. |
| S→C | `session:error` | `{code, message}` | Emitted to the offending socket only (never broadcast). Known codes: `INVALID_PARTY`, `SESSION_NOT_FOUND`, `NOT_JOINED`, `INVALID_PATCH`, `FORBIDDEN_PATCH`, `SESSION_LOCKED`, `REPORT_NOT_FOUND`, `REPORT_SEALED`, `REPORT_LOCKED`, `INTERNAL_ERROR`. |

Two REST routes also broadcast `report:patched` themselves (`uploads.js`'s
`broadcastPatch` helper), reusing the same `{path, value, by}` shape a
client-originated patch produces even though no client ever sent one: photo
upload/delete (`path: "photos"`, the full updated array — safe here even
though a *client*-initiated patch to `photos` is rejected, see rule 1 below,
because this is the server's own already-persisted state, not
client-supplied last-write-wins) and signature upload (`path:
"partyX.signature"`, `{fileId, signedAt}`). Needed so Review (Phase 8) and
any reconnect-free client see both parties' photos/signatures live.

### The three patch rules, as implemented

1. **Own-subtree only.** `classifyPatchPath()` in `session.socket.js` maps a path's
   top-level segment to `partyA`/`partyB` (owned) or `accident`/`sketch` (shared).
   Anything else (`status`, `chain`, `pdf`, `bundleHash`, `photos`, ...) returns
   `null` and is rejected with `INVALID_PATCH` — those fields are server-controlled
   and were never meant to go through this generic patch mechanism.
2. **Shared subtrees, last-write-wins.** `accident.*` and `sketch`/`sketch.*` are
   patchable by either party; there's no merge logic, the later `.save()` simply
   wins. Broadcast still carries `by` so clients can show who made the change.
3. **Persist-then-broadcast.** Every patch is saved to Mongo *before* the
   `report:patched` broadcast, specifically so a client that reconnects mid-session
   and calls `session:join` again always sees every prior patch in `session:state`.

### Sealed/locked guard

One guard, two call sites — both defined in `src/services/report-guard.service.js`:
- `assertReportNotSealed(report)` — throws `SealedReportError` (code
  `REPORT_SEALED`) if `report.status === "sealed"`, or `ReportLockedError`
  (code `REPORT_LOCKED`, Phase 8) if `report.status` is any other
  `LOCKED_STATUSES` value (`signing`/`finalizing`/`abandoned`). Called
  directly inside `report:patch`.
- `requireUnsealedReport` — Express middleware wrapping the same assertion,
  used by every mutating REST route (photos/sketch/signature) since Phase 7/8.

Separately, `report:patch` also rejects when `session.status` is in
`LOCKED_STATUSES` (`signing`, `finalizing`, `sealed`, `abandoned` — see
`src/models/statuses.js`), per §5.3's "reject all patches when status is
signing or later." This is a **session**-level gate distinct from the
**report**-level sealed/locked guard; both run on every patch. From Phase 8
on, both gates trip together — see `report-lock.service.js` below.

### Locking (Phase 8)

`src/services/report-lock.service.js`'s `maybeLockReport(report, session,
io)` is the single place that decides "both sides are done": both
`partyA`/`partyB.confirmedReview` true **and** both
`partyA`/`partyB.signature.fileId` set. When that becomes true it sets
**both** `Report.status` and `Session.status` to `"signing"` (in the same
call — this is what keeps them in sync from this transition on, see below)
and emits `report:locked`. It's idempotent (a no-op once `report.status` is
already at or past `"signing"`), so callers don't need to figure out
whether *their* write was the one that completed the pair — just call it
after any write that could plausibly contribute: after every accepted
`report:patch` in `session.socket.js`, and after a signature REST upload in
`uploads.js`.

### Finalize pipeline (Phase 10)

`src/services/finalize.service.js`'s `runFinalize(reportId, io)` is the
single entry point for `POST /api/reports/:id/finalize`
(`src/routes/reports.js`) and implements §5.4 steps 1-10 as one ordered,
logged (`console.log("[finalize:<step>] <status>")`, one line per step —
this is deliberately verbose, it's the defense-demo log) sequence. It is
**not** gated by `report-guard.service.js`'s `requireUnsealedReport` — that
middleware rejects every `LOCKED_STATUSES` value including `"signing"` and
`"finalizing"`, which are exactly the two statuses this route must accept.
Instead it does its own status check:

- `"sealed"` → no-op, returns the already-sealed report (200). Lets either
  party's late/duplicate call behave like a harmless read.
- `"signing"` → runs the full pipeline (generate → hash → store → hash
  attachments → bundle → derive → anchor → seal).
- `"finalizing"` with `pdf.fileId` **and** `bundleHash` already stored → a
  prior attempt got through storage but the anchor call (step 9) never
  confirmed. Retries **only** steps 8-10 (derive/anchor/seal) — the PDF is
  not regenerated, per §5.4's explicit "retry only re-runs the anchor step."
- `"finalizing"` without a stored PDF yet (e.g. the process died mid-pipeline
  before anything durable saved) → re-runs the full pipeline, same as
  `"signing"`.
- anything else (`"waiting"`/`"joined"`/`"filling"`/`"review"`/`"abandoned"`)
  → rejected `409 INVALID_STATUS`.
- both parties not actually signed off (defense-in-depth re-check of §5.4
  step 1, independent of the status gate) → rejected `409 NOT_READY`.

**Concurrency**: a per-report in-memory `Set` in `finalize.service.js`
serializes calls for the same report within this one Node process (no
clustering per docker-compose §7) — both parties' clients may call finalize
around the same moment (each auto-triggers on reaching the Finalizing
screen), and this makes the loser's call a cheap `202 {status:
"finalizing"}` no-op instead of a second concurrent pipeline run (double PDF
generation, or two concurrent `anchor()` sends racing for the same nonce).
The loser is expected to fall back to `report:progress`/`report:sealed`
rather than treating the 202 as an error.

**On anchor failure**: `report.chain.lastError` is set and `report.status`
stays `"finalizing"` (never sealed without a confirmed receipt) — this is
what a reconnecting client reads to show the error state without having had
to be listening live for the `report:progress` broadcast. Cleared back to
`null` at the start of every fresh pipeline run and on a successful anchor.

**reportId → bytes32**: `chain.service.js`'s `deriveReportId32(reportId)` is
`ethers.id(String(reportId))` — i.e. `keccak256(utf8Bytes(<24-char hex
ObjectId string>))`. Chosen over left-padding the raw 12 ObjectId bytes to
32 specifically so verify (Phase 11) only needs the report's string id (no
byte-order/padding convention to get right) to reproduce the exact same
value. See PROGRESS.md Decisions.

**Chain signer**: `chain.service.js`'s write-capable contract (`getSignerContract()`,
wrapping `new ethers.Wallet(config.PRIVATE_KEY, provider)`) is built lazily
on first use, not at module load — `config.PRIVATE_KEY` is a
syntactically-valid-but-cryptographically-invalid all-zeros placeholder in
both `.env.example` and `test/setupEnv.js`, and `ethers.Wallet` throws
immediately for that value. Every route that only reads the chain (health)
or doesn't touch it at all (sessions/reports/uploads/sockets) requires this
module transitively through `app.js`, so eager construction would crash the
entire test suite and any real deployment that hasn't set a real key yet,
not just finalize. Only an actual `anchorReport()` call needs a real funded
key — set in `backend/.env` (not `.env.example`) to Hardhat's well-known
default account #0 test key for local dev, matching the deployed contract
address already there (both are deterministic outputs of the same default
Hardhat account).

## Known scope gaps (intentional, left for later phases)

- `Session.status` only ever reaches `"waiting"` (on create), `"joined"`
  (on REST join), `"signing"` (Phase 8's `maybeLockReport`, once locked), or
  `"sealed"` (Phase 10's `runFinalize`, step 10 — set alongside
  `Report.status` in the same call) right now. Nothing auto-advances it
  through `filling`/`review` — that will land with the routes/UI that
  actually drive those transitions. Don't assume `party:ready` advances
  `status`; it only flips the per-party `ready` flag and rebroadcasts.
- `GET /api/reports?deviceId=` is accepted but a no-op — `Report`/`Session`
  schemas (§5.1) have no `deviceId` field. `?plate=` works.
