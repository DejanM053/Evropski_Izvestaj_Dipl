import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The tinted-background / colored-left-border tag shown in the design's own
/// component spec sheet ("Potvrđeno · 14:12"). `confirmed` and `verified`
/// share the success color family — the source design never visually
/// distinguishes "a party confirmed review" from "the hash check passed",
/// so callers separate them by label/context rather than color.
enum AppStatusChipVariant { pending, confirmed, verified, tampered }

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.variant});

  final String label;
  final AppStatusChipVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(variant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.accent, width: 4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: colors.accent),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _ChipColors _colorsFor(AppStatusChipVariant variant) {
    switch (variant) {
      case AppStatusChipVariant.pending:
        return const _ChipColors(
          background: AppColors.pendingBg,
          accent: AppColors.pendingBorder,
          text: AppColors.pendingText,
        );
      case AppStatusChipVariant.confirmed:
      case AppStatusChipVariant.verified:
        return const _ChipColors(
          background: AppColors.successBg,
          accent: AppColors.successBorder,
          text: AppColors.successText,
        );
      case AppStatusChipVariant.tampered:
        return const _ChipColors(
          background: AppColors.errorBg,
          accent: AppColors.errorBorder,
          text: AppColors.errorText,
        );
    }
  }
}

class _ChipColors {
  const _ChipColors({required this.background, required this.accent, required this.text});

  final Color background;
  final Color accent;
  final Color text;
}
