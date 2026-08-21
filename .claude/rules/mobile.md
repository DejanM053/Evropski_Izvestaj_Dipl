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
in every state, and is temporarily wired as the app's home route in
`main.dart`. **Replace `home: const DevGalleryScreen()` with the real Home
screen (§6 screen 1) as soon as Phase 6 starts** — the gallery is scaffolding,
not a screen in the 15-screen set, and should not ship.

## Scope note

Phase 5 is tokens + shared widgets only. No screens, models, or networking
(`socket_io_client`, `dio`/`http`) were added — those start in Phase 6. See
PROGRESS.md for the phase table.
