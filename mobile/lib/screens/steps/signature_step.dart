import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../../config/env.dart';
import '../../services/api_client.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../widgets/widgets.dart';

const _kPadSize = Size(600, 300);

/// Screen 11 (docs/master_plan.md §6) — the full-screen signature pad. Uses
/// the `signature` package's own canvas/undo-redo/export rather than a
/// hand-rolled CustomPainter like the sketch step: capturing one clean,
/// isolated stroke is exactly what that package is built for, and it
/// already ships clear/undo/redo. Export is fixed at [_kPadSize] regardless
/// of how much of the pad was actually inked, so every signature PNG has
/// the same full canvas — simpler for the eventual PDF layout (§5.6) than a
/// tightly-cropped image.
///
/// No `onNext` — this is the last step in the shell's own `IndexedStack`.
/// Once both parties have submitted, the server locks the report and emits
/// `report:locked` (`SessionController.isLocked`); `SessionShellScreen`
/// then swaps its whole body to `FinalizingScreen` (screen 12, Phase 10)
/// rather than advancing to another step here.
class SignatureStep extends StatefulWidget {
  const SignatureStep({super.key, required this.reportId});

  final String reportId;

  @override
  State<SignatureStep> createState() => _SignatureStepState();
}

class _SignatureStepState extends State<SignatureStep> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  late final SignatureController _controller;
  bool _submitting = false;
  double? _submitProgress;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 2.5,
      penColor: AppColors.navy,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_controller.isEmpty) {
      _showSnack('Nacrtajte potpis pre slanja.');
      return;
    }
    final selfParty = context.read<SessionController>().selfParty;
    setState(() {
      _submitting = true;
      _submitProgress = 0;
    });
    try {
      final bytes = await _controller.toPngBytes(
        width: _kPadSize.width.round(),
        height: _kPadSize.height.round(),
      );
      if (bytes == null) throw Exception('export failed');
      // The server broadcasts the stored {fileId, signedAt} back over
      // report:patched (see uploads.js's broadcastPatch), so `own.signature`
      // below updates itself once that round-trips — no manual local
      // state update needed here, same as every other patched field.
      await _api.uploadSignature(
        reportId: widget.reportId,
        bytes: bytes,
        party: selfParty,
        onProgress: (p) {
          if (mounted) setState(() => _submitProgress = p);
        },
      );
    } catch (_) {
      _showSnack('Potpis nije sačuvan. Proverite konekciju i pokušajte ponovo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final own = controller.report?.partyFor(controller.selfParty).signature;
    final other = controller.report?.partyFor(controller.otherParty).signature;
    final selfSigned = own?.fileId != null;
    final otherSigned = other?.fileId != null;
    final otherLabel = controller.otherParty == 'A' ? 'Vozač A' : 'Vozač B';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Potpisom potvrđujete tačnost unetih podataka. Kada oba vozača potpišu, izveštaj se automatski zaključava.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                StatusChip(
                  label: otherSigned ? '$otherLabel je potpisao' : '$otherLabel još nije potpisao',
                  variant: otherSigned ? AppStatusChipVariant.confirmed : AppStatusChipVariant.pending,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (selfSigned)
                  _SignedCard(signedAt: own?.signedAt)
                else
                  _SignaturePad(controller: _controller),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: selfSigned
              ? Text(
                  'Sačekajte da drugi vozač potpiše.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                )
              : AppButton(
                  label: _submitting
                      ? (_submitProgress != null ? 'Slanje… ${(_submitProgress! * 100).round()}%' : 'Slanje…')
                      : 'Pošalji potpis',
                  onPressed: _submitting ? null : _submit,
                ),
        ),
      ],
    );
  }
}

class _SignaturePad extends StatelessWidget {
  const _SignaturePad({required this.controller});

  final SignatureController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(label: 'Potpis'),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AspectRatio(
              aspectRatio: _kPadSize.width / _kPadSize.height,
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.borderDashed), color: AppColors.surfaceMuted),
                child: Signature(controller: controller, backgroundColor: Colors.transparent),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: _ToolButton(
                      label: 'Vrati',
                      icon: Icons.undo,
                      onTap: controller.canUndo ? controller.undo : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ToolButton(
                      label: 'Ponovi',
                      icon: Icons.redo,
                      onTap: controller.canRedo ? controller.redo : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ToolButton(
                      label: 'Obriši',
                      icon: Icons.delete_outline,
                      onTap: controller.isEmpty ? null : controller.clear,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppColors.navy : AppColors.textMuted;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: AppTypography.buttonLabel.copyWith(color: color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: enabled ? AppColors.navy : AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
        minimumSize: const Size(0, AppSpacing.minTapTarget - 12),
      ),
    );
  }
}

class _SignedCard extends StatelessWidget {
  const _SignedCard({required this.signedAt});

  final DateTime? signedAt;

  @override
  Widget build(BuildContext context) {
    final time = signedAt != null
        ? '${signedAt!.hour.toString().padLeft(2, '0')}:${signedAt!.minute.toString().padLeft(2, '0')}'
        : null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          StatusChip(
            label: time != null ? 'Potpisano · $time' : 'Potpisano',
            variant: AppStatusChipVariant.confirmed,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Vaš potpis je sačuvan i ne može se menjati.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
