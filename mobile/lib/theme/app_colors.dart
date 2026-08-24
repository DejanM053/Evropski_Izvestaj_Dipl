import 'package:flutter/widgets.dart';

/// Color tokens extracted from the Claude Design source
/// (`Accident Report App.dc.html`'s "BOJE" spec sheet plus a screen-by-screen
/// pass over all 16 mockups). Every color the app uses must come from here —
/// no inline hex values in screens or widgets. See .claude/rules/mobile.md.
class AppColors {
  AppColors._();

  // Brand
  static const navy = Color(0xFF12274A);
  static const cobalt = Color(0xFF1B3A6B);
  static const amber = Color(0xFFF0B323);

  // Neutrals — paper-form surface hierarchy
  static const paper = Color(0xFFEAE7DF); // scaffold background
  static const surface = Color(0xFFFFFFFF); // cards, inputs
  static const surfaceAlt = Color(0xFFF2F0EA); // table/section headers, disabled rows
  static const surfaceMuted = Color(0xFFFAF8F3); // sketch canvas, empty-state panel
  static const border = Color(0xFFCFCABD); // default 1px section/field border
  static const borderLight = Color(0xFFE3DFD4); // divider inside a card
  static const borderDashed = Color(0xFFBDB8AA); // empty-state dashed border

  // Text (on paper/surface backgrounds)
  static const textPrimary = Color(0xFF171A1F);
  static const textSecondary = Color(0xFF3A3F49);
  static const textMuted = Color(0xFF5C6270);
  static const textPlaceholderBorder = Color(0xFF9A9484); // unchecked checkbox border

  // Text/content on navy backgrounds
  static const onNavyPrimary = Color(0xFFFFFFFF);
  static const onNavySecondary = Color(0xFFB9C6DC);
  static const onNavyMuted = Color(0xFF8FA5C6);
  static const onNavyFaint = Color(0xFF5A6F94); // pending-step label on navy (finalizing screen)
  static const onNavyFaintTitle = Color(0xFF6E85AC); // pending-step title on navy
  static const navyTrack = Color(0xFF0D1D38); // progress-bar track on navy
  static const navyBorder = Color(0xFF2A4A80); // borders/dividers on navy

  // Session progress header — the two party panels are distinct navy shades
  static const sessionSelfPanelBg = cobalt; // 0xFF1B3A6B
  static const sessionOtherPanelBg = Color(0xFF16305A);

  // Status — success (confirmed / verified share one family; see status_chip.dart)
  static const successBg = Color(0xFFE3EDE5);
  static const successBorder = Color(0xFF2E6B4F);
  static const successText = Color(0xFF1F5039);
  static const successOnDark = Color(0xFFCDE3D6);

  // Status — pending
  static const pendingBg = Color(0xFFF5EFDC);
  static const pendingBorder = Color(0xFFF0B323);
  static const pendingText = Color(0xFFA87A08);

  // Status — error / tampered
  static const errorBg = Color(0xFFF7E7E4);
  static const errorBorder = Color(0xFFA6322A);
  static const errorText = Color(0xFF8A2A22);
  static const errorTextAlt = Color(0xFF6E332C);
  static const errorOnDark = Color(0xFFF3D5D1);
  static const errorHighlightBg = Color(0xFFF7D8D3); // tampered hash-diff highlight
  static const successHighlightBg = successBg; // matching hash-diff highlight

  // Illustration-only (sketch canvas, photo placeholders, QR scanner) — kept
  // as tokens so Phase 7's sketch/photos screens don't need to inline hex.
  static const illustrationStripeA = Color(0xFFD6D2C6);
  static const illustrationStripeB = Color(0xFFE6E2D8);
  static const scannerBg = Color(0xFF22262E);
  static const scannerStripe = Color(0xFF2A2F38);
  static const scannerDarkBg = Color(0xFF171A1F);
}
