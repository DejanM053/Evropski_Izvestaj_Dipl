import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The three button treatments in the design: a solid navy primary action,
/// an outlined navy secondary action, and a solid error-red destructive
/// action. The design itself never shows a filled-red button — destructive
/// is derived from the error color tokens per docs/master_plan.md §1
/// ("derive it from the existing tokens rather than inventing new styling").
enum AppButtonVariant { primary, secondary, destructive }

/// Full-width, flat, sharp-cornered button matching the design's single
/// button shape (radius AppRadii.button, min height AppSpacing.minTapTarget).
/// Passing `onPressed: null` renders a disabled state derived from the same
/// tokens (the design has no explicit disabled button, either).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(variant, enabled: onPressed != null);

    return SizedBox(
      width: double.infinity,
      height: AppSpacing.minTapTarget,
      child: Material(
        color: colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          side: colors.border ?? BorderSide.none,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.button),
          child: Center(
            child: Text(
              label,
              style: AppTypography.buttonLabel.copyWith(color: colors.foreground),
            ),
          ),
        ),
      ),
    );
  }

  _ButtonColors _colorsFor(AppButtonVariant variant, {required bool enabled}) {
    if (!enabled) {
      final isOutlined = variant == AppButtonVariant.secondary;
      return _ButtonColors(
        background: isOutlined ? Colors.transparent : AppColors.border,
        foreground: AppColors.textMuted,
        border: isOutlined ? const BorderSide(color: AppColors.border, width: 1.5) : null,
      );
    }
    switch (variant) {
      case AppButtonVariant.primary:
        return const _ButtonColors(background: AppColors.navy, foreground: Colors.white);
      case AppButtonVariant.secondary:
        return const _ButtonColors(
          background: Colors.transparent,
          foreground: AppColors.navy,
          border: BorderSide(color: AppColors.navy, width: 1.5),
        );
      case AppButtonVariant.destructive:
        return const _ButtonColors(background: AppColors.errorBorder, foreground: Colors.white);
    }
  }
}

class _ButtonColors {
  const _ButtonColors({required this.background, required this.foreground, this.border});

  final Color background;
  final Color foreground;
  final BorderSide? border;
}
