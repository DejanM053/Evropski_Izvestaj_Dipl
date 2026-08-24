import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/env.dart';
import '../../models/report_model.dart';
import '../../services/api_client.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../widgets/widgets.dart';

class _PendingUpload {
  _PendingUpload({required this.id, required this.path});
  final String id;
  final String path;
  double progress = 0;
  String? error;
}

/// Screen 9 (docs/master_plan.md §6) — photo capture/pick with per-photo
/// captions, grid preview, delete-before-lock, immediate upload with
/// per-file progress. The task brief explicitly overrides the design "1h"
/// mockup's "5 OD MIN. 4 SNIMKA" (5 of min. 4 shots) framing — "make it so
/// photos are not necessary" — so there's no minimum-count gate here.
///
/// Uploaded photos are **not** live-broadcast to the other party (`photos`
/// is deliberately excluded from the generic `report:patch` mechanism —
/// see .claude/rules/backend.md and PROGRESS.md for why last-write-wins
/// replace would be unsafe for an additive list). Each party sees their own
/// uploads immediately (optimistic local state below); the other party
/// picks them up on their next `session:join` resync.
class PhotosStep extends StatefulWidget {
  const PhotosStep({super.key, required this.reportId, required this.onNext});

  final String reportId;
  final VoidCallback onNext;

  @override
  State<PhotosStep> createState() => _PhotosStepState();
}

class _PhotosStepState extends State<PhotosStep> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  final _picker = ImagePicker();
  final _captionController = TextEditingController();

  final List<_PendingUpload> _pending = [];
  final List<PhotoModel> _localOnlyPhotos = [];
  final Set<String> _deletedFileIds = {};
  int _nextPendingId = 0;

  // The photo just picked, waiting for the user to confirm/skip a caption
  // before upload starts. Rendered inline (see _CaptionPromptCard) instead
  // of via showDialog — image_picker hands off to a separate native
  // Activity (camera or gallery), and Android tears down/reattaches the
  // Flutter surface when that Activity closes and this one resumes.
  // Pushing a *new route* (a Dialog's Overlay entry) right as that
  // reattachment happens hit a real framework bug on physical devices —
  // "'_dependents.isEmpty': is not true" thrown from Element
  // unmount/deactivate — reproducible even with a settling delay before
  // showDialog, so the actual trigger is the route push itself, not
  // timing. Prompting inline, inside the already-mounted screen, never
  // creates a new route, which sidesteps the bug entirely.
  XFile? _awaitingCaption;

  List<PhotoModel> _mergedPhotos(List<PhotoModel> remote) {
    final remoteIds = remote.map((p) => p.fileId).toSet();
    return [
      ...remote.where((p) => !_deletedFileIds.contains(p.fileId)),
      ..._localOnlyPhotos.where((p) => !remoteIds.contains(p.fileId) && !_deletedFileIds.contains(p.fileId)),
    ];
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    _captionController.clear();
    setState(() => _awaitingCaption = file);
  }

  void _cancelCaptionPrompt() {
    setState(() => _awaitingCaption = null);
  }

  void _confirmCaptionPrompt() {
    final file = _awaitingCaption;
    if (file == null) return;
    setState(() => _awaitingCaption = null);
    _startUpload(file, _captionController.text);
  }

  Future<void> _startUpload(XFile file, String caption) async {
    final pending = _PendingUpload(id: (_nextPendingId++).toString(), path: file.path);
    final selfParty = context.read<SessionController>().selfParty;
    setState(() => _pending.add(pending));

    try {
      final result = await _api.uploadPhoto(
        reportId: widget.reportId,
        filePath: file.path,
        party: selfParty,
        caption: caption,
        onProgress: (p) {
          if (mounted) setState(() => pending.progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        _localOnlyPhotos.add(
          PhotoModel(fileId: result.fileId, caption: caption, party: selfParty, takenAt: DateTime.now()),
        );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => pending.error = e.message);
    }
  }

  Future<void> _confirmDelete(PhotoModel photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Obriši fotografiju?'),
        content: const Text('Ova radnja se ne može opozvati.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Otkaži')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Obriši')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.deletePhoto(reportId: widget.reportId, fileId: photo.fileId);
      if (!mounted) return;
      setState(() {
        _deletedFileIds.add(photo.fileId);
        _localOnlyPhotos.removeWhere((p) => p.fileId == photo.fileId);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final photos = _mergedPhotos(controller.report?.photos ?? const []);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Fotografije nisu obavezne, ali pomažu kod procene štete. Snimljene fotografije se odmah otpremaju.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                if (_awaitingCaption != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _CaptionPromptCard(
                    imagePath: _awaitingCaption!.path,
                    controller: _captionController,
                    onCancel: _cancelCaptionPrompt,
                    onConfirm: _confirmCaptionPrompt,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm + 2,
                  crossAxisSpacing: AppSpacing.sm + 2,
                  childAspectRatio: 0.86,
                  children: [
                    for (final photo in photos)
                      _PhotoCell(
                        photo: photo,
                        selfParty: controller.selfParty,
                        onDelete: () => _confirmDelete(photo),
                      ),
                    for (final pending in _pending) _PendingCell(pending: pending),
                    _AddPhotoCell(onTap: _showSourcePicker),
                  ],
                ),
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
          child: AppButton(label: 'Nastavi na pregled', onPressed: widget.onNext),
        ),
      ],
    );
  }

  Future<void> _showSourcePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.navy),
              title: const Text('Kamera'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.navy),
              title: const Text('Galerija'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickAndUpload(source);
  }
}

/// Inline (non-route) caption prompt shown after a photo is picked, before
/// upload starts — see the comment on `_awaitingCaption` for why this isn't
/// a showDialog. `controller` is owned by the parent State so its text
/// survives this card being rebuilt.
class _CaptionPromptCard extends StatelessWidget {
  const _CaptionPromptCard({
    required this.imagePath,
    required this.controller,
    required this.onCancel,
    required this.onConfirm,
  });

  final String imagePath;
  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surface),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRect(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.file(File(imagePath), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  label: 'Opis fotografije (opciono)',
                  controller: controller,
                  hintText: 'npr. Zadnji branik, ogrebotina',
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Otkaži', variant: AppButtonVariant.secondary, onPressed: onCancel),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppButton(label: 'Otpremi fotografiju', onPressed: onConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoCell extends StatelessWidget {
  const _PhotoCell({required this.photo, required this.selfParty, required this.onDelete});

  final PhotoModel photo;
  final String selfParty;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isSelf = photo.party == selfParty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surfaceAlt),
                child: ClipRect(
                  child: Image.network(
                    '${Env.apiUrl}/api/files/${photo.fileId}',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (context, error, stack) =>
                        const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
                  ),
                ),
              ),
              Positioned(
                top: 5,
                left: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: isSelf ? AppColors.amber : AppColors.cobalt,
                  child: Text(
                    '${photo.party ?? '?'} · ŠTETA',
                    style: AppTypography.monoMeta.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isSelf ? AppColors.navy : Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.close, size: 16),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                  tooltip: 'Obriši',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 1),
        Text(
          (photo.caption?.isNotEmpty ?? false) ? photo.caption! : 'Bez opisa',
          style: AppTypography.caption.copyWith(
            color: (photo.caption?.isNotEmpty ?? false) ? AppColors.textSecondary : AppColors.textMuted,
            fontStyle: (photo.caption?.isNotEmpty ?? false) ? FontStyle.normal : FontStyle.italic,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PendingCell extends StatelessWidget {
  const _PendingCell({required this.pending});

  final _PendingUpload pending;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
                child: ClipRect(child: Image.file(File(pending.path), fit: BoxFit.cover)),
              ),
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: pending.error != null
                      ? const Icon(Icons.error_outline, color: Colors.white)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.amber,
                                value: pending.progress > 0 ? pending.progress : null,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${(pending.progress * 100).round()}%',
                              style: AppTypography.caption.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 1),
        Text(
          pending.error ?? 'Otpremanje…',
          style: AppTypography.caption.copyWith(color: pending.error != null ? AppColors.errorText : AppColors.textMuted),
        ),
      ],
    );
  }
}

class _AddPhotoCell extends StatelessWidget {
  const _AddPhotoCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _DottedBorderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.navy, width: 2))),
              child: const Icon(Icons.add, size: 16, color: AppColors.navy),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Snimi / dodaj', style: AppTypography.buttonLabel.copyWith(color: AppColors.navy, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A dashed-border tile matching the design's "Snimi / dodaj" affordance
/// (`border: 1.5px dashed`) — `Border.all` has no dashed style in Flutter,
/// so this paints the dashes manually via [CustomPaint].
class _DottedBorderBox extends StatelessWidget {
  const _DottedBorderBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Container(color: AppColors.surfaceMuted, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0, gap = 4.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}
