import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'create_session_screen.dart';
import 'dev_gallery.dart';
import 'join_session_screen.dart';

/// Screen 1 (docs/master_plan.md §6) — new report / history / verify entry
/// points. History (screen 15) and Verify (screen 14) aren't built until
/// Phase 11, so their rows are present (matching the design 1:1) but inert
/// for now — tapping surfaces a snackbar instead of a dead navigation.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _notYetAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dostupno u kasnijoj fazi razvoja.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _HomeHeader(
              onDebugTap: kDebugMode
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DevGalleryScreen()),
                      )
                  : null,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NewReportCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateSessionScreen()),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _JoinSessionCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JoinSessionScreen()),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Divider(height: 1, color: AppColors.border),
                    _HomeListRow(
                      label: 'Istorija izveštaja',
                      trailing: '4',
                      onTap: () => _notYetAvailable(context),
                    ),
                    _HomeListRow(
                      label: 'Provera izveštaja',
                      trailing: '›',
                      onTap: () => _notYetAvailable(context),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _EmergencyNotice(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({this.onDebugTap});

  final VoidCallback? onDebugTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xl - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REPUBLIKA SRBIJA · OBRAZAC EI-2',
                  style: AppTypography.monoEyebrow.copyWith(color: AppColors.amber),
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                Text(
                  'Evropski izveštaj\no saobraćajnoj nezgodi',
                  style: AppTypography.displayLarge.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          if (onDebugTap != null)
            IconButton(
              tooltip: 'Component gallery (debug)',
              icon: const Icon(Icons.widgets_outlined, color: AppColors.onNavyMuted),
              onPressed: onDebugTap,
            ),
        ],
      ),
    );
  }
}

class _NewReportCard extends StatelessWidget {
  const _NewReportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Novi izveštaj', style: AppTypography.titleLarge.copyWith(color: Colors.white)),
              const SizedBox(height: AppSpacing.xs + 1),
              Text(
                'Vi pokrećete sesiju i pozivate drugog vozača da se pridruži.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.onNavySecondary, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinSessionCard extends StatelessWidget {
  const _JoinSessionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg - 1),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.navy, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pridruži se sesiji', style: AppTypography.titleMedium.copyWith(color: AppColors.navy)),
                  const SizedBox(height: AppSpacing.xs - 1),
                  Text(
                    'Skeniraj QR ili unesi šifru',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              Container(width: AppSpacing.sm, height: AppSpacing.sm, color: AppColors.amber),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeListRow extends StatelessWidget {
  const _HomeListRow({required this.label, required this.trailing, required this.onTap});

  final String label;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.buttonLabel.copyWith(color: AppColors.textPrimary)),
            Text(trailing, style: AppTypography.monoValueTiny.copyWith(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _EmergencyNotice extends StatelessWidget {
  const _EmergencyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
      decoration: const BoxDecoration(
        color: AppColors.pendingBg,
        border: Border(left: BorderSide(color: AppColors.pendingBorder, width: 4)),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTypography.bodySmall.copyWith(color: AppColors.pendingText, height: 1.5),
          children: [
            const TextSpan(text: 'Ako ima povređenih, prvo pozovite '),
            TextSpan(text: '194', style: AppTypography.monoMeta.copyWith(color: AppColors.pendingText)),
            const TextSpan(text: '. Ova aplikacija ne zamenjuje policijski uviđaj kod težih nezgoda.'),
          ],
        ),
      ),
    );
  }
}
