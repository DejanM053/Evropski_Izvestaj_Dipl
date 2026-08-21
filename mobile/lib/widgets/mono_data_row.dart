import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A label/value pair for evidence data (hashes, tx refs, report IDs,
/// timestamps). Two layouts, both seen repeatedly in the design:
/// - inline (default): label left, mono value right — review rows, the
///   history list's tx ref line.
/// - stacked: uppercase mono label above a full-width, wrapping mono value
///   — the verify screen's "HEŠ IZ DOKUMENTA" / "HEŠ IZ REGISTRA" blocks.
class MonoDataRow extends StatelessWidget {
  const MonoDataRow({
    super.key,
    required this.label,
    required this.value,
    this.stacked = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool stacked;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final valueStyle = AppTypography.monoValueTiny.copyWith(
      color: valueColor ?? AppColors.textPrimary,
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(value, style: valueStyle.copyWith(height: 1.5)),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            value,
            style: valueStyle,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
