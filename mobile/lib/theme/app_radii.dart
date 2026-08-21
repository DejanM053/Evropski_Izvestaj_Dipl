/// Border radii from the design spec sheet: "Radijus: 0 za polja i sekcije,
/// 3 za dugmad, 2 za oznake" (radius: 0 for fields/sections, 3 for buttons,
/// 2 for badges/tags). See .claude/rules/mobile.md.
class AppRadii {
  AppRadii._();

  /// Fields, cards, and sections are square.
  static const double none = 0;

  /// Buttons.
  static const double button = 3;

  /// Chips/badges/tags.
  static const double badge = 2;
}
