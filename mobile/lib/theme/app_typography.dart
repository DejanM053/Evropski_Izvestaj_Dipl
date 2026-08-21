import 'package:flutter/widgets.dart';

/// Font family names as declared in pubspec.yaml. See .claude/rules/mobile.md
/// for which family each covers.
class AppFontFamily {
  AppFontFamily._();

  /// Headings, hero numbers, screen titles.
  static const display = 'Archivo';

  /// Body copy, instructions, buttons.
  static const body = 'IBM Plex Sans';

  /// Anything that is evidence: codes, plates, hashes, tx refs, timestamps.
  static const mono = 'IBM Plex Mono';

  /// Decorative "handwritten" signature preview text only — never real UI
  /// chrome. The actual signature capture (Phase 8) uses the `signature`
  /// package's drawing pad, not this font.
  static const signature = 'Caveat';
}

/// Type scale distilled from every distinct text treatment observed across
/// the 16 design screens, grouped by family and rounded to a manageable set
/// of named steps. Colors are deliberately omitted here — apply them via
/// `.copyWith(color: ...)` at the call site, since the same size/weight is
/// reused on both paper and navy backgrounds with different colors.
///
/// No screen or widget should declare a raw TextStyle — pick the closest
/// step here, or add a new named step if none fits (don't inline one-offs).
class AppTypography {
  AppTypography._();

  // Archivo — headings ---------------------------------------------------

  /// Hero title (home screen banner). 700/26, e.g. "Evropski izveštaj o
  /// saobraćajnoj nezgodi".
  static const TextStyle displayLarge = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    height: 1.15,
  );

  /// Big status headline (finalizing / sealed / verify banner). 700/22.
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.2,
  );

  /// Prominent card title (e.g. "Novi izveštaj"). 600/19.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w600,
    fontSize: 19,
  );

  /// Secondary title (session/empty-state titles). 600/17.
  static const TextStyle titleMedium = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w600,
    fontSize: 17,
  );

  /// The screen app-bar/step-header title — the single most reused text
  /// style in the design, appearing on nearly every screen. 600/16.
  static const TextStyle titleSmall = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w600,
    fontSize: 16,
  );

  /// Session shell title ("Sesija K7M-4RQ2"). 600/15.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: AppFontFamily.display,
    fontWeight: FontWeight.w600,
    fontSize: 15,
  );

  // IBM Plex Sans — body / UI ---------------------------------------------

  /// Field values, primary reading text. 400/16.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w400,
    fontSize: 16,
  );

  /// Button label. 500/15.
  static const TextStyle buttonLabel = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w500,
    fontSize: 15,
  );

  /// List/card item headline (e.g. history entry name). 600/14.5.
  static const TextStyle itemTitle = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w600,
    fontSize: 14.5,
  );

  /// Standard paragraph / instructional text. 400/13.5.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w400,
    fontSize: 13.5,
    height: 1.4,
  );

  /// Helper text, list supporting text. 400/12.5.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    height: 1.4,
  );

  /// Meta captions. 400/11.5.
  static const TextStyle caption = TextStyle(
    fontFamily: AppFontFamily.body,
    fontWeight: FontWeight.w400,
    fontSize: 11.5,
  );

  // IBM Plex Mono — evidence: codes, hashes, tx, plates, timestamps -------

  /// The big session-pairing code (e.g. "K7M-4RQ2"). 600/34, tracked.
  static const TextStyle monoDisplay = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w600,
    fontSize: 34,
    letterSpacing: 3.4,
  );

  /// Split code-entry boxes. 600/24.
  static const TextStyle monoCodeInput = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w600,
    fontSize: 24,
  );

  /// Emphasized mono value (e.g. the plate field's own value). 600/20, tracked.
  static const TextStyle monoValueLarge = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w600,
    fontSize: 20,
    letterSpacing: 0.8,
  );

  /// Standard mono field value (plate, licence no., policy no.). 500/16.
  static const TextStyle monoValueMedium = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w500,
    fontSize: 16,
  );

  /// Inline mono value (tx hash inline, sealed-screen footer). 500/14.
  static const TextStyle monoValueSmall = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w500,
    fontSize: 14,
  );

  /// Table/row mono values (review rows, tx refs inside cards). 500/12.5.
  static const TextStyle monoValueTiny = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w500,
    fontSize: 12.5,
  );

  /// Timestamps and other mono meta text. 400/11.5.
  static const TextStyle monoMeta = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w400,
    fontSize: 11.5,
  );

  /// Uppercase eyebrow labels ("KORAK 2 / 8", "● UŽIVO", party labels).
  /// 400/10.5, tracked.
  static const TextStyle monoEyebrow = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w400,
    fontSize: 10.5,
    letterSpacing: 1.05,
  );

  /// Section/table header label ("VREME I MESTO"). 600/10, tracked.
  static const TextStyle monoLabel = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    letterSpacing: 1.2,
  );

  /// The smallest label — sits directly above a field's value ("IME I
  /// PREZIME"). 400/9.5, tracked.
  static const TextStyle monoFieldLabel = TextStyle(
    fontFamily: AppFontFamily.mono,
    fontWeight: FontWeight.w400,
    fontSize: 9.5,
    letterSpacing: 0.76,
  );

  // Caveat — decorative signature preview only -----------------------------

  /// Full-size signature preview (matches the signature-pad screen). 600/56.
  static const TextStyle signatureLarge = TextStyle(
    fontFamily: AppFontFamily.signature,
    fontWeight: FontWeight.w600,
    fontSize: 56,
  );

  /// Inline signature preview (e.g. "other party already signed" summary).
  /// 600/26.
  static const TextStyle signatureInline = TextStyle(
    fontFamily: AppFontFamily.signature,
    fontWeight: FontWeight.w600,
    fontSize: 26,
  );
}
