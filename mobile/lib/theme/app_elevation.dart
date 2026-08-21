/// This design is intentionally flat: "Ivice sekcija: 1 px #CFCABD, bez
/// senki" (section edges: 1px border, no shadows). Depth is communicated
/// with a 1px AppColors.border/borderLight outline, never a box-shadow.
///
/// This constant exists so "no elevation" is a deliberate, documented choice
/// — widgets should reference AppElevation.flat instead of hardcoding 0.
class AppElevation {
  AppElevation._();

  static const double flat = 0;
}
