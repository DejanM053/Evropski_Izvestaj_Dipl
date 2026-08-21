# Progress

## Current phase

Phase 6 — Screens 1–4 (session pairing)

## Phases (from master_plan.md §8)

- [x] Phase 0 — Repository restructure (mobile/backend/blockchain split, root config)
- [x] Phase 1 — Contract + Hardhat tests
- [x] Phase 2 — Docker Compose + backend skeleton + `/api/health`
- [x] Phase 3 — Session + report CRUD + Socket.IO sync
- [x] Phase 4 — GridFS uploads + hashing
- [x] Phase 5 — Design system → Flutter theme + widgets
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

## Known issues

- `GET /api/reports?deviceId=` doesn't filter — no `deviceId` field exists
  anywhere in §5.1's schemas yet. Needs a schema decision before the mobile
  client's local-deviceId history scoping (§6 client rules) can work.
