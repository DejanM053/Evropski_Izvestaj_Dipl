# Progress

## Current phase

Phase 8 — Screens 10–11 (review + signatures)

## Phases (from master_plan.md §8)

- [x] Phase 0 — Repository restructure (mobile/backend/blockchain split, root config)
- [x] Phase 1 — Contract + Hardhat tests
- [x] Phase 2 — Docker Compose + backend skeleton + `/api/health`
- [x] Phase 3 — Session + report CRUD + Socket.IO sync
- [x] Phase 4 — GridFS uploads + hashing
- [x] Phase 5 — Design system → Flutter theme + widgets
- [x] Phase 6 — Screens 1–4 (session pairing)
- [x] Phase 7 — Screens 5–9 (form, circumstances, sketch, photos)
- [ ] Phase 8 — Screens 10–11 (review + signatures)
- [ ] Phase 9 — PDF generation
- [ ] Phase 10 — Finalize + anchor + screens 12–13
- [ ] Phase 11 — Verify endpoint + screens 14–15
- [ ] Phase 12 — Testnet deploy + README + demo script

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

## Known issues

- `GET /api/reports?deviceId=` doesn't filter — no `deviceId` field exists
  anywhere in §5.1's schemas yet. Needs a schema decision before the mobile
  client's local-deviceId history scoping (§6 client rules) can work.
- Photos aren't live-synced between parties (no socket broadcast on
  upload/delete — see Phase 7 decisions above for why). Each party sees
  their own photos immediately; the other party only sees them after a
  reconnect. Not a blocker for the Phase 7 "done when," but worth fixing
  with a dedicated broadcast event before the Review screen (Phase 8)
  needs to show both parties' photos without requiring a reconnect first.
