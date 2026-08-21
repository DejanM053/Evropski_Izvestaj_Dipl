import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One box in the circumstances checkbox grid (screen 1f): unchecked is a
/// white card with an outlined square and secondary-colored label; checked
/// inverts to a solid navy tile with an amber check mark and a white label.
class CircumstanceTile extends StatelessWidget {
  const CircumstanceTile({
    super.key,
    required this.label,
    required this.checked,
    this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md + 2),
        decoration: BoxDecoration(
          color: checked ? AppColors.navy : AppColors.surface,
          border: checked ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? AppColors.amber : AppColors.surfaceMuted,
                border: checked
                    ? null
                    : Border.all(color: AppColors.textPlaceholderBorder, width: 1.5),
              ),
              child: checked ? const Icon(Icons.check, size: 14, color: AppColors.navy) : null,
            ),
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: checked ? Colors.white : AppColors.textSecondary,
                fontWeight: checked ? FontWeight.w500 : FontWeight.w400,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
