# Progress

## Current phase

**Feature-complete and confirmed end to end by the user.** All 12 phases
from master_plan.md §8 are done. Phase 12 (testnet deploy + README + demo
script + acceptance-checklist walkthrough) added the Sepolia deploy and the
full acceptance-checklist walkthrough — see its Decisions entry below.
A round of post-Phase-12 fixes (sketch step, a finalize-screen timeout
banner, and a real data-loss race condition affecting vehicle/insurer
fields) followed, found via the user's own live testing — see that
Decisions entry and "Project status" below for the real two-device Sepolia
run that confirmed all of it end to end through the actual mobile UI.

Phase 11 is done, confirmed both ways: first against the backend alone
(throwaway report, real Hardhat anchor, `scripts/tamper.js`, re-verify
TAMPERED), then for real on the actual two-device mobile UI (physical
phone + the user's own Chrome) — two real sessions were carried through to
sealed reports, and `scripts/tamper.js` was run against one of them
(`6a8c4964...99afb4`) while the other (`6a8c4846...99afa0`) was left
untouched as a control. See Decisions below for both passes.

## Phases (from master_plan.md §8)

- [x] Phase 0 — Repository restructure (mobile/backend/blockchain split, root config)
- [x] Phase 1 — Contract + Hardhat tests
- [x] Phase 2 — Docker Compose + backend skeleton + `/api/health`
- [x] Phase 3 — Session + report CRUD + Socket.IO sync
- [x] Phase 4 — GridFS uploads + hashing
- [x] Phase 5 — Design system → Flutter theme + widgets
- [x] Phase 6 — Screens 1–4 (session pairing)
- [x] Phase 7 — Screens 5–9 (form, circumstances, sketch, photos)
- [x] Phase 8 — Screens 10–11 (review + signatures)
- [x] Phase 9 — PDF generation
- [x] Phase 10 — Finalize + anchor + screens 12–13
- [x] Phase 11 — Verify endpoint + screens 14–15
- [x] Phase 12 — Testnet deploy + README + demo script

## Decisions

- Two-device testing standard is emulator (party A) + one USB-connected
  physical phone (party B), not two physical phones over Wi-Fi/LAN — updated
  master_plan.md §7/§9/§11 accordingly (networking note, demo script step 2,
  and the acceptance checklist item). Pairing works by scanning the QR the
  emulator renders on its window with the phone's real camera; no
  camera-passthrough emulator config or LAN setup needed. Chosen because
  it's simpler to set up for a bachelor-thesis proof of concept and Wi-Fi/AP
  isolation on unfamiliar networks (e.g. university Wi-Fi) is a real risk to
  demo-day reliability. Applies to Phases 6–12 dev testing and the final
  defense demo alike, not just routine development.
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
- GridFS attachments live in a single bucket named `attachments`
  (`attachments.files`/`attachments.chunks`), wrapped by
  `storage.service.js`. The bucket is built lazily per call from
  `mongoose.connection.db` rather than once at module load, since
  `storage.service.js` is required before `index.js`'s async Mongo connect
  resolves.
- `hash.service.computeBundleHash` sorts attachment sha256 hex strings
  lexicographically (not by fileId, kind, or insertion order) before
  concatenating and re-hashing — the only input to the sort is the hash
  values themselves, so verify (§5.5, Phase 11) can reproduce the same
  bundleHash from a freshly-recomputed attachment list without needing to
  reconstruct the original upload order. Documented in a comment in
  `hash.service.js`.
- Sketch and signature uploads are treated as single-slot-per-report (sketch)
  or single-slot-per-party (signature): re-uploading replaces the prior
  `attachmentHashes` entry (matched by the previous `fileId`, since
  `AttachmentHashSchema` has no `party` field) and best-effort deletes the
  orphaned GridFS blob via `storage.service.deleteFile`. Photos are additive
  — no replace logic, every upload is a new entry. Not tested by finalize
  yet (Phase 9/10 hasn't landed), but keeps `attachmentHashes` from
  accumulating stale entries if a party redoes their sketch or signature
  before finalizing.
- `report-guard.service.js`'s `requireUnsealedReport` didn't validate
  `req.params.id` as an ObjectId before (unused until this phase). Added an
  `isValid` check ahead of `findById` so a malformed id 404s like every
  other route, instead of throwing a Mongoose `CastError` into the generic
  500 handler.
- Upload validation (image/png + image/jpeg only, 10MB cap) lives entirely
  in `routes/uploads.js` via a `multer.memoryStorage()` instance wrapped in
  a custom `uploadSingle()` — multer's callback-style error (fileFilter
  rejection, `LIMIT_FILE_SIZE`) is caught there and turned into a 415/413
  directly, rather than relying on Express's error-middleware layer
  ordering, which is easy to get wrong when regular and error middleware
  are interleaved in one route's middleware array.
- Verified manually against the running Docker stack (not just Jest): `curl`
  multipart upload to `POST /api/reports/:id/photos` on a live
  `docker compose` backend, then `GET /api/files/:fileId`, confirmed
  byte-identical output and a matching `sha256sum`. Rebuilt only the
  `backend` image (`docker compose build backend` +
  `docker compose up -d --no-deps backend`) to pick up the new `multer`
  dependency — deliberately used `--no-deps` so `hardhat`'s in-memory chain
  (and the already-deployed contract) wasn't reset, per the existing
  `up -d backend`-without-`--build` note above.

- Design import used the `DesignSync` MCP tool's `get_file`/`list_files`
  methods directly against project `78016f84-06e4-4866-bbc0-818cdb195c9d`
  (type `PROJECT_TYPE_PROJECT`, not a design-system project) rather than the
  `claude_design` MCP server named in master_plan.md §1 — that server wasn't
  available in this session's tool set, but `DesignSync`'s read methods
  worked against the same project ID and returned the same three files
  (`Accident Report App.dc.html`, `android-frame.jsx`, `support.js`), so the
  extraction is from the same source either way.
- Fonts (Archivo, IBM Plex Sans, IBM Plex Mono, Caveat) are all freely
  available (Google Fonts, SIL OFL) — no typeface substitution was needed.
  Bundled as static `.ttf` files under `mobile/assets/fonts/` (user chose
  this over the `google_fonts` pub package specifically for zero network
  dependency at demo time). Archivo/IBM Plex Sans/Caveat ship upstream only
  as variable fonts (no pre-cut static weights in the google/fonts repo), so
  each is declared once in `pubspec.yaml` with multiple `weight:` entries
  pointing at the same file — Flutter/Skia renders the correct instance per
  declared weight. IBM Plex Mono has real static weight files upstream, used
  directly. See `.claude/rules/mobile.md` for the full token/widget map.
- `confirmed` and `verified` `StatusChip` variants intentionally share one
  color family (`AppColors.success*`) — the source design's own component
  spec sheet only shows one positive-status chip ("Potvrđeno · 14:12"), and
  never visually distinguishes "a party confirmed review" from "the hash
  check passed"; callers separate them by label/context.
- `AppButtonVariant.destructive` and all three variants' disabled states are
  not in the source design (it never shows a filled-red or a disabled
  button) — derived from the existing error-color tokens and a muted
  border/text treatment, per master_plan.md §1's instruction to derive
  missing states from existing tokens rather than invent new styling.
- Verified Phase 5's "Done when" on a real device, not just `flutter
  analyze`/`flutter test`: built and ran the app on the `Pixel_10` Android
  emulator (`flutter run -d emulator-5554`), then used `adb exec-out
  screencap` to capture the full scrolled gallery and visually compared
  every section against the source screens/spec sheet (colors, type scale,
  spacing/radii swatches, all 3 button variants × enabled/disabled, all 4
  text-field states, the circumstances grid checked/unchecked, section
  header + card, all 4 status chips, both `MonoDataRow` layouts, and the
  session progress header). `flutter run`'s CLI session detaches
  ("Lost connection to device") when driven non-interactively with no
  attached stdin — expected, and unrelated to the app itself; relaunched via
  `adb shell am start -n com.example.my_app/.MainActivity` to keep
  screenshotting without needing an attached debug session.

- `dio` (not `http`) is the one REST client used by `lib/services/api_client.dart`
  — master_plan.md §2 lists both as options and says to pick one and use it
  consistently; `dio` was chosen ahead of Phase 7/9's multipart photo/sketch/
  signature uploads (§6 screen 9 wants per-file progress, which `dio` gives
  via `onSendProgress` and `http` doesn't natively). `provider` (not
  `riverpod`) is the one state-management package, used narrowly for
  `SessionController` (see below) rather than app-wide — nothing else in
  Phase 6 needed shared state.
- `lib/services/socket_client.dart` forces `transports: ['websocket']`
  (skips the engine.io polling handshake). Tested against this backend: the
  default transport list (polling first, then upgrade) never completes its
  initial handshake at all, on either the Android emulator or a physical
  device — websocket-only connects immediately on both. Do not "fix"
  reconnect issues by removing this; that was tried and made things worse
  (see the bug below).
- Found and fixed a real bug during two-device testing: after Vozač A's
  `CreateSessionScreen` detects Vozač B joining and navigates to
  `SessionShellScreen`, the new screen's `SessionController` opened its own
  socket to the same session/party *before* the old screen's transient
  "watcher" socket (used only to detect B joining) had been torn down by
  Flutter's normal `State.dispose()` timing. The two sockets briefly
  overlapping left the new one stuck reconnecting forever (confirmed via
  Mongo: `partyA.socketId` never changed after the first join, i.e. every
  reconnect attempt was failing before completing a handshake). Fixed by
  having `_advanceToShell` in `create_session_screen.dart` explicitly cancel
  the watcher's subscriptions and call `_socket.dispose()` itself, before
  calling `Navigator.pushReplacement` — rather than waiting for
  `State.dispose()` to do it after the new screen is already mounted.
- QR payload is the raw 6-character `sessionCode` as plain text (no URI
  scheme, no JSON) — `mobile_scanner` hands back `rawValue` directly and the
  join flow already takes a plain code from manual entry, so there's one
  code path either way. The design mockup's "K7M-4RQ2" (7 chars,
  hyphenated) is decorative only; the real format is exactly 6 chars, no
  separator (`backend/src/services/session-code.service.js`). The create
  session screen displays it as two groups of 3 for readability, and the
  manual-entry field on the join screen is a single 6-char uppercase input
  (not the design's split boxes — simpler and equally usable; noted as a
  deliberate deviation, not an oversight).
- Home screen's History/Verify rows render per the design (screens 14/15
  aren't built until Phase 11) but are inert — tapping shows a snackbar
  instead of navigating anywhere. The dev-gallery route survives as a
  `kDebugMode`-gated icon button in Home's header instead of being deleted,
  per the task's "keep the file, reachable via a debug-only entry point."
- Added `android.permission.INTERNET` and `android.permission.CAMERA` (plus
  an optional `android.hardware.camera` feature) to the main
  `AndroidManifest.xml` — INTERNET is normally auto-granted in debug builds
  via the debug manifest overlay, but this app needs it in release builds
  too since the whole point is talking to the backend; CAMERA is new this
  phase for `mobile_scanner`.
- Verified Phase 6's "Done when" end-to-end, not just `flutter analyze`:
  `Pixel_10`/`Medium_Phone_1` Android emulator as Vozač A + the
  USB-connected physical phone as Vozač B, against the real
  `docker compose` backend. Confirmed via `adb exec-out screencap` on both
  devices and cross-checked the session document in `mongosh`
  (`partyA`/`partyB.socketId` and `joinedAt` both set) that each device
  shows the other as connected in the `SessionProgressHeader` after a real
  join. **API_URL values that worked:**
  - Emulator: `http://10.0.2.2:3000` (the standard Android-emulator alias
    for the host loopback).
  - USB device: `adb reverse tcp:3000 tcp:3000` once, then
    `http://localhost:3000` (or `http://127.0.0.1:3000`) — no LAN/Wi-Fi
    needed, matches the existing Phase 5 decision above.
  - Wi-Fi/LAN was not used or needed, per that same decision.
  - `flutter run`'s CLI session reliably detaches ("Lost connection to
    device") a few seconds after a non-interactive launch on both the
    emulator and the physical device — same benign behavior noted in Phase
    5, not a crash; `adb shell am start -n com.example.my_app/.MainActivity`
    reliably relaunches/refocuses the already-installed app afterward.
  - This machine's Android emulator (`Pixel_10` with default `gfxstream`
    graphics, and `Medium_Phone_1` with `-gpu swiftshader_indirect`) showed
    intermittent fully-black-screen rendering glitches during this session
    — `adb shell dumpsys window`/`pidof` confirmed the app process stayed
    alive and focused throughout, so this is an emulator/host GPU rendering
    issue, not an app crash. `adb shell input keyevent KEYCODE_WAKEUP`
    followed by a fresh `screencap` recovered it every time it happened. If
    this recurs during manual testing, it's a known quirk, not a regression
    to chase in the app code.
  - Windows Developer Mode (symlink support) is still not enabled on this
    machine, so `flutter run -d windows` fails outright — irrelevant to the
    Android testing path above, but blocks ever using a Windows desktop
    build as a stand-in party in future sessions on this machine.

- **Phase 7** — implemented against the imported design (project
  `78016f84-06e4-4866-bbc0-818cdb195c9d`) screens "1e"-"1h" (My details,
  Circumstances, Sketch, Photos); the design's 16-screen set has no mockup
  for screen 5 (Accident details) at all, so that screen's layout is
  derived from the same section/token pattern as "1e" per master_plan.md
  §1, not copied from a source screen. Initial implementation wasn't
  tested by the agent (the user ran the real two-device flow themselves
  per their own request) — that first pass surfaced several real bugs,
  fixed in a follow-up round documented below. **User-confirmed working
  end-to-end (phone + Chrome) as of this update.**
  - `SessionShellScreen` now owns the step flow for screens 5-9 as an
    `IndexedStack` (preserves each step's controllers/local state when
    navigating back and forth) rather than pushing a route per screen. A
    lightweight non-navy `_StepHeaderBar` (title + "KORAK X/8" + back
    arrow) sits below the existing `SessionProgressHeader` instead of each
    step re-showing its own navy header block like the design mockups do —
    two stacked navy bars would fight for attention, and the progress
    header already carries the party/session chrome. Step numbering treats
    session pairing as step 1/8 and Accident details as step 2/8, shifting
    the design's own "1e" (My details) from its mockup label "KORAK 2/8" to
    3/8 here — the design never numbered a separate accident-details step,
    so this app's 8-step count (pairing, accident, details, circumstances,
    sketch, photos, review, signature) is the authoritative one.
  - `party:ready`'s `stage` field (`.claude/rules/backend.md` — forwarded
    as-is, never persisted, purely for the "other driver is on step Y"
    header) is now actually used: each step screen's key (`accident`,
    `details`, `circumstances`, `sketch`, `photos`) is sent verbatim on
    entry, and both clients independently derive the display label *and*
    progress fraction from the same local `_kSteps` list — the wire payload
    stays a small opaque token, not a formatted string, so the two clients
    can't drift out of sync on wording.
  - `ReportModel.applyPatch(path, value)` (round-trips through
    `toJson`/`fromJson`, walking the dot path) is the new mechanism that
    makes `report:patched` events actually update the live report —
    `SessionController` didn't listen to `SocketClient.reportPatched` at
    all before this phase (declared, unused since Phase 6). Same approach
    as the backend's own `report.set(path, value)`, so it stays correct as
    fields are added to the schema instead of needing a hand-written setter
    per path.
  - The "don't clobber the field you're typing in" requirement is handled
    by two new widgets, `PatchTextField`/`PatchToggleRow`
    (`mobile/lib/widgets/`): each owns one dot-path, debounces outgoing
    edits ~400ms (per-field independent `Timer`), and only pulls in a
    remote value when its `FocusNode` doesn't have focus. This applies even
    to a field's *own* echoed-back patch (backend rule: every accepted
    patch broadcasts to the whole room "including the sender"), not just
    the other party's edits — otherwise a slow echo could overwrite
    keystrokes typed after the patch was sent but before it round-tripped.
    Required adding an optional external `focusNode` param to the existing
    `AppTextField` (Phase 5) so `PatchTextField` could check `hasFocus`
    itself; backward compatible, both pre-existing call sites are unaffected.
  - Witness rows (`accident.witnesses`) are patched as one whole-array
    replace (debounced, one shared `Timer` for the section) rather than
    per-field dot paths like `accident.witnesses.2.phone` — Mongoose's
    dot-path `.set()` *would* accept that and could sparse-fill the array
    with `null` entries for skipped indices, which `WitnessModel.fromJson`
    isn't prepared to survive. Whole-array replace avoids the sparse-array
    footgun entirely; witness editing isn't a high-frequency path so one
    shared debounce is fine.
  - GPS uses `geolocator` (added this phase, `mobile/pubspec.yaml`) to fill
    `accident.location.lat`/`lng` only — there's no geocoding step to turn
    coordinates into a street address (no geocoding API in the stack), so
    `accident.location.address` stays a fully manual text field regardless
    of whether GPS was used. `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`
    added to `AndroidManifest.xml`.
  - Circumstances (`models/circumstances.dart`) is a 17-item Serbian list
    matching the standard European Accident Statement's checkbox count —
    the design's own "1f" mockup only shows a handful of example labels
    plus "Prikaži još 11 okolnosti" (6 shown + 11 more = 17), so the exact
    wording is drawn from the standard statement rather than invented.
    Circumstance toggles patch immediately (no debounce) since each tap is
    already a single discrete change, unlike text typing.
  - **Sketch** (`sketch_step.dart`): the road-outline background is one
    `CustomPainter` (grid + crossing strips + dashed center lines +
    "SEVER ↑ · lat, lng") rather than nested styled boxes like the design's
    own HTML mockup, since it needs to be captured into the PNG export
    alongside the draggable items. Car/impact/marker icons are draggable
    via `onPanUpdate` and rotatable via a small corner handle whose drag
    position is converted to canvas-local coordinates through the canvas's
    own `RenderBox` (the handle sits inside the icon's `Transform.rotate`,
    so its own local `onPanUpdate` position isn't in the same frame as
    `item.position` — this bit non-obvious, worth remembering if touching
    this code). Freehand drawing was implemented too (task brief: "if not
    too complicated") — a pencil toggle switches the canvas's single
    `GestureDetector` between arranging icons and capturing strokes, since
    letting both interpret the same drag would be ambiguous. Export uses
    `RepaintBoundary.toImage`; on successful upload the resulting
    `sketch.fileId` is broadcast to the other party via `report:patch`
    (`sketch`/`sketch.*` is an explicitly allowed shared path per
    `.claude/rules/backend.md`), so sketch *is* genuinely live-synced,
    unlike photos below.
  - **Photos** (`photos_step.dart`): per the task brief, photos are
    explicitly optional — no minimum-count gate, unlike the design "1h"
    mockup's "5 OD MIN. 4 SNIMKA" framing. Caption is collected via a
    dialog *before* upload (the only point the REST endpoint accepts one —
    there's no route to edit a caption after the fact). Uploaded photos are
    **not** live-broadcast to the other party: `photos` is deliberately
    excluded from the generic `report:patch` allowlist
    (`.claude/rules/backend.md` — last-write-wins whole-array replace would
    risk silently dropping a photo the other party added moments earlier,
    since there's no merge logic). Each party sees their own uploads
    immediately via local-only state merged with the last-synced report;
    the other party picks them up on their next `session:join` resync
    (reconnect, or relaunch). A dedicated broadcast event for this is
    future work, not added here to avoid extending the socket contract
    beyond what this phase's mobile screens strictly need.
  - Added `DELETE /api/reports/:id/photos/:fileId` to
    `backend/src/routes/uploads.js` (guarded by `requireUnsealedReport`,
    reuses the existing `replaceAttachment` helper) — master_plan.md §6
    screen 9 explicitly requires "delete before lock" but no delete route
    existed anywhere in §5.2's endpoint list or Phase 4's implementation.
    This is the one backend change in an otherwise mobile-only phase, made
    because the screen's spec is literally impossible to satisfy without
    it. Covered by 3 new tests in `backend/test/uploads.test.js`; rebuilt
    and recreated the `backend` container (`docker compose build backend`
    + `up -d --no-deps backend`, same non-`--build` care as prior phases so
    the Hardhat chain/contract deployment isn't reset).
  - Fixed `mobile/test/widget_test.dart`, which had been broken since
    Phase 6: it asserted `AccidentReportApp` boots straight into
    `DevGalleryScreen` (true only in Phase 5, before Home became the real
    route and the gallery moved behind a debug icon). Also needs
    `flutter test --dart-define=API_URL=...` to pass at all — a bare
    `flutter test` leaves `Env.apiUrl` empty, so `main.dart` renders the
    "missing API_URL" screen instead of Home (docs/master_plan.md §7); this
    was true before Phase 7 too, just never previously exercised by a
    passing test. Noted in a comment at the top of the file.
  - Added `image_picker` and `geolocator` to `mobile/pubspec.yaml` (both
    already named as key packages in docs/master_plan.md §2).
  - Found and fixed a pre-existing backend test flake while validating the
    new DELETE tests: `npm test` (bare `jest`, no `maxWorkers`) runs
    `uploads.test.js` and `session-report.test.js` in separate parallel
    workers, but both reset the *same* real dockerized Mongo database in
    their own `beforeEach` (the deliberate Phase 3 choice — no
    `mongodb-memory-server`, no per-file DB namespacing). One file's
    `deleteMany`/create can race and clobber the other's fixtures
    mid-test — reproduced as an intermittent 404 on core session/report
    routes that had nothing to do with this phase's changes. Fixed by
    setting `maxWorkers: 1` in `backend/jest.config.js` so the two suites
    run serially; confirmed clean across several repeated `npm test` runs
    after the fix, where it had failed roughly half the time before.

- **Phase 7 bug-fix round** — the user's first live test (physical phone +
  emulator) surfaced four real bugs, all fixed and re-verified (phone +
  Chrome; emulator was dropped as a test target, see below). Worth reading
  before touching `session_shell_screen.dart` or any of the `steps/` screens
  again — two of these are genuine Flutter footguns, not typos, and easy to
  reintroduce by accident:
  - **`Container(color: ..., decoration: ...)` is a hard crash, not a lint
    nit.** `_StepHeaderBar` in `session_shell_screen.dart` passed both to
    the same `Container` — Flutter's `Container` asserts against this
    combination. Since that widget rebuilds on every socket event, it
    crashed on a loop the moment party B joined. Fix: fold `color` into the
    `BoxDecoration`. Grep the diff for the exact shape if this pattern shows
    up elsewhere — a scripted top-level-argument check (not a naive
    string-contains grep, which flags unrelated nested `color:`/`decoration:`
    pairs) confirmed no other instance exists as of this fix.
  - **`Row(crossAxisAlignment: CrossAxisAlignment.stretch)` inside a
    `SingleChildScrollView`'s unbounded-height `Column` is unsafe.** The
    circumstances-grid fix (pairing `CircumstanceTile`s in a `Row` so each
    row grows to fit wrapped text) used `stretch` to make both tiles in a
    row match height. Under real device font metrics (not reproduced under
    Chrome's) this left the `Row` `NEEDS-LAYOUT` with `size: MISSING`,
    which surfaced as "Cannot hit test a render box that has never been
    laid out" + repeated `mouse_tracker.dart` assertions on web (hover
    tracking kept hitting the broken node), and as widespread visual
    overlap/corruption of the whole `SessionShellScreen` on the physical
    phone (SessionProgressHeader, `_StepHeaderBar`, and the active step's
    own content all painting on top of each other, scrolling dead,
    confirmed reproducible on a clean uninstall+reinstall so it wasn't a
    stale graphics cache). Fix: `crossAxisAlignment: CrossAxisAlignment.start`
    instead — tiles in a row occasionally differ in height now, a fine
    trade for not crashing. Lesson: don't give a `Row` `stretch` cross-axis
    alignment when its height constraint can be unbounded (i.e. it's
    inside a vertically-scrolling ancestor) — `Column` `stretch` is fine
    there (its cross axis is width, which stays bounded), only `Row`
    `stretch` (cross axis = height) is the trap.
  - **`showDialog` immediately after `image_picker` returns crashes on a
    physical device.** `image_picker` hands off to a separate native
    Activity (camera/gallery); Android tears down and reattaches the
    Flutter surface when that Activity closes and the app resumes. Pushing
    a *new route* (the caption dialog) right at that moment raced with the
    reattachment and threw `'_dependents.isEmpty': is not true` from
    `Element` unmount/deactivate. A settling delay before `showDialog`
    (tried first) did **not** fix it — the trigger is the route push
    itself, not timing. Fix: `photos_step.dart`'s caption prompt is now an
    inline card built into the screen (`_CaptionPromptCard`, plain
    `setState`, no `Navigator`/`showDialog` involved) instead of a dialog.
    `_confirmDelete`'s dialog was left as-is (not implicated — it's not
    downstream of an `image_picker` Activity hand-off).
  - Backend needed `cors` (added to `backend/package.json`, `app.use(cors())`
    in `app.js`) once testing moved to `flutter run -d chrome`: Socket.IO
    already allowed any origin, but the plain Express REST routes had no
    CORS headers, so the browser silently blocked every REST call from
    the Flutter-web dev server's own localhost origin. No auth/cookies
    exist anywhere in this API, so an open origin has no real risk here.
  - Added "Popuni test podacima" (fill sample data) buttons to Accident
    details and My details (`utils/sample_data.dart`,
    `widgets/fill_sample_data_button.dart`) per user request, so testing
    doesn't require retyping the same fields every run. Party A's driver is
    always **Dejan Mihajlović**, party B's always **Mihajlo Dejanović**
    (fixed user requirement), each with a distinct plausible
    vehicle/insurer/policyholder so the two sides look genuinely different
    in the review/PDF later. Button intentionally has no icon (had one
    initially — `Icons.auto_fix_high` — removed per user feedback).
  - Fixed a latent race while adding the fill buttons: `_syncWitnessesFromRemote`
    in `accident_details_step.dart` would resync from the server's
    *pre-mutation* value on the very next build after any local witness
    add/remove/fill, because that build runs before the patch has
    round-tripped and no witness field is focused to suppress it (the
    existing focus-guard only protects active typing). Fixed with a
    `_witnessesLocalEditAt` timestamp — suppresses remote resync for 1s
    after any local witness mutation, not just while a field has focus.
  - **Operational notes for future sessions on this machine:**
    - Never run two `flutter run` invocations concurrently against this
      project — they share `mobile/build/` and Gradle-corrupting one
      mid-build (a `NoSuchFileException` on an intermediates directory)
      cost real time to diagnose. Build one device fully (or at least past
      the Gradle step) before starting the next. If it happens anyway:
      `flutter clean`, `flutter pub get`, rebuild serially.
    - `adb reverse tcp:3000 tcp:3000` does not survive the USB device
      disconnecting/reconnecting (its `transport_id` changes) — re-run it
      whenever a previously-working physical-device build suddenly shows
      "Connection refused" creating a session.
    - This machine's emulators (`Pixel_10`, `Medium_Phone_1`) can get into
      a state well beyond the "black screen" quirk already noted in Phase
      6 — a severe in-app render error (the `Row`/`stretch` bug above) left
      one emulator throwing repeated `system_server` ANR dialogs even after
      reinstalling the fixed app, and `adb emu kill` failed to actually
      terminate the wedged `qemu-system-x86_64` process (needed a direct
      `Stop-Process`). Recovery was a cold boot
      (`emulator -avd <name> -no-snapshot-load -no-snapshot-save`), not a
      normal relaunch. Given this, mid-session testing moved from the
      emulator to `flutter run -d chrome` for the "party A" role instead
      (see the CORS fix above) — Chrome is far more reliable to drive
      programmatically on this machine and reproduces the same Dart-level
      bugs. The emulator remains an option for the user's own testing but
      is no longer assumed reliable enough for the agent to drive.

- **Phase 8** — review, signing, and locking (docs/master_plan.md §5.1/§5.3,
  §6 screens 10–11).
  - **Review confirmation reuses the existing generic patch mechanism** —
    `ReviewStep`'s "Potvrđujem da su podaci tačni" button sends
    `report:patch` with path `partyX.confirmedReview`/`value: true`, no new
    endpoint or event needed since `confirmedReview` already lives under
    the caller's own `partyA`/`partyB` subtree (`.claude/rules/backend.md`'s
    existing own-subtree rule). The same broadcast that persists it also
    gives the other party's confirmation state live — that requirement
    fell out of the existing contract for free.
  - **Locking is a new `report-lock.service.js`** (`maybeLockReport(report,
    session, io)`): once both parties have `confirmedReview` **and** a
    stored `signature.fileId`, it sets **both** `Report.status` and
    `Session.status` to `"signing"` together and emits `report:locked` —
    resolving the "Session.status and Report.status aren't kept in sync"
    gap noted in `.claude/rules/backend.md`, at least for this one
    transition (the rest of the status lifecycle is still Phase
    9/10/11 work). Idempotent (a no-op once already at or past `"signing"`),
    so it's called after *every* accepted `report:patch` in
    `session.socket.js` (cheap; simpler than filtering to just
    `confirmedReview` paths) and again after a signature REST upload in
    `uploads.js` (the one write path the socket handler never sees).
  - **The sealed-report guard now covers the whole locked range, not just
    `"sealed"`.** `report-guard.service.js`'s `assertReportNotSealed`/
    `requireUnsealedReport` used to only check `status === "sealed"` (true
    of every write route before this phase, since nothing ever set any
    other locked status). It now also rejects `"signing"`/`"finalizing"`/
    `"abandoned"` via a new `ReportLockedError` (code `REPORT_LOCKED`),
    kept distinct from the existing `SealedReportError`/`REPORT_SEALED` so
    a caller/test can still tell "permanently sealed" apart from
    "temporarily locked, signing/finalizing in flight." This is what makes
    "every patch and every upload" actually true from the moment of
    locking — the socket path was already covered by the session-level
    `LOCKED_STATUSES` check, but the REST upload routes (photos/sketch/
    signature) had no equivalent until now.
  - **Signature upload broadcasts itself instead of the client re-patching
    it.** `POST /api/reports/:id/signature` now emits a server-originated
    `report:patched` (`{path: "partyX.signature", value: {fileId,
    signedAt}, by: party}`) right after persisting — reusing the exact
    `{path, value, by}` contract clients already handle for
    socket-originated patches, rather than inventing a new event type or
    having the mobile client fire a redundant `report:patch` after its own
    REST upload (which would have double-written the same value). Both the
    uploader's own screen and the other party's get the update live, the
    same way `sketch.fileId` already worked in Phase 7 — except here the
    server is the one broadcasting, since the REST route (not a client
    patch) is the actual write.
  - **This closed the "photos aren't live-synced" known issue below, as a
    side effect of the same mechanism.** `classifyPatchPath` in
    `session.socket.js` still rejects a *client*-initiated `report:patch`
    to `photos` (that restriction is about validating untrusted client
    input against last-write-wins array replace being unsafe for an
    additive list — still true). But nothing stops the *server* from
    broadcasting `report:patched` with path `"photos"` after its own
    atomic, already-persisted array push/filter — so `POST
    /api/reports/:id/photos` and `DELETE
    /api/reports/:id/photos/:fileId` now do exactly that
    (`broadcastPatch` helper in `uploads.js`). Needed for Review's "full
    assembled report from both sides" to actually be both sides without
    requiring a reconnect first, exactly the gap the note below used to
    describe. `photos_step.dart`'s own local-optimistic-list/dedupe-by-
    fileId logic (Phase 7) needed no changes — it already treats "the
    fileId is in the remote list" as the signal to drop its own optimistic
    entry, which now just happens sooner (on broadcast) instead of only on
    reconnect.
  - **`app.set("io", io)`** in `app.js` so REST routes can reach the same
    Socket.IO server the socket handlers use, without each route module
    importing/constructing its own — needed for `uploads.js`'s new
    broadcasts and lock check.
  - **Client-side locking is one flag, one overlay, not per-field
    plumbing.** `SessionController.isLocked` is derived two ways: from a
    `session:state`/reconnect snapshot whose `status` is already in a new
    `kLockedSessionStatuses` set (mirrors backend `LOCKED_STATUSES`), or
    set immediately by a live `report:locked` event (no payload).
    `SessionShellScreen` wraps its entire step `IndexedStack` (all 7 steps,
    not just Review/Signature) in one `IgnorePointer(ignoring: isLocked)` +
    dimmed `Opacity`, plus a `_LockedBanner` — rather than threading an
    `enabled`/`isLocked` prop through every `PatchTextField`/
    `PatchToggleRow`/button on every step screen. Verified this actually
    covers the earlier screens too (accident details, my details,
    circumstances, sketch, photos), not just Review/Signature, since the
    gate lives above all of them in the widget tree. One rough edge this
    surfaces: a step's own "next" button lives inside the same ignored
    region, so a party sitting on an earlier step when the report locks
    (e.g. they went back to double-check something while the other side
    finished signing) would otherwise have no way forward — handled with a
    one-time `_maybeJumpToReviewOnLock` that jumps to the Review step the
    first time `isLocked` flips true while `_stepIndex` is behind it, so
    the locked state is always visible at that same well-known screen for
    both parties, but doesn't fight a deliberate back-navigation
    afterward.
  - **Signature screen uses the `signature` pub package (v6.4.0)** rather
    than a hand-rolled `CustomPainter` like the sketch step — its own
    canvas already ships `clear()`/`undo()`/`redo()`/`canUndo`/`canRedo`,
    which is exactly "clear/redo" from §6 screen 11. Export
    (`toPngBytes(width:, height:)`) is pinned to a fixed 600×300 canvas
    regardless of how much of the pad was actually inked, rather than the
    package's default tightly-cropped-to-strokes size — every signature
    PNG ends up the same shape, simpler for the eventual PDF layout (§5.6)
    than a variably-sized image. `AppFontFamily.signature`/
    `AppTypography.signatureLarge` (Caveat) were already reserved back in
    Phase 5 for a decorative preview only, never the real capture — no
    change needed there.
  - Own signature state (`selfSigned`) and the bottom-bar submit button
    read straight off `SessionController.report`, which updates itself via
    the broadcast above — no manual local-state patch needed after a
    successful upload, unlike the sketch step's explicit
    `sendPatch('sketch.fileId', ...)` (Phase 7 pattern, kept as-is there
    since that upload genuinely is client-initiated all the way through).
  - Added integration test coverage in `backend/test/session-report.test.js`
    (confirmedReview-driven lock via sockets, `SESSION_LOCKED` on a patch
    attempted after) and `backend/test/uploads.test.js` (signature-driven
    lock via REST, `REPORT_LOCKED` on an upload attempted after, and both
    new `report:patched` broadcasts — signature and photos). Rebuilt and
    recreated the `backend` container (`docker compose build backend` +
    `up -d --no-deps backend`, same non-`--build` care as prior phases) so
    the running stack matches this code; did not drive the mobile UI
    end-to-end (the user is testing that themselves this round, per their
    own request).

- **Phase 9** — `services/pdf.service.js`, §5.6 layout. Generation only —
  this phase never calls the chain (no `chain.service.js`/`ethers` import).
  - **Chose `pdfkit` over `pdf-lib`** (§2 lists both, pick-one-and-use-it-
    consistently like `dio`/`provider` before it). `pdfkit`'s `.text()`
    does automatic word-wrap *and* automatic page-break-on-overflow in
    flowing mode, which is most of what §9.4's "very long remarks" and
    "photo appendix spanning multiple pages" cases need for free;
    `pdf-lib` would have meant hand-rolling both. Trade-off taken
    knowingly: `pdfkit`'s auto-pagination only applies to flowing text, not
    to absolutely-positioned draws (the two-column grids, the circumstance
    checkboxes, images) — those are paginated by hand (see below), which
    `pdf-lib` would have needed everywhere anyway.
  - **Layout mixes two drawing strategies deliberately.** Fixed-shape data
    (driver/vehicle/insurer/policyholder fields, the circumstances grid) is
    drawn at explicit `x`/`y` in two hand-synced columns with a page-break
    check (`ensureSpace`) *before* the block starts, so a row is never
    split mid-draw — safe because these fields have a small, bounded row
    count. Free-typed content (`visibleDamage`/`remarks`) instead uses
    `pdfkit`'s plain flowing `.text()` with no explicit position, so
    arbitrarily long text wraps and paginates on its own. The photo
    appendix hand-checks available space per *row* (2 photos/row) before
    drawing it, calling `doc.addPage()` itself when a row won't fit — this
    is the "spans multiple pages" case, verified in
    `backend/test/pdf.test.js` by asserting page count > 1 for a
    14-photo report.
  - **Footer trimmed twice, on request, down to just a page number.**
    Originally carried report ID, PDF SHA-256, contract address, and
    network; first pass dropped the first three (already shown in the
    app's own report history/detail views — pure duplication here), which
    also retired the one piece of real complexity the footer had caused:
    the SHA-256 line needed a two-pass build (render once to hash the
    result, then re-render with that hash filled in — a document can't
    literally contain the hash of its own final bytes). Second pass
    dropped the contract address too, once it became clear a lone address
    with no report ID/network/tx-hash context around it doesn't actually
    mean anything — it's not proof this document was anchored to that
    contract (nothing is, until Phase 10 actually anchors it). No chain
    data of any kind appears in the PDF now. `generateReportPdf` is
    single-pass — nothing left in the document depends on the document's
    own output, so there was never a real ordering problem here, only the
    self-referential-hash one the first trim already removed.
  - **Found and fixed a real bug while regenerating a preview after the
    first trim: every page was gaining 1-2 blank trailing pages.**
    `stampFooterOnAllPages` drew its text at `y = page.height -
    margins.bottom + 18` — deliberately *inside* the reserved bottom-margin
    strip, since that's where a footer belongs. But pdfkit's own text
    engine doesn't know that positioning is deliberate: its overflow check
    (would this line's bottom edge land past `page.height -
    margins.bottom`) fires regardless of whether the position was reached
    by flowing or by an explicit `x`/`y` argument, and silently calls
    `doc.addPage()` first when it does — confirmed by a standalone pdfkit
    repro script (3 real content pages → 9 after footer-stamping with two
    `.text()` calls per page at that position). Fixed by temporarily
    zeroing `doc.page.margins.bottom` around each page's footer draw (a
    known pdfkit footer-stamping pattern) so the check's own boundary
    moves down along with where we're actually drawing; restored
    immediately after. Re-verified with the same repro script (3 pages in,
    3 pages out) and added a regression test in `pdf.test.js` asserting an
    exact page count (not just "> 1") for the fully-filled fixture, plus
    tightened the long-remarks and 14-photo tests' `> 1` assertions with
    upper bounds too — none of the three would have caught this
    regression with only a lower-bound check, since a doubled page count
    still satisfies "> 1".
  - **Circumstance labels ported to a new `backend/src/constants/
    circumstances.js`**, verbatim from `mobile/lib/models/circumstances.dart`
    `kCircumstances` (same order, same Serbian wording) — so the PDF's grid
    reads identically to what the driver actually saw and checked on the
    Circumstances screen, rather than inventing separate label text
    server-side.
  - **`storage.service.js` gained `getFileBuffer(fileId)`** (drains
    `openDownloadStream` into one `Buffer`) — every existing caller
    (`files.js`) streams to an HTTP response and never needed the whole
    file in memory at once; `pdf.service.js` does, to hand raw bytes to
    `pdfkit`'s `doc.image()`. All three image types (sketch, photos, both
    signatures) are pre-fetched together via `Promise.all` before either
    pdfkit pass starts, so the actual page-drawing code stays fully
    synchronous — missing/failed fetches resolve to `null` and render as
    an explicit "not available" placeholder rather than aborting the PDF
    (§9.4 "missing optional fields", extended to attachments too — a
    report can legitimately be previewed via the Phase 9 dev route before
    every attachment exists).
  - **Temporary dev-only preview route**, `backend/src/routes/dev-pdf.js`,
    mounted at `/api/dev` — `GET /api/dev/reports` (id/status/plates for
    the newest 50 reports, so a report id can be found without opening
    `mongosh`) and `GET /api/dev/reports/:id/pdf` (regenerates on demand,
    no `requireUnsealedReport` guard — a read-only preview has no reason to
    reject a sealed report, and most reports being iterated against during
    this phase aren't sealed yet anyway). Explicitly marked temporary in
    both files' own comments, to be deleted once Phase 10's real
    `GET /api/reports/:id/pdf` (streams the *stored* PDF from GridFS after
    finalize) makes it redundant.
  - Added `backend/test/pdf.test.js`: a bare-minimum report (every optional
    field/attachment missing), zero photos, a very-long-remarks report
    (page count bounded both above and below — see the blank-page bug
    above for why an upper bound matters), a 14-photo report (same), a
    fully-filled report with real sketch/photo/signature attachments
    (asserts an exact page count), and the two dev-route endpoints via
    supertest. Also generated a real PDF from the report the user had just
    carried through signing during Phase 8's own testing (via the new dev
    route against the live Docker backend) and sent it to them directly at
    each iteration of this phase, as a concrete example on real data
    rather than only synthetic test fixtures. Rebuilt and recreated the
    `backend` container the same way as prior phases, each time.
  - **Found and fixed a second real bug, on request: Serbian Latin
    diacritics (č, ć, š, đ, ž) rendered wrong or vanished entirely.**
    pdfkit's standard 14 fonts (`Helvetica`, `Courier`, ...) only support
    WinAnsiEncoding (Windows-1252) — which happens to have Š/š and Ž/ž, but
    has no code points for Č/č, Ć/ć, or Đ/đ at all, so any word using them
    (extremely common in Serbian — confirmed by inspecting the earlier
    PDFs' decompressed content streams, e.g. "Napuštao" → "Naputao",
    "SAOBRAĆAJNOJ" → garbage bytes) silently dropped the character or
    rendered the wrong glyph. Fixed by embedding real fonts instead of
    relying on the standard 14 — specifically the *same* IBM Plex Sans/
    Mono `.ttf` files already bundled for the Flutter app
    (`mobile/assets/fonts/`, chosen there for the same Serbian-coverage
    reason — see `.claude/rules/mobile.md`), copied into a new
    `backend/src/assets/fonts/` (plus their OFL license files) rather than
    sourcing a new font. Verified full glyph coverage for all five
    diacritics (both cases) against the actual files with `fontkit` (the
    same library pdfkit uses internally for font embedding) before wiring
    anything up, and again as a permanent regression test.
    `pdf.service.js`'s `registerFonts` registers three: `Sans` (body/value
    text — IBM Plex Sans's variable-font file, rendered at its default
    instance since pdfkit/fontkit can't select a named weight from a
    variable font), `Mono` (footer), and `Mono-SemiBold` (section
    headings/labels/party-column headers) — the latter two are real static
    weight files, unlike Sans, so they're used everywhere the old code
    used `Helvetica-Bold` for actual bold emphasis; there is no embedded
    Sans-Bold, so that distinction is gone (acceptable per the "don't
    stress over the design" guidance — Mono-SemiBold already carries the
    emphasis role in the app's own type scale, `AppTypography.monoLabel`).
    Switching fonts changed text metrics enough that the fully-filled test
    fixture now legitimately needs 3 pages instead of 2 — traced both new
    `addPage()` calls to their call sites (`drawFreeText`'s own overflow,
    then `ensureSpace` inside `drawSignatures`) with an instrumented
    one-off script to confirm this was normal reflow, not a return of the
    blank-page bug, before updating that test's expected count.
    Also discovered while investigating: text drawn with a real embedded
    font is encoded as CID/glyph-index hex strings in the content stream,
    not simple ASCII-as-hex like the standard 14 fonts use — confirmed by
    running the same decompress-and-hex-decode trick `pdf.test.js` used
    for the (now-removed) footer-text assertions and getting back
    unreadable glyph-index bytes instead of readable text. That technique
    only ever worked because the document used standard fonts; it can't
    recover rendered text from this document anymore, so those two
    assertions and the decompression helper were removed as no longer
    meaningful, in favor of the font-file glyph-coverage test described
    above (which doesn't depend on how pdfkit happens to encode the
    content stream). Rebuilt and recreated the `backend` container again;
    sent the user a freshly regenerated preview.

- **Phase 10** — `services/finalize.service.js`, `services/chain.service.js`,
  `POST /api/reports/:id/finalize`, `GET /api/reports/:id/pdf`, and mobile
  screens 12–13 (docs/master_plan.md §5.4/§6).
  - **`reportId32` derivation**: `chain.service.js`'s `deriveReportId32(reportId)`
    is `ethers.id(String(reportId))` — i.e. `keccak256(utf8Bytes(<24-char hex
    Mongo ObjectId string>))`. Considered the alternative of left-padding the
    raw 12 ObjectId bytes out to 32 (`ethers.zeroPadValue`) but rejected it:
    that needs both sides of a later verify call (Phase 11) to agree on byte
    order/padding side with no on-chain-specific knowledge to check it
    against, whereas hashing the id's own string form is exactly what
    `String(reportId)` already produces everywhere else in this codebase
    (`console.log`, JSON responses, the mobile `ReportModel.id`), so verify
    only ever needs "the report's id as a string" to reproduce the same
    bytes32, nothing chain-specific. Documented again in
    `.claude/rules/backend.md`.
  - **Finalize pipeline is one function, `runFinalize(reportId, io)`**, not
    split per §5.4 step — steps share too much local state (the report
    document, the session, the derived hashes) to usefully separate, and the
    ordering/rollback behavior (stop and persist an error on step 9 failure,
    skip 3-7 on a retry) only makes sense read as one sequence. Each step
    still gets its own `console.log("[finalize:<step>] <status>")` line and
    `report:progress` broadcast, per the task's "log each step distinctly."
  - **Retry re-uses the same `POST /finalize` endpoint** rather than a
    separate route — docs/master_plan.md §5.2 only lists the one endpoint,
    and the pipeline already has to inspect `report.status` to decide
    fresh-vs-resume regardless, so a second endpoint would just be another
    caller of the same status-branching logic. `runFinalize` distinguishes:
    `"sealed"` → no-op success; `"signing"` → full pipeline; `"finalizing"`
    with `pdf.fileId`+`bundleHash` already stored → anchor-only retry (steps
    8-10); `"finalizing"` without a stored PDF (a process died before
    anything durable saved) → full pipeline again; anything else → `409`.
  - **Concurrency**: a per-report in-memory `Set` in `finalize.service.js`
    serializes `runFinalize` calls for the same report within this one Node
    process (no clustering per docker-compose §7) — both parties' clients
    auto-trigger finalize on reaching screen 12, so this is expected to
    happen almost every time, not an edge case. The loser gets a `202
    {status: "finalizing"}` instead of running a second concurrent pipeline
    (which would double-generate the PDF, or send two `anchor()` transactions
    racing for the same nonce). Not a durable/distributed lock — acceptable
    for a single-backend-instance bachelor-thesis deployment, called out
    explicitly in `.claude/rules/backend.md` so it isn't mistaken for one if
    this ever gets containerized to multiple replicas.
  - **`chain.service.js`'s write-capable contract is built lazily**
    (`getSignerContract()`, memoized on first call), not at module load like
    the existing read-only `provider`/`contract` were. `config.PRIVATE_KEY`
    is a syntactically-present-but-cryptographically-invalid all-zeros
    placeholder in both `.env.example` and `test/setupEnv.js`, and
    `ethers.Wallet` throws immediately for that value — every route
    (health/sessions/reports/uploads/sockets) requires `chain.service.js`
    transitively through `app.js`, so eager construction would have crashed
    the entire test suite the moment this phase's code was required, not
    just an actual finalize call. Verified this explicitly: `node -e
    "require('./src/app')"` with the placeholder key still loads cleanly.
  - **`backend/.env`'s `PRIVATE_KEY` updated from the all-zero placeholder to
    Hardhat's well-known default account #0 key**
    (`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`,
    address `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`) — this is the same
    publicly-documented throwaway key every `npx hardhat node` prints, not a
    real secret, and it's also the deployer whose deterministic first
    contract deployment already matches the `CONTRACT_ADDRESS` that was
    already sitting in `.env`. `.env.example` is untouched (stays the
    placeholder, per its own "for local Hardhat dev, use one of the funded
    test account keys" comment — the user copies/fills it in themselves).
  - **`report:sealed`'s payload is extended** beyond §5.3's minimal
    `{pdfFileId, txHash, blockNumber}` to also carry `contractAddress`,
    `network`, and `anchoredAt` — so *every* connected client (not just
    whichever one's own `POST /finalize` happened to complete the pipeline)
    can render the full sealed state on screen 13 without a follow-up REST
    call. A new `report:progress` event (`{step, status, error?, txHash?,
    skipped?}`) was also added, not in the original §5.3 table at all, since
    "step-by-step progress driven by real server events" has no other
    mechanism to ride on. Both documented in `.claude/rules/backend.md`.
  - **`GET /api/reports/:id/pdf` replaces the temporary Phase 9 dev route**
    (`routes/dev-pdf.js`, deleted along with its `app.js` mount) exactly as
    that file's own comment said it should once Phase 10 landed — it streams
    the *stored* PDF from GridFS (404 if `pdf.fileId` isn't set yet) rather
    than regenerating on every request. `pdf.test.js`'s dev-route describe
    block was rewritten against this real route instead of deleted outright,
    keeping equivalent coverage (stream succeeds once stored, 404 with no
    stored PDF, 404 for an unknown id).
  - **Mobile: Finalizing/Report-complete are a conditional swap inside
    `SessionShellScreen`'s existing body, not new pushed routes or new
    `IndexedStack` steps.** The source design (screens "1k"/"1l") renders
    both full-bleed with their own header treatment, not nested under the
    shell's `SessionProgressHeader`/`_StepHeaderBar` chrome — but routing
    away with `Navigator.push` would tear down the `ChangeNotifierProvider`
    that owns the live `SessionController`/socket, and recreating a second
    `SessionController` for the same session was exactly the
    two-overlapping-sockets bug from Phase 6 (see that phase's note above).
    Instead `_SessionShellBodyState.build()` just returns a different widget
    tree once `isLocked`/`status == "sealed"`, keeping the same controller
    instance alive across the transition for free. This also let the old
    Phase 8 "jump to Review once locked, so there's a well-known place to
    land" hack (`_maybeJumpToReviewOnLock`/`_kReviewStepIndex`) be deleted
    outright — the real destination (Finalizing) now exists, so there's
    nothing left to work around, and the old `_LockedBanner` + dimmed
    `IgnorePointer`-wrapped `IndexedStack` (Phase 8) is dead code once
    "locked" always means "showing a completely different screen" rather
    than "showing the same form, disabled."
  - **FinalizingScreen derives each step row's done/active/error state
    primarily from the report's own persisted fields** (`pdfFileId`,
    `chain.txHash`, `chain.lastError`), using the live `report:progress`
    event map (`SessionController.finalizeStepStatus`) only for in-flight
    flavor (spinner vs. static icon, the short-SHA hint text, the progress
    bar fraction) — not as the sole source of truth. A client that reaches
    this screen via a reconnect (having missed every earlier event) still
    renders correctly instead of showing every row stuck on "pending."
    Symmetrically, the backend replays the skipped steps (`lock` through
    `bundle`) as instantly-`"done"` `skipped: true` events on an anchor-only
    retry, so a client that *is* listening live doesn't see them go
    silent either.
  - **Auto-start, not a manual "Finalize" button**: `FinalizingScreen` POSTs
    `/finalize` once on mount whenever `report.status == "signing"`, or
    `"finalizing"` with no recorded error yet (covers a client reconnecting
    mid-pipeline before any failure happened — safe, the backend's in-flight
    lock just no-ops it if another request already owns the run). A
    `"finalizing"` report that *does* have `chain.lastError` set is
    deliberately **not** auto-retried — that needs an explicit "Pokušaj
    ponovo" tap, so a persistently-failing chain (e.g. RPC down) doesn't spin
    silently forever in the background.
  - **Screen 13's "Preuzmi"/"Otvori PDF"/"Podeli" collapsed to two actions**
    ("Otvori PDF" and "Podeli," matching the task's "preview/open/share"),
    not the design mockup's three ("Preuzmi", "Otvori PDF ›" link, "Podeli").
    The stack has no save-to-Downloads package (master_plan.md §2 names only
    `open_filex`, not a storage/save library), and "Preuzmi" downloading to
    the same app-temp file `open_filex` then opens wouldn't be a
    meaningfully different action from "Otvori PDF" — both download once
    (`ApiClient.downloadFile` against the existing `GET /api/files/:fileId`,
    cached in `_localPdfPath` so a second tap doesn't re-download) and hand
    the same local file to either `OpenFilex.open` or `share_plus`'s
    `SharePlus.instance.share`. Added `share_plus` (^13.3.0 — `^11.1.0` was
    tried first per the task's package list, but its `share_plus_platform_interface`
    pins `win32 ^5.5.3`, which conflicts with `geolocator`'s existing
    `package_info_plus`/`win32 ^6.0.1` chain; 13.3.0 was the version `flutter
    pub get`'s own resolver suggested and still has the `SharePlus.instance.share(ShareParams(...))`
    API, confirmed introduced in 11.0.0) and `path_provider`/`open_filex`/
    `url_launcher` (all three already named in master_plan.md §2's key
    package list) to `mobile/pubspec.yaml`.
  - **Block-explorer link** only renders when `report.chain.network` (set
    from the backend's `CHAIN_NETWORK` at anchor time) matches a small known
    map of public testnets (`sepolia`, `amoy`/`polygon-amoy`) — anything else
    (`localhost`/`hardhat`, the only network actually configured for local
    dev right now) shows no link, satisfying "when CHAIN_NETWORK is a public
    testnet" without needing a hardcoded assumption about which testnet this
    demo ends up using (hardhat.config.js currently only has a `sepolia`
    network entry, but master_plan.md §2 allows either).
  - **Report id display deviates from the mockup's decorative "EI-2026-08-4471"
    numbering** — no such formatted-id scheme exists anywhere in the backend
    (§5.1's `Report._id` is a plain Mongo ObjectId), so inventing one just
    for this screen would be presentation-only fiction. Shows `#<last 6 hex
    chars of the ObjectId, uppercased>` instead — short, stable, and doesn't
    imply a numbering scheme the backend doesn't actually have.
  - Verified with automated tests only this round, not a live two-device
    run — the user is doing that themselves per their own request (see
    "Current phase" above). `backend/test/finalize.test.js` mocks
    `chain.service`'s `anchorReport`/`deriveReportId32` (`jest.mock`) so the
    pipeline's own state machine — gating, step ordering, the anchor-only
    retry not regenerating the PDF, idempotency once sealed — is covered
    without needing a live Hardhat node in CI; the real end-to-end anchor
    (contract layer itself already covered by `blockchain/test/registry.test.js`)
    is exactly what the live run verifies. `npm test` (53 tests, 4 suites),
    `flutter analyze` (no issues), `flutter test`, and `flutter build apk
    --debug` all green as of this update.
  - **Live two-device run surfaced a real bug: `FinalizingScreen` never
    actually called `POST /finalize`.** The user reported the Finalizing
    screen stuck on "PDF generisan"; the backend's finalize logs showed
    nothing since the container started except an earlier synthetic smoke
    test, and the actual live report was confirmed sitting at
    `status: "signing"` with `pdf.fileId: null` in Mongo — i.e. the request
    genuinely never left the client, not a slow/failed request. Root cause:
    `_maybeAutoStart` gated on `controller.report?.status == 'signing'`, but
    `report.status` is **not** kept live-synced on the client — the
    `report:locked` event that gets this screen on-screen at all carries no
    payload (`.claude/rules/backend.md`) and only flips the separate
    `SessionController.isLocked` boolean; `status` itself is server-
    controlled and never goes through `report:patched`
    (`classifyPatchPath` rejects it), so it only ever updates from a full
    `session:state` resync (join/reconnect) or the `report:sealed` handler.
    In a live (non-reconnect) session it just sits stale at whatever it was
    *before* locking, so the `== 'signing'` check never matched and
    `_start()` was silently never called — which also explains the exact
    visible symptom: row 2 ("PDF generisan") has no real pending state
    (only done/active), so with `pdfFileId` never set it just spun forever,
    looking exactly like a hung PDF generation step rather than a request
    that was never sent. Fixed by gating on `isLocked` (the one flag that
    *is* reliably live-synced via its own dedicated event) plus "no known
    error yet" instead of the specific status string — this screen only
    ever renders once `isLocked` is already true (`SessionShellScreen`), so
    there's no need to distinguish "signing" from "finalizing" here at all.
    Verified the fix by rebuilding and reinstalling on the physical phone
    (`flutter run -d <device>`) against the *same* already-locked, already-
    signed report from the stuck attempt — it picked up immediately on
    relaunch and sealed for real: report `6a8c4120...c7cdd` (`#3C7CDD`),
    tx `0xa4ef61cb...773f3eb7`, block 3, 4 attachments hashed (sketch +
    1 photo + both signatures), confirmed independently against both the
    backend's `[finalize:*]` logs and the sealed Mongo document.

- **Phase 11** — `GET /api/reports/:id/verify` (§5.5, the thesis
  centerpiece), deviceId-scoped history, screens 14–15, `scripts/tamper.js`.
  - **`verify.service.js`'s match logic is recomputed-vs-on-chain, never
    recomputed-vs-stored.** Every hash is recomputed fresh from GridFS
    bytes / the on-chain record at request time; Mongo's own
    `pdf.sha256`/`attachmentHashes[].sha256` fields are surfaced in the
    response purely as `storedHash`, a third display value, never an input
    to `match`. This is deliberate, not incidental: the whole point of
    anchoring on-chain instead of just trusting the database is that even
    an attacker who edits both a file's bytes *and* its stored hash field
    in Mongo still can't fool verify, since the on-chain record is outside
    their reach. A recomputed-vs-stored check alone would have missed
    exactly that case.
  - **Per-attachment `match` is recomputed-current-bytes vs.
    `attachmentHashes[].sha256`** (the value recorded at finalize time,
    itself one of the inputs hashed into `bundleHash`) — there's no
    per-file hash on-chain, only the aggregate `bundleHash`, so this is the
    only available per-file ground truth. A single swapped attachment
    therefore shows up two ways in the response: that one entry in
    `attachments` with `match: false`, and `bundle.match: false` (since
    `bundleHash` is recomputed from *current* attachment bytes the same
    deterministic way `hash.service.computeBundleHash` does at finalize
    time — sorted hex strings, re-hashed). `pdf.match` is unaffected by an
    attachment swap; the two are checked and reported independently, which
    is what lets the UI say *which* thing is wrong.
  - **Verdict logic**: `NOT_ANCHORED` if `report.chain.txHash` isn't set,
    or if it is but `chain.service.getOnChainRecord` still can't find a
    record (RPC down, or the contract's own "not found" revert — both
    collapsed to the same outcome rather than a hard 500, since neither
    means anything different to a user checking a report's status).
    Otherwise `VERIFIED` if both `pdf.match` and `bundle.match` are true,
    else `TAMPERED`. A missing/deleted attachment file recomputes to a
    hash of `null`, folded into the bundle input as `""` — guaranteed to
    mismatch, which is the correct outcome for a vanished file.
  - **`chain.service.getOnChainRecord`** wraps the existing read-only
    `contract` (no signer needed, same instance `checkChain` already uses)
    and catches *any* read failure — including the contract's own "not
    found" revert for an id that was never anchored — returning `null`
    rather than throwing, so `verify.service.js` doesn't need its own
    try/catch around the chain read.
  - **`deviceId` schema decision** (the gap `GET /api/reports?deviceId=`
    was left with since Phase 3): `Report.deviceIds: [String]`, not a field
    on `Session`. History (§6 screen 15) scopes *reports*, and a report
    should stay visible in history long after its session's 24h TTL reaps
    the `Session` document — putting it on `Session` would have made
    history silently go blank a day after every report. Both parties'
    deviceIds land in the same flat array (pushed once each, at session
    create/join in `routes/sessions.js`, via `$addToSet` on join so a
    same-device rejoin doesn't duplicate) — a report shows up in either
    party's history, there's no tracked "which slot" a device occupied.
    `POST /api/sessions` and `POST /api/sessions/:code/join` both now
    accept an optional `{deviceId}` body field; the mobile client always
    sends its `DeviceIdService.getOrCreate()` value.
  - **`scripts/tamper.js`** is a standalone CLI (`npm run tamper -- <id>
    [--photo]`), not a test helper — it's the literal §9 demo step run
    against the real live stack, not jest. It flips one byte of the stored
    PDF by default, or (`--photo`) overwrites the report's first photo with
    a different image, via a new `storage.service.overwriteFile(fileId,
    buffer)` (delete + re-upload under the same GridFS `_id`, using the
    driver's `openUploadStreamWithId`) — deliberately leaves the `Report`
    document itself completely untouched (`pdf.sha256`/`attachmentHashes`
    keep their original, honest values), since that's the entire premise of
    the demo: only what's sitting in GridFS changes, and verify still
    catches it because it never trusted those stored fields as its source
    of truth in the first place.
  - **Verified against the real live stack, not just jest**: seeded a
    throwaway signed-off report directly in Mongo (same shortcut
    `backend/test/verify.test.js` uses), ran it through the real
    `POST /finalize` against the docker-compose `hardhat` node (a genuine
    anchor tx, confirmed on-chain), called the real `GET /verify` →
    `VERIFIED` with `pdf.recomputedHash === pdf.onChainHash`, then ran the
    real `node scripts/tamper.js <id>` CLI (not just the underlying
    function — this exercises the script's own env/argv/exit-code wiring
    too) and called `GET /verify` again → `TAMPERED`, `pdf.match: false`,
    `pdf.storedHash === pdf.onChainHash` (proving the mismatch is caught by
    the recomputed-vs-chain check, not a stale stored field). Also smoke-
    tested `?deviceId=` filtering directly against the live stack: a
    session created with a `deviceId` shows up under that id and not under
    an unrelated one. Rebuilt and recreated the `backend` container
    (`docker compose build backend` + `up -d --no-deps backend`, same
    non-`--build` care as every prior phase) before this pass, then cleaned
    up all throwaway Mongo/GridFS data created for it afterward — nothing
    from this verification run persists in the shared dev database.
  - **Mobile**: `VerifyScreen` (14) has two entry paths — given a
    `reportId` directly (from `ReportCompleteScreen`'s new "Proveri
    integritet" action, or a sealed `HistoryScreen` row) it verifies
    immediately; given none (Home's "Provera izveštaja" row) it first shows
    a picker of this device's own sealed reports (`ApiClient.getReports`
    filtered client-side to `status == 'sealed'`, since only a sealed
    report has anything on-chain to check). `HistoryScreen` (15) lists
    every report `GET /api/reports?deviceId=` returns, reusing a new shared
    `ReportListTile` widget for both screens' list rows (date, both
    drivers' names, both plates, a status chip) — no source mockup exists
    for either screen (they weren't part of the imported design set), so
    both are built from the existing token/widget vocabulary rather than
    copied from an unseen screen, including the `errorHighlightBg`/
    `successHighlightBg` color tokens `app_colors.dart` had already
    reserved specifically for "the verify screen's hash-diff highlight"
    back in Phase 5.
  - **`ReportCompleteScreen` (13) gained an optional `report` constructor
    param** so `HistoryScreen` can push it standalone for a sealed report
    with no live session left to reconnect to (a session's `Session`
    document may be long TTL-expired by the time someone browses history,
    and re-opening a `SessionController`/socket for history browsing would
    be wrong regardless). `final report = widget.report ??
    context.watch<SessionController>().report;` — `??` short-circuits, so
    the existing live path (`SessionShellScreen`, `report` left null) never
    changes behavior, and the standalone path never requires a
    `SessionController` to exist in the widget tree at all. The report
    object History passes in is already the *full* document (`GET
    /api/reports?deviceId=` returns whole `Report` documents, not
    summaries), so no second network round trip is needed either.
  - **Confirmed live on the real two-device mobile UI**, not just the
    backend-only pass above: USB-connected physical phone + the user's own
    Chrome, `adb reverse tcp:3000 tcp:3000` for the phone (same setup as
    every prior phase's live run). Started both with a single
    `flutter run` each (phone first through its Gradle build, then Chrome
    — per the existing "never run two concurrent `flutter run`s against
    Android" caution; Chrome's build uses a different toolchain so running
    it alongside the already-launched phone was fine). Two real sessions
    were carried end to end through pairing → form → sketch/photos →
    review → signatures → finalize, reaching two independently sealed
    reports: `6a8c4964...99afb4` (tx `0xdca3b8c9...eae319e`, block 6) and
    `6a8c4846...99afa0` (tx `0x437aad45...ea8ac18085`). `node scripts/tamper.js
    6a8c4964...99afb4` was then run against the first — confirmed via
    `GET /verify` before (`VERIFIED`) and after (`TAMPERED`, `pdf.match:
    false`, `bundle.match` and every attachment still `true`, i.e. only the
    PDF was touched) — and the user confirmed the real Verify screen
    (reached via `ReportCompleteScreen`'s new "Proveri integritet" action)
    rendered the TAMPERED state correctly for that report. The second
    report was left untouched as a control and was not re-verified in this
    pass, but has no reason to differ from the backend-only VERIFIED case
    above.

- **Phase 12** — testnet deploy, README rewrite, demo script, acceptance
  checklist. No live two-device demo this phase, per the task's own
  instruction — everything below is backend scripts/API calls plus
  documentation review.
  - **Sepolia signer wallet**: a dedicated wallet was generated ahead of
    this phase specifically to sign Sepolia transactions, address
    `0x05915d206Db0FeceFd7874d5811c4585afeCca86`, funded via the
    [Google Cloud Web3 Sepolia faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia).
    Its private key was read from a local secrets file
    (`~/.accident-report-secrets/sepolia-wallet.env.local`, outside the
    repo, gitignored-equivalent by location) and merged into `.env` via a
    shell command that piped the value directly file-to-file — never
    echoed to any tool output or chat message, matching how the existing
    local Hardhat key is already handled.
  - **Deployed `AccidentRegistry` to Sepolia**:
    `npx hardhat run scripts/deploy.js --network sepolia` (existing
    `sepolia` network entry in `hardhat.config.js`, reading
    `RPC_URL`/`PRIVATE_KEY` from env — no config change needed). Address
    `0xF64198F2765cA34B52370948F74F0959573C9F6F`, RPC
    `https://ethereum-sepolia-rpc.publicnode.com` (the first candidate from
    the task's fallback list — worked on the first try, no need to fall
    back to `rpc.sepolia.org`/`sepolia.drpc.org`). `.env` updated:
    `CONTRACT_ADDRESS`/`CHAIN_NETWORK=sepolia`; `backend/src/abi/AccidentRegistry.json`
    regenerated with the same ABI (contract source unchanged) and the new
    address (that `address` field is purely informational — only `abi` is
    ever read by `chain.service.js` — but it's git-tracked, so it briefly
    showed as modified until the later local-redeploy step below
    regenerated it back to the local address; see the clean-clone item).
  - **Confirmed `CHAIN_NETWORK` is genuinely just a label with no code
    branching on it anywhere**: read `chain.service.js` end to end — the
    `ethers` provider/contract/wallet are built purely from
    `RPC_URL`/`CONTRACT_ADDRESS`/`PRIVATE_KEY`, no `if (network ===
    ...)` anywhere in the backend. Confirmed this in practice too: the same
    running `backend` container was pointed at `localhost` and then at
    `sepolia` (and back) with nothing but an `.env` edit + `docker compose
    up -d backend` between them — no rebuild, no other file touched.
  - **Mobile block-explorer link extended to `VerifyScreen`**
    (`mobile/lib/screens/verify_screen.dart`'s `_ChainDetailsCard`), which
    had none before this phase — only `ReportCompleteScreen` (Phase 10) had
    one. Rather than duplicate `ReportCompleteScreen`'s private
    `_kExplorerTxBaseUrls` map/`_openExplorer` method, extracted a shared
    `mobile/lib/utils/block_explorer.dart` (`kExplorerTxBaseUrls`,
    `explorerTxUrl(network, txHash)`) and pointed both screens at it — two
    call sites reading the same map is exactly the "reuse, don't duplicate"
    threshold. `flutter analyze` clean after the change.
  - **`backend/scripts/tamper.js` needs to run *inside* the backend
    container against a live stack, not from the host — a real operational
    finding, not documented before this phase.** `config.MONGO_URI` in
    `.env` is the `mongo` service hostname (`mongodb://mongo:27017/...`),
    which only resolves inside the docker compose network. Confirmed by
    direct testing: `cd backend && node scripts/tamper.js` fails
    immediately (no `backend/.env` for `dotenv` to find — the required-vars
    check in `config.js` fires first); `node backend/scripts/tamper.js`
    from the repo root finds the root `.env` fine (Node resolves
    `require("dotenv")` relative to `backend/scripts/`'s own
    `node_modules`, walking up from the file being required, not from
    `cwd`) but then fails with `getaddrinfo ENOTFOUND mongo` once it tries
    to connect. The working invocation is `docker compose exec backend node
    scripts/tamper.js <reportId>` — confirmed working against the real
    Sepolia run below. Documented in the README's Sepolia section so this
    doesn't have to be rediscovered next time.
  - **Live Sepolia anchor + tamper/verify run**, same shape as
    `backend/test/verify.test.js`'s `makeSealedReport()` and Phase 11's own
    local live smoke test, but against the real Sepolia-configured backend
    container instead of a mocked or local chain:
    1. Recreated the `backend` container with the Sepolia `.env`
       (`docker compose up -d backend`); `GET /api/health` →
       `{"mongo":"ok","chain":"ok","contract":"0xF64198F2765cA34B52370948F74F0959573C9F6F","network":"sepolia"}`.
    2. A temporary seed script (`backend/scripts/seed-throwaway-sepolia-demo.js`,
       `docker cp`'d into the running container rather than baked in via a
       rebuild, so the already-running Hardhat/Mongo state wasn't touched)
       created a minimal `status: "signing"` report — both parties'
       `confirmedReview: true` + a stored signature PNG each, one sketch
       PNG, one photo PNG, all real GridFS blobs — then a Session pointing
       at it. Report id `6a8c527a240dfd5810b2f623`.
    3. `POST /api/reports/6a8c527a240dfd5810b2f623/finalize` against the
       Sepolia-configured backend ran the real pipeline end to end,
       including a genuine `anchor()` transaction: `status: "sealed"`,
       `chain.txHash: 0xd8852329e6dea60ecf866e49b93e9c6e6601452f29daddca8208f384b3c2cf9e`,
       `chain.blockNumber: 11557579`, `chain.contractAddress:
       0xF64198F2765cA34B52370948F74F0959573C9F6F`, `chain.network:
       sepolia`. Viewable at
       `https://sepolia.etherscan.io/tx/0xd8852329e6dea60ecf866e49b93e9c6e6601452f29daddca8208f384b3c2cf9e`.
    4. `GET /api/reports/6a8c527a240dfd5810b2f623/verify` →
       `verdict: "VERIFIED"`, `pdf.match: true`,
       `pdf.recomputedHash === pdf.onChainHash`, `bundle.match: true` — the
       untouched-report half of the proof, now against a real public
       chain instead of local Hardhat.
    5. `docker compose exec backend node scripts/tamper.js
       6a8c527a240dfd5810b2f623` flipped one byte of the stored PDF in
       GridFS (report document's own `pdf.sha256` left untouched, per the
       script's existing design).
    6. Re-ran `GET /verify` → `verdict: "TAMPERED"`, `pdf.match: false`,
       `pdf.storedHash === pdf.onChainHash` (proving the mismatch is caught
       by the recomputed-vs-chain comparison, not a stale database field —
       same distinction Phase 11 made locally), `bundle.match: true`
       (only the PDF was touched, not an attachment) — the
       VERIFIED→TAMPERED flip, now demonstrated against Sepolia.
    7. Cleaned up afterward: deleted all 5 GridFS files (sketch, PDF, both
       signatures, photo) via `storage.deleteFile`, then the `Report` and
       `Session` documents themselves, then confirmed `GET
       /api/reports/6a8c527a240dfd5810b2f623` → `404`. Deleted the
       temporary seed script from both the running container and the repo
       (it was a one-off verification helper, not a permanent tool like
       `scripts/tamper.js` — nothing in the repo references it).
    8. Switched `.env` back to the local Hardhat values (`RPC_URL`,
       `CONTRACT_ADDRESS`, `PRIVATE_KEY`, `CHAIN_NETWORK=localhost`) and
       recreated the `backend` container again so routine dev work isn't
       left pointed at a public testnet.
  - **"`docker compose up` brings the stack up from a clean clone" tested
    directly**, not just read about: `git worktree add` at `HEAD` gave a
    genuinely separate checkout with none of this session's uncommitted
    changes. A first attempt used a `docker-compose.override.yml` with
    different host ports to run the clean-clone stack alongside the
    already-running dev stack — failed, because compose merges `ports:`
    arrays across base+override files rather than replacing them, so the
    base file's `27017:27017` mapping was still attempted and collided
    with the already-running `mongo` container. Correct approach: stop the
    main dev stack first (`docker compose down` — safe, no data depended on
    surviving it), run the clean-clone worktree's stack on the normal
    ports, confirm `docker compose up -d --build` + a fresh
    `npx hardhat run scripts/deploy.js --network localhost` +
    `docker compose up -d backend` reaches
    `{"mongo":"ok","chain":"ok",...}` from nothing but a checkout and
    `cp .env.example .env`, then tear the worktree stack down
    (`docker compose down -v`) and remove the worktree. Brought the main
    dev stack back up afterward and redeployed the contract to its
    (now-reset, since stopping `hardhat` wipes its in-memory chain) local
    node — same deterministic address as before
    (`0x5FbDB2315678afecb367f032d93F642f64180aa3`, confirmed via `git
    status` that this also restored `AccidentRegistry.json` to match the
    committed version).
  - **README.md rewritten in full**: project description, an architecture
    diagram, prerequisites, setup from a clean clone (kept close to the
    original but now cross-referenced against the fresh-worktree test
    above), a full environment-variable reference table (including the
    "no code change to switch networks" claim, now verified rather than
    assumed), how to run all three services, how to run the mobile app
    against each network configuration (emulator/USB device/Chrome — the
    table clarifies `API_URL` depends on *how you reach the backend*, not
    on which chain the backend is anchoring to), the Sepolia deploy
    walkthrough (steps 0-3 of this task) including the
    `tamper.js`-needs-the-container finding, the full test-command
    reference for all three subsystems, and the eight-step demo script
    from master_plan.md §9 with exact commands, explicitly marking which
    steps were vs. weren't re-run this phase.

## Acceptance checklist (master_plan.md §11) — walked item by item, Phase 12

- [x] **No personal data is written on-chain.** Read
  `blockchain/contracts/AccidentRegistry.sol` end to end: `Record` holds
  only `pdfHash`, `bundleHash`, `timestamp`, and `submitter` (the backend's
  own address, not a driver's identity); `anchor()`/`getRecord()`/`verify()`
  take/return only `bytes32` hashes, a `reportId`, and a timestamp. Cross-
  checked `chain.service.js`'s `anchorReport(reportId32, pdfHash32,
  bundleHash32)` call site — nothing else is ever passed. No driver name,
  plate, address, or any other PII crosses into a chain call anywhere in
  the codebase.
- [x] **Verification passes on an untouched report and fails on a tampered
  one, identifying the affected file.** Demonstrated live against Sepolia
  (Decisions above): `VERIFIED` → `scripts/tamper.js` → `TAMPERED`,
  `pdf.match: false` naming the PDF specifically (a `--photo` run would
  instead name that attachment's entry in `attachments`, as already proven
  locally in Phase 11's "names the specific file" test and live run).
- [x] **PDF is generated and matches the statement structure with photos,
  sketch, and both signatures embedded.** Checked two ways: (1)
  `backend/test/pdf.test.js`'s fully-filled-report case asserts an exact
  page count against a report with real sketch/photo/signature attachments,
  and separately exercises the empty-optional-fields, long-remarks, and
  14-photo-pagination cases (Phase 9). (2) Downloaded a real sealed PDF
  from this session's local Mongo (`GET
  /api/files/6a8c417566cfead94c3c7ce9`, the PDF for already-sealed report
  `6a8c412066cfead94c3c7cdd` from Phase 10's live run) and confirmed with
  `file` that it's a valid 3-page PDF document.
- [x] **PDF and every attachment have stored SHA-256 hashes.** Queried
  Mongo directly for sealed reports from earlier live-testing phases (ids
  `6a8c412066cfead94c3c7cdd`, `6a8c4846...99afa0`, `6a8c4964...99afb4`):
  each has a non-null `pdf.sha256` and a 4-entry `attachmentHashes` array
  (sketch + 2 signatures + 1 photo), each entry with its own `sha256`. Same
  shape confirmed again on the throwaway Sepolia report before cleanup.
- [x] **Hash + bundle hash are anchored on-chain with a retrievable tx
  hash.** The Sepolia run above: tx
  `0xd8852329e6dea60ecf866e49b93e9c6e6601452f29daddca8208f384b3c2cf9e`,
  block `11557579`, contract `0xF64198F2765cA34B52370948F74F0959573C9F6F`,
  publicly retrievable at
  `https://sepolia.etherscan.io/tx/0xd8852329e6dea60ecf866e49b93e9c6e6601452f29daddca8208f384b3c2cf9e`
  — a real public testnet, not just local Hardhat.
- [x] **`docker compose up` brings the whole backend stack up from a clean
  clone.** Demonstrated directly in a separate `git worktree` checkout with
  none of this session's changes present (Decisions above) —
  `docker compose up -d --build` → `mongo: ok`, `chain: error` (expected,
  placeholder contract) → deploy → `docker compose up -d backend` →
  `chain: ok`, matching the README's own documented sequence exactly.
- [x] **README documents setup, env vars, deploy, and the demo script.**
  This phase's rewrite (Decisions above) covers all four explicitly, plus
  prerequisites, architecture, per-network mobile run commands, and the
  full test-command reference, which the checklist item doesn't strictly
  require but master_plan.md §0's "demonstrable" goal implies.
- [ ] **An emulator (party A) and one USB-connected physical phone (party
  B) complete a report end to end.** **Not demonstrated in Phase 12** — no
  live two-device demo was in scope this phase, per the task's own explicit
  instruction. Already demonstrated for real multiple times in earlier
  phases' own live testing, cited here rather than re-run: Phase 6 (pairing
  only), Phase 7 (form/circumstances/sketch/photos, phone + emulator, later
  phone + Chrome after the emulator was dropped as unreliable on this
  machine), Phase 8 (review/signing/locking, phone + Chrome), Phase 10
  (finalize/anchor through screens 12-13, phone + Chrome, sealed report
  `6a8c412066cfead94c3c7cdd`), and most completely Phase 11 (screens 14-15,
  full pairing-through-verify run on phone + Chrome, two independently
  sealed reports `6a8c4846...99afa0` and `6a8c4964...99afb4`, one of them
  carried through the tamper/verify TAMPERED flow on the real Verify
  screen). See "Known issues" below.

- **Post-Phase-12 hardening: per-party freeze on sign**, prompted by a
  defense-prep conversation about how far the "provably unaltered" claim
  actually extends. The honest answer walked through with the user: the
  chain anchor only proves the *sealed* report wasn't altered *after*
  sealing — it says nothing about whether the report ever faithfully
  reflected what the two drivers confirmed/signed *during* the live
  session, since `confirmedReview` was just a boolean patch with no
  binding to a specific data snapshot, and — because the report only
  locked once *both* parties had confirmed+signed
  (`report-lock.service.js`'s `bothPartiesSignedOff`) — a party who had
  already confirmed and signed could still freely patch their own subtree
  again while waiting on the other party. That's a real (if narrow, in
  practice) TOCTOU gap between "what I signed" and "what got finalized,"
  distinct from the general blockchain "oracle problem" (no system can
  cryptographically prove *input* honesty, only detect *post-hoc* tampering
  of whatever was recorded) — the oracle problem is inherent to any such
  system and out of scope to "fix," but this specific gap was just this
  implementation being more permissive than necessary.
  - Added `partySignedOff(report, party)` to `report-lock.service.js`
    (one party's half of `bothPartiesSignedOff`, which now just calls it
    for both parties) and used it in two places: `session.socket.js`'s
    `report:patch` handler rejects a patch into `partyA.*`/`partyB.*` with
    a new `PARTY_LOCKED` error once *that* party has already confirmed
    review and signed, even if the other party hasn't; `uploads.js`'s
    signature route rejects a second signature upload from the same
    already-signed party the same way (`409 PARTY_LOCKED`) — otherwise the
    field-patch freeze could be sidestepped by just re-signing instead.
  - **Deliberately scoped to structured party fields only** — confirmed
    with the user before implementing: photos (party-attributed but not
    part of the review screen's confirmed content) are explicitly *not*
    frozen by this change; shared subtrees (`accident.*`/`sketch`) stay
    open until the *whole* report locks (`maybeLockReport`, both parties),
    since they're joint by design and freezing them on one party's
    signature would block the other party's own legitimate edits before
    they've even reviewed/signed themselves.
  - **No mobile-side code change needed.** `session_shell_screen.dart`'s
    existing `_maybeShowError` already renders any `session:error.message`
    in a SnackBar, generically, for every error code — `PARTY_LOCKED` is
    covered by that same mechanism with zero new client code. (Proactively
    blocking back-navigation to an already-signed party's earlier steps,
    so they never even attempt the now-rejected write, was considered and
    explicitly deferred — the user opted for "backend rejection + error
    message" over the extra Flutter work, at least for now.)
  - Covered by 4 new backend tests: `session-report.test.js` (a signed
    party's own patch is rejected `PARTY_LOCKED` while the report/session
    stay unlocked; the *other*, not-yet-signed party can still patch their
    own subtree; either party can still patch shared `accident.*` after
    one party has signed) and `uploads.test.js` (a second signature upload
    from an already-signed-off party is rejected `409 PARTY_LOCKED`, and
    the original signature's `fileId` is left untouched). `npm test`: 62/62
    passing (was 58 before this change). `flutter analyze`: clean
    (no mobile files touched).

- **Post-Phase-12 fixes found via live two-device testing**, in one round:
  the sketch step and a data-loss bug in the socket patch handler.
  - **Sketch step (`mobile/lib/screens/steps/sketch_step.dart`) had six
    real bugs**, all found by the user clicking through the actual app:
    a screen-size-dependent canvas instead of the real report's fixed 2:1
    diagram-box ratio; a hardcoded crossroads background that doesn't
    belong on a freeform sketch; freehand strokes invisible until switching
    back to the hand tool; the rotation handle not working on either
    device; the sketch silently resetting/overwriting when the second
    party reached the step; and the canvas losing touch gestures to the
    page scroll on phones. Fixed together:
    - **2:1 canvas + 12x6 dotted grid**: fixed logical canvas at
      `Size(400, 200)`, wrapped in `AspectRatio` + `FittedBox` so it scales
      to any screen width while staying exactly 2:1 — all existing item/
      stroke position math is untouched (still in the same fixed 400x200
      coordinate space Flutter's hit-testing/`RepaintBoundary.toImage`
      automatically account for through the scaling ancestors). Grid drawn
      as 13 dashed vertical + 7 dashed horizontal lines (12x6 cells).
    - **Crossroads removed**: `_RoadPainter` → `_GridPainter`, stripped the
      hardcoded road strips/dashed center lines, kept grid + coordinate
      caption. Deleted the now-dead `illustrationRoad` color token.
    - **Invisible strokes while drawing**: `_StrokesPainter.shouldRepaint`
      compared the same mutated `List` by identity (`_strokes.add(...)`
      never reassigns the list) — always `false`, so `CustomPaint` skipped
      repainting mid-stroke even though `setState` had rebuilt the widget
      tree with a new painter instance. Fixed by always returning `true`.
    - **Rotation handle unreachable**: a real Flutter hit-test gotcha, not
      a device issue — `RenderBox.hitTest`'s `size.contains(position)`
      check rejects a point before ever trying that box's children, so
      sizing the item's outer `Positioned` to exactly the icon's 40x40 and
      only *painting* the handle outside those bounds (via
      `clipBehavior: Clip.none`) left most of the visible handle outside
      the hit-testable region. Fixed by enlarging the outer bounding box
      (`_boundsSize = Size(112, 112)`) to comfortably contain the handle's
      full swept circle at any rotation angle, with the icon and handle
      repositioned relative to the new, bigger box's center.
    - **Sketch reset on the second party's turn** — the real bug behind
      it: the sketch only ever round-trips as a flattened PNG (no
      persisted vector/structured state), so `SketchStep.initState()`
      always started from a blank `_defaultItems()` regardless of what the
      other party had already drawn; whoever saved second silently
      overwrote the first party's sketch. Discussed two fixes with the
      user before implementing — persisting structured canvas state for
      true live collaborative editing, vs. restricting editing to one
      party — and went with the simpler one per the user's own suggestion:
      **only the session creator (party A) gets the interactive canvas**;
      party B sees a read-only view (the uploaded image once it exists, or
      a "waiting for Vozač A" placeholder before that, reactively updating
      off the already-live-synced report with no polling). Deliberately
      scoped narrower per follow-up discussion: doesn't extend to photos
      (not part of what Review actually confirms), and shared subtrees
      (`accident.*`/`sketch` broadcast path) aren't otherwise touched.
      `review_step.dart`'s sketch preview card updated from `aspectRatio: 1`
      to `2` to match the shape change.
    - **Phone: canvas gestures lost to page scroll** — removed the
      `SingleChildScrollView` that wrapped the canvas; it's now a
      non-scrolling layout with the canvas in an `Expanded`, so there's no
      ancestor `Scrollable` for the draw gesture to lose a gesture-arena
      contest against. This was the root fix, not a workaround — no amount
      of `HitTestBehavior`/gesture-priority tuning changes that a `Pan`
      recognizer competing against an ancestor `Scrollable`'s own drag
      recognizer is inherently fragile; removing the competing ancestor
      entirely is what actually closes it.
  - **`FinalizingScreen` briefly showed a raw Dio "request took longer than
    expected" banner** once the backend was pointed at Sepolia for the
    user's own testnet check (see the Phase 12 entry above) — `ApiClient`'s
    shared Dio instance has an 8s default timeout, but `POST /finalize`'s
    HTTP response doesn't return until the whole pipeline completes
    server-side (`routes/reports.js` awaits `runFinalize` before
    responding), including a real chain confirmation that the screen's own
    hint text already says takes 20-40s on a public testnet — so the
    client gave up and surfaced Dio's raw timeout message as if finalize
    had failed, even though the pipeline kept running fine server-side and
    sealed moments later. Fixed two ways: `ApiClient.finalizeReport` now
    passes a 90s `receiveTimeout`/`sendTimeout` via per-call `Options`
    (leaving the 8s default alone for every other, genuinely-short REST
    call) so this stops happening in the normal case; and `ApiException`
    gained an `isTimeout` flag (set from `DioExceptionType`) so
    `FinalizingScreen._start()` can specifically swallow a *timeout*
    without swallowing a real server-reported failure — a client-side
    timeout on this one call was never actually a failure signal to begin
    with, since the screen's step rows already reflect the real outcome
    via `report:progress`/`report:sealed` and the report's own persisted
    fields, independent of whether this particular HTTP request is still
    open.
  - **Vehicle/insurer fields silently missing from the generated PDF** —
    the most involved fix of this round, found because the user checked a
    real generated PDF closely. Confirmed first via direct Mongo inspection
    of the actual sealed report (not just re-reading the code) that the
    data was genuinely absent from the database, not merely a PDF-layout
    bug: `partyA.vehicle` was missing as a key entirely, and
    `partyA.insurer` had only its very-last-patched field (`validTo`) —
    identical pattern on both parties' independent reports. Root-caused
    and *confirmed* with a standalone repro script
    (`socket.io-client` against the real running dev backend, no jest
    scaffolding needed for the first pass) that fired the exact same burst
    `my_details_step.dart`'s `_fillSampleData` sends (~18
    `report:patch` events back-to-back with zero pacing between them,
    matching how the "Popuni test podacima" button works) — reproduced the
    identical missing-field pattern on the very first run, confirming this
    is a deterministic bug, not network jitter. Mechanism: `session.socket.js`'s
    `report:patch` handler does an independent `Report.findById` →
    `.set(path, value)` → `.save()` for every single incoming patch, with
    no serialization; when several patches for the same report arrive
    close together, each fetches its own snapshot before any of the others
    have committed. For a leaf under a *not-yet-existing* nested
    subdocument (`partyA.vehicle` and `partyA.insurer` both start out
    absent — Mongoose's default `minimize: true` drops an all-undefined
    embedded object from what's actually persisted), Mongoose's dirty-path
    tracking marks the *whole parent path* as modified rather than the
    individual leaf, so each concurrent patch's `.save()` generates a
    conflicting whole-object `$set` on the same key — concurrent
    whole-object `$set`s to the same key don't merge, and whichever
    commits last silently wins, discarding the others' fields, with no
    error thrown anywhere (confirmed nothing appeared in the backend
    logs during the repro). Driver fields survived because they were
    patched first in the burst and (in this instance) didn't collide with
    a later group the same way; this was never guaranteed and could just
    as easily have hit driver fields on a different run — the bug is
    general to "concurrent patches into any not-yet-existing subdocument
    leaf," not vehicle/insurer specifically.
    - **Fix**: a new `backend/src/services/report-mutex.service.js`
      (`withReportLock(reportId, task)`) — a plain in-memory `Map` of
      chained promises, one per reportId, that serializes the *whole*
      fetch→set→save→broadcast sequence per report (different reports
      still process fully concurrently). Same "single Node process, no
      clustering per docker-compose §7" trade-off already accepted for
      `finalize.service.js`'s own per-report guard, just a queue instead
      of a reject-if-busy lock, since every patch here carries real data
      that must be *applied*, not dropped. Wired into `session.socket.js`'s
      `report:patch` handler around the report fetch through the
      `report:patched` broadcast and the `maybeLockReport`/`partySignedOff`
      checks added in the earlier post-Phase-12 hardening entry — those are
      now implicitly race-safe too, as a side effect of the same fix.
    - **Verified the fix closes it**: re-ran the exact same standalone
      repro script against the rebuilt backend — every field now present
      and correct. Added a proper regression test in
      `backend/test/session-report.test.js` ("keeps every field from a
      burst of concurrent patches into a not-yet-existing subdocument")
      and *confirmed the test itself is meaningful*, not a false-positive:
      temporarily bypassed `withReportLock` (`return task()` short-circuit)
      and watched the new test fail with the exact same missing-field
      shape, then restored the real fix and confirmed the full suite
      (63/63) passes again.
  - **Renamed "Broj zel. karte" → "Zeleni karton"** (green card number
    field label) in both `pdf.service.js` and `my_details_step.dart`, per
    user request — matches the PDF's existing compact-label convention
    (e.g. "Osiguravač", not "Naziv osiguravača") rather than a longer
    grammatically-inflected form that risked overflowing the PDF's fixed
    82px label column at this font size.
  - Rebuilt and recreated the `backend` container for each of the above
    (`docker compose build backend` + `up -d --no-deps backend`, same
    non-`--build` care as every prior phase) before re-verifying; cleaned
    up every throwaway Mongo document created by the two repro scripts
    afterward. `npm test`: 63/63. `flutter analyze`: clean. `flutter test`:
    passing.

## Project status

**Feature-complete, and confirmed end to end by the user.** After the
post-Phase-12 sketch/finalize/PDF fixes above, the user drove a full
two-device session (phone + Chrome) through the real mobile UI — pairing,
form, sketch, photos, review, both signatures — against the Sepolia-
configured backend, and it sealed for real: report `6a8c7f8d85819414af65e6bd`,
tx `0x11aed0a798822d6125a9d91a0894c03a643e8db67c4716850086c168c5ea21d0`,
viewable at
`https://sepolia.etherscan.io/tx/0x11aed0a798822d6125a9d91a0894c03a643e8db67c4716850086c168c5ea21d0`.
This is a strictly stronger confirmation than Phase 12's own Sepolia
verification (which only exercised the backend via scripts, not the live
UI) — it closes the one item Phase 12's acceptance checklist had filed as
a gap: the live two-device run had been demonstrated locally in Phases
6-11 and via script against Sepolia in Phase 12, but never through the
real UI against the public testnet until now.

## Known issues

- **No outstanding known issues.** The two-device run above closes the one
  gap left open after Phase 12 (see "Project status"). If a committee wants
  a *fresh* run immediately before the defense, it's still worth
  rehearsing once more close to demo day regardless, per master_plan.md
  §9's "rehearse this" — routine practice, not because anything is known
  to be broken.
