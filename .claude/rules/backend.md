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
| S→C | `report:locked` | — | Not emitted yet — no handler sets it. Wire this up in the signatures phase (§6 screen 11 / Phase 8) once both signatures land. |
| S→C | `report:sealed` | `{pdfFileId, txHash, blockNumber}` | Not emitted yet — belongs to the finalize pipeline (§5.4 / Phase 10). |
| S→C | `session:error` | `{code, message}` | Emitted to the offending socket only (never broadcast). Known codes: `INVALID_PARTY`, `SESSION_NOT_FOUND`, `NOT_JOINED`, `INVALID_PATCH`, `FORBIDDEN_PATCH`, `SESSION_LOCKED`, `REPORT_NOT_FOUND`, `REPORT_SEALED`, `INTERNAL_ERROR`. |

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

### Sealed guard

One guard, two call sites — both defined in `src/services/report-guard.service.js`:
- `assertReportNotSealed(report)` — throws `SealedReportError` if `report.status === "sealed"`. Called directly inside `report:patch`.
- `requireUnsealedReport` — Express middleware wrapping the same assertion for
  future mutating REST routes (photos/sketch/signature/finalize). Not wired to
  any route yet since none of those routes exist as of Phase 3 — import and use
  it, don't re-implement the check.

Separately, `report:patch` also rejects when `session.status` is in
`LOCKED_STATUSES` (`signing`, `finalizing`, `sealed`, `abandoned` — see
`src/models/statuses.js`), per §5.3's "reject all patches when status is
signing or later." This is a **session**-level gate distinct from the
**report**-level sealed guard; both run on every patch.

### Known scope gaps (intentional, left for later phases)

- `Session.status` only ever reaches `"waiting"` (on create) or `"joined"`
  (on REST join) right now. Nothing auto-advances it to `filling`/`review`/
  `signing`/`finalizing`/`sealed` — that will land with the routes/UI that
  actually drive those transitions (review confirmation, signatures, finalize).
  Don't assume `party:ready` advances `status`; currently it only flips the
  per-party `ready` flag and rebroadcasts.
- `Session.status` and `Report.status` are **not** kept in sync with each
  other. They start independently at `"waiting"`. Decide the sync strategy
  before Phase 8/10 needs both to agree.
- `GET /api/reports?deviceId=` is accepted but a no-op — `Report`/`Session`
  schemas (§5.1) have no `deviceId` field. `?plate=` works.
