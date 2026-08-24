import 'dart:async';

import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// An [AppTextField] wired directly to one `report:patch` dot path
/// (docs/master_plan.md §5.3), used by the Phase 7 form screens
/// (`accident_details_step.dart`, `my_details_step.dart`).
///
/// Two jobs, both required by docs/master_plan.md §6 screen 6 and the
/// Phase 7 task brief:
/// - **Debounce**: keystrokes update the field instantly, but [onPatch]
///   (`SessionController.sendPatch`) only fires ~400ms after the user stops
///   typing, one independent [Timer] per field instance.
/// - **Don't clobber the field the user is editing**: when [remoteValue]
///   changes (a live `report:patched` from the other party, or our own
///   echoed-back patch arriving after we've already kept typing), the new
///   value is only pulled into the visible text if this field does *not*
///   currently have focus.
class PatchTextField extends StatefulWidget {
  const PatchTextField({
    super.key,
    required this.label,
    required this.path,
    required this.remoteValue,
    required this.onPatch,
    this.onChanged,
    this.hintText,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.monospace = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.debounce = const Duration(milliseconds: 400),
    this.transform,
  });

  final String label;

  /// Dot path patched, e.g. `partyA.vehicle.plate` or `accident.injuries`.
  final String path;

  /// The field's current value per the live report snapshot. Null/empty
  /// renders as an empty field.
  final String? remoteValue;

  /// `SessionController.sendPatch` (or an equivalent), called after the
  /// debounce settles with `transform`-ed value already applied.
  final void Function(String path, dynamic value) onPatch;

  /// Fired on every keystroke (before debounce), for callers that need to
  /// track local validation state as the user types.
  final ValueChanged<String>? onChanged;

  final String? hintText;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final bool monospace;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final Duration debounce;

  /// Applied to the typed value before it's sent as the patch value (e.g.
  /// uppercasing a plate) — the visible text itself is left as typed.
  final String Function(String value)? transform;

  @override
  State<PatchTextField> createState() => _PatchTextFieldState();
}

class _PatchTextFieldState extends State<PatchTextField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.remoteValue ?? '');
  }

  @override
  void didUpdateWidget(PatchTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final remote = widget.remoteValue ?? '';
    if (!_focusNode.hasFocus && remote != _controller.text) {
      _controller.value = TextEditingValue(text: remote);
    }
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () {
      final patched = widget.transform?.call(value) ?? value;
      widget.onPatch(widget.path, patched);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: _controller,
      focusNode: _focusNode,
      hintText: widget.hintText,
      errorText: widget.errorText,
      helperText: widget.helperText,
      enabled: widget.enabled,
      monospace: widget.monospace,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.maxLines,
      onChanged: _handleChanged,
    );
  }
}
