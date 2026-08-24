import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// "Fill with test data" affordance on the Accident details and My details
/// steps — not part of the source design (a dev/demo convenience, not a
/// real report action), so styled off the `pending`/amber token family
/// instead of navy: it reads visually as a testing aid, distinct from the
/// real primary/secondary actions elsewhere on the same screen.
class FillSampleDataButton extends StatelessWidget {
  const FillSampleDataButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.pendingBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
        minimumSize: const Size(double.infinity, AppSpacing.minTapTarget - 12),
      ),
      child: Text(
        'Popuni test podacima',
        style: AppTypography.buttonLabel.copyWith(color: AppColors.pendingText),
      ),
    );
  }
}
