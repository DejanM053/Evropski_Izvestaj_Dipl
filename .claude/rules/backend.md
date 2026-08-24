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
| S→C | `report:sealed` | `{pdfFileId, txHash, blockNumber}` | Not emitted yet — belongs to the finalize pipeline (§5.4 / Phase 10). |
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

### Known scope gaps (intentional, left for later phases)

- `Session.status` only ever reaches `"waiting"` (on create), `"joined"`
  (on REST join), or `"signing"` (Phase 8's `maybeLockReport`, once locked)
  right now. Nothing auto-advances it through `filling`/`review` — that
  will land with the routes/UI that actually drive those transitions.
  Don't assume `party:ready` advances `status`; it only flips the
  per-party `ready` flag and rebroadcasts.
- `Session.status` and `Report.status` are only kept in sync for the
  `"signing"` transition (Phase 8's `maybeLockReport`, which sets both
  together). Before that point they can still independently be `"waiting"`
  vs `"joined"` etc. — the general sync strategy for the rest of the
  lifecycle is still open, for Phase 10 (finalize/seal) to decide.
- `GET /api/reports?deviceId=` is accepted but a no-op — `Report`/`Session`
  schemas (§5.1) have no `deviceId` field. `?plate=` works.
