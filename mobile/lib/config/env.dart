/// Build-time configuration. `apiUrl` is always supplied via
/// `--dart-define=API_URL=...` (docs/master_plan.md §7) — never hardcode a
/// fallback host here. An empty value is surfaced as a startup error by
/// `main.dart` instead, so a missing --dart-define fails loudly rather than
/// silently pointing at the wrong network.
class Env {
  Env._();

  static const String apiUrl = String.fromEnvironment('API_URL');
}
