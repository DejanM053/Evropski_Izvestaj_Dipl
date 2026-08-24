import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// A date (or date+time) picker styled as an [AppTextField]: read-only,
/// tappable, opens the platform date picker (and time picker when
/// [includeTime] is set). Used for `accident.dateTime`,
/// `driver.licenceValidUntil`, `insurer.validFrom`/`validTo` — none of
/// which the source design shows as an interactive control, so this
/// derives its look from the existing text-field tokens per §1.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.includeTime = false,
    this.errorText,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool includeTime;
  final String? errorText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  String _format(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    if (!includeTime) return d;
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 20),
      lastDate: lastDate ?? DateTime(now.year + 20),
    );
    if (date == null || !context.mounted) return;

    if (!includeTime) {
      onChanged(date);
      return;
    }

    final initialTime = value != null ? TimeOfDay.fromDateTime(value!) : TimeOfDay.fromDateTime(now);
    final time = await showTimePicker(context: context, initialTime: initialTime);
    if (!context.mounted) return;
    final combined = DateTime(date.year, date.month, date.day, time?.hour ?? 0, time?.minute ?? 0);
    onChanged(combined);
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: TextEditingController(text: value == null ? '' : _format(value!)),
      hintText: includeTime ? 'Dodirnite za datum i vreme' : 'Dodirnite za datum',
      errorText: errorText,
      readOnly: true,
      monospace: true,
      onTap: () => _pick(context),
    );
  }
}
