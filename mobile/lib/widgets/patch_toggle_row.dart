import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A bordered label + switch row for the boolean fields on the Accident
/// details screen (injuries / other-vehicle-damage / third-party-damage —
/// docs/master_plan.md §5.1 `accident.*`). Not in the source design (no
/// screen shows a boolean toggle), so styled from the existing surface/
/// border/navy tokens per §1's "derive it from the existing tokens" rule,
/// matching the flat/square/1px-border language used everywhere else.
///
/// Unlike [PatchTextField], a toggle flip is a single discrete action —
/// there's nothing to debounce, so [onPatch] fires immediately.
class PatchToggleRow extends StatelessWidget {
  const PatchToggleRow({
    super.key,
    required this.label,
    required this.path,
    required this.value,
    required this.onPatch,
    this.helperText,
  });

  final String label;
  final String path;
  final bool value;
  final void Function(String path, dynamic value) onPatch;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary)),
                if (helperText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(helperText!, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: AppColors.navy,
            onChanged: (next) => onPatch(path, next),
          ),
        ],
      ),
    );
  }
}
