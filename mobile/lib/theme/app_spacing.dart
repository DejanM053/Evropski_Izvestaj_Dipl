/// Spacing scale from the design spec sheet: "Koraci: 4 / 8 / 12 / 16 / 24 / 32"
/// (steps: 4/8/12/16/24/32). Use these for every padding/gap/margin — no
/// magic numbers in screens or widgets. See .claude/rules/mobile.md.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// "Minimalni tap: 56 px (rukavice, jedna ruka)" — minimum touch target,
  /// chosen for one-handed / gloved roadside use. Applies to buttons and any
  /// other tappable control.
  static const double minTapTarget = 56;
}
