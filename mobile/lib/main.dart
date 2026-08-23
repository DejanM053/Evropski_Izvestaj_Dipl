import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/env.dart';
import 'screens/home_screen.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android target, portrait only (docs/master_plan.md §2).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AccidentReportApp());
}

class AccidentReportApp extends StatelessWidget {
  const AccidentReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evropski izveštaj',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Env.apiUrl.isEmpty ? const _MissingApiUrlScreen() : const HomeScreen(),
    );
  }
}

/// Shown instead of a silent hardcoded fallback when the app is launched
/// without `--dart-define=API_URL=...` (docs/master_plan.md §7) — a missing
/// API_URL should fail loudly, not connect to a guessed host.
class _MissingApiUrlScreen extends StatelessWidget {
  const _MissingApiUrlScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nedostaje API_URL', style: AppTypography.titleLarge.copyWith(color: AppColors.errorText)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pokrenite aplikaciju sa --dart-define=API_URL=http://<host>:3000',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
