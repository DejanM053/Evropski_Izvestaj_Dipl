import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The small uppercase label bar that titles a block inside a bordered card
/// ("VREME I MESTO", "STRANE", "OKOLNOSTI"). Meant to sit at the top of a
/// Container the caller borders themselves — this widget only draws the
/// header bar (alt-surface background, bottom border, mono label).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 1, vertical: AppSpacing.sm + 1),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.monoLabel.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
