import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A labeled field matching the design's card-like inputs: an uppercase mono
/// label sitting above a bordered value box (white bg, 1px border by
/// default). Reacts to four states — normal, focused (1.5px navy border,
/// as seen on the emphasized plate field), error (1.5px error border + a
/// message below), and disabled (muted bg/border/text) — since the design
/// itself only shows the normal and one emphasized/focused field; error and
/// disabled are derived from the shared status color tokens.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.monospace = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.onChanged,
    this.focusNode,
    this.readOnly = false,
    this.onTap,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final bool enabled;

  /// Use for code-like values (plate, licence number, policy number) that
  /// the design renders in IBM Plex Mono instead of IBM Plex Sans.
  final bool monospace;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  /// Supply an external node (e.g. PatchTextField) when the caller needs to
  /// check `hasFocus` itself — such as skipping a remote-value resync while
  /// the user is actively typing. Falls back to an internally owned node.
  final FocusNode? focusNode;

  /// Read-only + tappable (date/GPS pickers use this instead of a real
  /// keyboard field, but keep the same label/border/error treatment).
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = !widget.enabled
        ? AppColors.border
        : hasError
            ? AppColors.errorBorder
            : _focused
                ? AppColors.navy
                : AppColors.border;
    final borderWidth = (_focused || hasError) ? 1.5 : 1.0;
    final valueStyle = widget.monospace ? AppTypography.monoValueMedium : AppTypography.bodyLarge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: widget.enabled ? AppColors.surface : AppColors.surfaceAlt,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 3),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            maxLines: widget.maxLines,
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            onChanged: widget.onChanged,
            style: valueStyle.copyWith(
              color: widget.enabled ? AppColors.textPrimary : AppColors.textMuted,
            ),
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.hintText,
              hintStyle: valueStyle.copyWith(color: AppColors.textMuted),
            ),
          ),
        ),
        if (hasError || (widget.helperText?.isNotEmpty ?? false)) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            hasError ? widget.errorText! : widget.helperText!,
            style: AppTypography.caption.copyWith(
              color: hasError ? AppColors.errorText : AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
