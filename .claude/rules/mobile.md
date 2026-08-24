---
paths: ["mobile/**"]
---

# Mobile rules

## Design system (Phase 5)

Source: Claude Design project `78016f84-06e4-4866-bbc0-818cdb195c9d`, file
`Accident Report App.dc.html` (16 screens, incl. a "BOJE/TIPOGRAFIJA/RITAM I
MREŽA/KOMPONENTE" spec sheet at the top). `android-frame.jsx` and
`support.js` from that project are the design canvas's own device-frame
renderer and template runtime — they are tooling for viewing the mockups,
not app content, and were not ported.

Every token lives under `lib/theme/`, one file per concern, re-exported from
`lib/theme/theme.dart`. **No screen or widget may inline a hex color, a raw
font size/weight, a spacing number, or a border radius — always reference a
token.** If a new value is genuinely needed, add a named step to the
relevant token file (don't inline a one-off, don't silently reuse the
nearest existing step if it's visibly wrong).

- `app_colors.dart` — `AppColors`. Semantic groups: brand (`navy`/`cobalt`/
  `amber`), paper-surface hierarchy (`paper`/`surface`/`surfaceAlt`/
  `surfaceMuted`/`border`/`borderLight`/`borderDashed`), text (`textPrimary`/
  `textSecondary`/`textMuted`), on-navy variants (`onNavy*`, `navyTrack`,
  `navyBorder`, `sessionSelfPanelBg`/`sessionOtherPanelBg`), and status
  triads — each of `pending`/`success`/`error` has a `*Bg`/`*Border`/`*Text`
  set. `confirmed` and `verified` (see status_chip.dart) both use the
  `success*` triad; the source design never visually distinguishes "a party
  confirmed review" from "the hash check passed on this report" — those are
  told apart by label/context, not color.
- `app_spacing.dart` — `AppSpacing`. The design's own scale: `xs`=4, `sm`=8,
  `md`=12, `lg`=16, `xl`=24, `xxl`=32 ("Koraci: 4/8/12/16/24/32"). Also
  `minTapTarget`=56 ("Minimalni tap: 56 px" — gloved/one-handed roadside
  use); apply it as the minimum height of every tappable control.
- `app_radii.dart` — `AppRadii`. `none`=0 (fields, cards, sections — the
  design is square almost everywhere), `button`=3, `badge`=2.
- `app_elevation.dart` — `AppElevation.flat` (=0). The design is
  deliberately flat: "Ivice sekcija: 1px #CFCABD, bez senki" (no shadows —
  depth comes from a 1px border, see `AppColors.border`). This file exists
  so that's a documented choice, not an omission; don't add `boxShadow`
  anywhere without discussing it first.
- `app_typography.dart` — `AppFontFamily` (family name strings) and
  `AppTypography` (the ~21-step type scale, one `const TextStyle` per named
  step, grouped by family — see the file's doc comments for what each step
  is for). Styles carry no color; apply one via
  `AppTypography.someStyle.copyWith(color: AppColors.something)` at the call
  site, since the same size/weight is reused on both paper and navy
  backgrounds with different colors.
- `app_theme.dart` — `AppTheme.light` assembles the one `ThemeData` the app
  uses (no dark theme; the design is a single fixed palette).

## Fonts

Archivo (500/600/700), IBM Plex Sans (400/500/600), IBM Plex Mono
(400/500/600), and Caveat (600) — all four are freely available (Google
Fonts, SIL OFL), so no substitution was needed. Bundled as static `.ttf`
assets under `mobile/assets/fonts/` (not the `google_fonts` pub package) so
the app renders correctly with zero network dependency, chosen specifically
for demo-day reliability — see PROGRESS.md decisions. Archivo, IBM Plex
Sans, and Caveat ship upstream only as variable fonts; each is declared in
`pubspec.yaml` as one asset file with multiple `weight:` entries (Flutter/
Skia renders the correct instance per declared weight). IBM Plex Mono ships
pre-cut static weight files upstream, used directly. OFL license texts are
kept alongside in `assets/fonts/licenses/`.

## Widget set (`lib/widgets/`, barrel `widgets.dart`)

Seven components, each derived from a real recurring pattern across the 16
screens (not invented ahead of need):

- `AppButton` (`app_button.dart`) — `AppButtonVariant.primary/secondary/
  destructive`. Full-width, `AppRadii.button`, height `AppSpacing.
  minTapTarget`. `destructive` doesn't appear in the source design as a
  filled-red button — it's derived from the error color tokens per
  docs/master_plan.md §1's "derive missing states from existing tokens"
  instruction. `onPressed: null` renders a derived disabled state (also not
  in the source design).
- `AppTextField` (`app_text_field.dart`) — label above (always
  `monoFieldLabel`, uppercased) + bordered value box. States: normal,
  focused (1.5px navy border — the only emphasis state the design actually
  shows, on the plate field), `error` (pass `errorText`, derived), disabled
  (pass `enabled: false`, derived). Pass `monospace: true` for code-like
  values (plate, licence/policy numbers) that the design sets in IBM Plex
  Mono instead of IBM Plex Sans.
- `CircumstanceTile` (`circumstance_tile.dart`) — one box in the
  circumstances checkbox grid; `checked` flips the whole tile from a
  white/outlined card to a solid-navy one with an amber check.
  min-height 96, matching the design.
- `SectionHeader` (`section_header.dart`) — the uppercase mono label bar
  ("VREME I MESTO", "STRANE", "OKOLNOSTI") that titles a block inside a
  bordered card. Draws only the header bar; wrap it and the content
  together in your own `Border.all(color: AppColors.border)` container.
- `StatusChip` (`status_chip.dart`) — `AppStatusChipVariant.pending/
  confirmed/verified/tampered`. Matches the exact chip shown in the design's
  own "KOMPONENTE" spec-sheet entry: tinted background + 4px colored left
  border + colored label.
- `MonoDataRow` (`mono_data_row.dart`) — label/value pair for evidence data.
  Default is inline (label left, mono value right — review rows, tx refs);
  `stacked: true` is the full-width wrapping block used for the verify
  screen's full hash display.
- `SessionProgressHeader` (`session_progress_header.dart`) — the persistent
  navy header (screen 1d) wrapping the shared-form screens: session code +
  live indicator, then a two-column split of `SessionPartyProgress` (label,
  stage, 0..1 progress). The self party is highlighted in amber; the other
  party uses the muted on-navy tokens.

## Gallery

`lib/screens/dev_gallery.dart` renders every token group and every widget
in every state. As of Phase 6 it is no longer the home route — `main.dart`
wires the real Home screen (§6 screen 1) instead — and is reachable only
via a `kDebugMode`-gated icon in Home's header (absent from release
builds). The gallery is scaffolding, not a screen in the 15-screen set, and
should not ship as a reachable route in a release build.

## Screens 1-4 & networking (Phase 6)

`lib/services/api_client.dart` (REST, via `dio`) and
`lib/services/socket_client.dart` (Socket.IO, via `socket_io_client`) wrap
the endpoints/events in docs/master_plan.md §5.2/§5.3. Both take a
`baseUrl` — always `Env.apiUrl` (`lib/config/env.dart`, reading
`--dart-define=API_URL`), never hardcoded; `main.dart` shows an explicit
error screen instead of falling back to a guessed host if it's empty.

`lib/state/session_controller.dart` is a `ChangeNotifier` created per
session (by `SessionShellScreen`) that owns one `SocketClient`: it joins on
construction, re-joins automatically on every reconnect (see
`socket_client.dart`'s doc comment — `session:join` is idempotent and
socket.io's own `connect` event fires on both first connect and every
reconnect, which is what drives the `session:state` resync), and tracks
`connectionState`/`otherPartyConnected` for the header and the shell's
reconnecting banner. Phases 7+ read/write through this same controller
(`sendPatch`/`sendReady`) rather than opening their own socket.

`socket_client.dart` forces `transports: ['websocket']` — confirmed by
testing that the default (polling-first) transport list never completes
its handshake against this backend, on emulator or physical device.
Don't remove this to chase a reconnect bug; that was tried and broke the
connection outright on both platforms (see PROGRESS.md). Any screen that
opens its own short-lived `SocketClient` (e.g. `CreateSessionScreen`
watching for the other party to join) must explicitly cancel its stream
subscriptions and call `.dispose()` on it itself before navigating away —
not rely on `State.dispose()` — since the next screen's own socket can
otherwise start up while the old one is still overlapping it, which was
observed to leave the new socket stuck reconnecting indefinitely.

`lib/models/` mirrors the full `Report`/`Session` Mongoose schemas
(fromJson/toJson, no validation) even though Phase 6 only reads
`status`/party connectivity off them — so Phase 7's form screens can start
patching real fields immediately.

Session codes are always exactly 6 characters
(`backend/src/services/session-code.service.js`'s `ALPHABET`/`CODE_LENGTH`)
— the design mockup's "K7M-4RQ2" 7-char hyphenated display is decorative
only, not the real format. The QR encodes the raw 6-char code as plain
text (no URI scheme); the create-session screen displays it as two
groups of 3 for readability. History (screen 15) and Verify (screen 14)
rows on Home render per the design but are inert (snackbar) until Phase
11 builds those screens.

## Screens 10-11 & read-only locking (Phase 8)

`lib/screens/steps/review_step.dart` (screen 10) and `signature_step.dart`
(screen 11) extend the same `SessionShellScreen` `IndexedStack` step flow
Phase 7 established — `_kSteps` now has 7 entries (steps 2-8 of 8; step 1 is
pairing, screens 1-4). Review's "Potvrđujem da su podaci tačni" button sends
a plain `report:patch` to `partyX.confirmedReview` (already own-subtree
patchable, no new endpoint) rather than anything bespoke. Signature uses the
`signature` pub package (not a hand-rolled `CustomPainter` like the sketch
step) — its own canvas ships `clear()`/`undo()`/`redo()`, matching §6 screen
11's "clear/redo" directly; export is pinned to a fixed 600×300 canvas via
`toPngBytes(width:, height:)` rather than the package's default
cropped-to-strokes size, uploaded via the new `ApiClient.uploadSignature`.

`SessionController.isLocked` is the one flag every screen reads for "am I
still editable" — derived from a `session:state` snapshot's `status` (a new
`kLockedSessionStatuses` set in `session_model.dart`, mirroring the
backend's `LOCKED_STATUSES`) or set immediately by a live `report:locked`
event (`.claude/rules/backend.md`). `SessionShellScreen` wraps its *entire*
step `IndexedStack` — not just Review/Signature — in one
`IgnorePointer(ignoring: isLocked)` + dimmed `Opacity`, plus a
`_LockedBanner`, rather than threading an `enabled`/`isLocked` prop through
every `PatchTextField`/`PatchToggleRow`/button on every step screen
individually. This is why gating "every edit affordance" required no
changes at all to `accident_details_step.dart`, `my_details_step.dart`,
`circumstances_step.dart`, `sketch_step.dart`, or `photos_step.dart` — the
gate lives above all of them. One consequence: a step's own "next" button
lives inside the same ignored region, so `_SessionShellBodyState` has a
one-time `_maybeJumpToReviewOnLock` that jumps to Review the first time
`isLocked` flips true while the viewer is sitting on an earlier step (e.g.
they went back to double-check something while the other party finished
signing) — otherwise there'd be no way forward once locked.

Photos are now live-synced between parties (closing the Phase 7 "not
live-synced" known issue) as a side effect of the server broadcasting
`report:patched` with `path: "photos"` after its own upload/delete — no
mobile-side change was needed for this, `photos_step.dart`'s existing
local-optimistic/dedupe-by-fileId merge (Phase 7) already treats "fileId is
in the remote list" as the signal to drop its own optimistic entry.

## Scope note

Phase 5 was tokens + shared widgets only, with no screens, models, or
networking. Phase 6 (screens 1-4, session pairing) added all three — see
the section above and PROGRESS.md for the phase table.
