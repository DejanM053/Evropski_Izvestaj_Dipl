import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../config/env.dart';
import '../../services/api_client.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../widgets/widgets.dart';

enum _ItemKind { carA, carB, impact, marker }

class _SketchItem {
  _SketchItem({required this.kind, required this.position});

  final _ItemKind kind;
  Offset position;
  double rotation = 0;
}

// Fixed at a 2:1 ratio, matching the diagram box on the real European
// Accident Statement (not the screen's own size — see the AspectRatio +
// FittedBox wrapping in build(), which scales this fixed logical canvas to
// fit whatever width is available without ever changing its proportions or
// the coordinate space item positions/strokes are stored in). 12x6 grid
// cells fall out of this evenly (400/12 == 200/6).
const _kCanvasSize = Size(400, 200);
const _kGridColumns = 12;
const _kGridRows = 6;

/// Screen 8 (docs/master_plan.md §6) — the scene sketch: draggable/rotatable
/// car icons + an impact marker on a dotted-grid canvas, exported to PNG on
/// save. Freehand drawing is layered on top as a bonus per the Phase 7 task
/// brief ("if not too complicated") — a pencil toggle switches the canvas
/// gesture between arranging icons and drawing strokes so the two don't
/// fight over drags.
///
/// Only the session creator (party A) gets this interactive canvas — party B
/// sees a read-only view of whatever A has drawn (or a waiting placeholder
/// if A hasn't drawn yet). This is deliberate, not a missing feature: the
/// sketch only round-trips as a flattened PNG (there's no persisted
/// vector/structured state to load back into an editable canvas), so
/// whichever party reached this step *second* would otherwise silently
/// overwrite the first party's sketch with their own from-scratch blank
/// canvas the moment they saved — a real bug found during live testing (see
/// PROGRESS.md). Restricting editing to one deterministic party removes the
/// possibility entirely, and mirrors how the physical paper form actually
/// works: one person's pen touches the shared diagram box while both look
/// at it together, not two independent edits merged after the fact.
class SketchStep extends StatefulWidget {
  const SketchStep({super.key, required this.reportId, required this.onNext});

  final String reportId;
  final VoidCallback onNext;

  @override
  State<SketchStep> createState() => _SketchStepState();
}

class _SketchStepState extends State<SketchStep> {
  final _repaintKey = GlobalKey();
  final _api = ApiClient(baseUrl: Env.apiUrl);

  late List<_SketchItem> _items;
  final List<List<Offset>> _strokes = [];
  bool _drawMode = false;
  bool _saving = false;
  double? _saveProgress;

  @override
  void initState() {
    super.initState();
    _items = _defaultItems();
  }

  List<_SketchItem> _defaultItems() => [
        _SketchItem(kind: _ItemKind.carA, position: const Offset(150, 70)),
        _SketchItem(kind: _ItemKind.carB, position: const Offset(250, 130)),
        _SketchItem(kind: _ItemKind.impact, position: const Offset(200, 100)),
      ];

  void _reset() {
    setState(() {
      _items = _defaultItems();
      _strokes.clear();
    });
  }

  void _recenter(_ItemKind kind) {
    final existing = _items.where((i) => i.kind == kind).toList();
    if (existing.isEmpty) {
      setState(() => _items.add(_SketchItem(kind: kind, position: _kCanvasSize.center(Offset.zero))));
    } else {
      setState(() {
        for (final item in existing) {
          item
            ..position = _kCanvasSize.center(Offset.zero)
            ..rotation = 0;
        }
      });
    }
  }

  void _addMarker() {
    setState(() => _items.add(_SketchItem(kind: _ItemKind.marker, position: _kCanvasSize.center(Offset.zero))));
  }

  Offset _clampToCanvas(Offset offset) {
    return Offset(offset.dx.clamp(0, _kCanvasSize.width), offset.dy.clamp(0, _kCanvasSize.height));
  }

  void _onItemDrag(_SketchItem item, Offset delta) {
    setState(() => item.position = _clampToCanvas(item.position + delta));
  }

  // `canvasLocalPosition` is the drag pointer's position in the same
  // coordinate space as `item.position` (converted via the canvas
  // RenderBox in _DraggableSketchItem, since the handle itself sits inside
  // a Transform.rotate and its own onPanUpdate.localPosition would be in
  // that rotated frame, not the canvas's). Rotation is the angle swept from
  // the handle's rest position (top-right of the icon) to the drag point.
  void _onItemRotate(_SketchItem item, Offset canvasLocalPosition) {
    final vector = canvasLocalPosition - item.position;
    const restAngle = -math.pi / 4; // atan2(-24, 24), the handle's angle at rotation 0
    setState(() => item.rotation = math.atan2(vector.dy, vector.dx) - restAngle);
  }

  Future<Uint8List?> _exportPng() async {
    final boundary = _repaintKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveProgress = 0;
    });
    try {
      final bytes = await _exportPng();
      if (bytes == null) throw Exception('export failed');
      final result = await _api.uploadSketch(
        reportId: widget.reportId,
        bytes: bytes,
        onProgress: (p) => setState(() => _saveProgress = p),
      );
      if (!mounted) return;
      // Broadcasts the new sketch to the other party live: `sketch.fileId`
      // is an explicitly allowed shared patch path (.claude/rules/backend.md),
      // unlike `photos` — see PROGRESS.md for why photos can't do the same.
      context.read<SessionController>().sendPatch('sketch.fileId', result.fileId);
      widget.onNext();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skica nije sačuvana. Proverite konekciju i pokušajte ponovo.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final isDrawer = controller.selfParty == 'A';

    if (!isDrawer) {
      return _ReadOnlySketchView(sketchFileId: controller.report?.sketchFileId, onNext: widget.onNext);
    }

    final accident = controller.report?.accident;
    final coords = accident?.location.lat != null && accident?.location.lng != null
        ? '${accident!.location.lat!.toStringAsFixed(4)}, ${accident.location.lng!.toStringAsFixed(4)}'
        : null;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Postavite oba vozila i tačku udara. Skica se ne mora crtati rukom.',
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _drawMode = !_drawMode),
                      tooltip: _drawMode ? 'Prevlačenje ikonica' : 'Slobodno crtanje',
                      icon: Icon(
                        _drawMode ? Icons.pan_tool_outlined : Icons.edit_outlined,
                        color: AppColors.navy,
                      ),
                      isSelected: _drawMode,
                      style: IconButton.styleFrom(
                        backgroundColor: _drawMode ? AppColors.pendingBg : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Expanded + AspectRatio (rather than the scrollable layout
                // this step used to have) keeps the canvas fixed at exactly
                // 2:1 and responsive to available space, and — just as
                // importantly — means there's no ancestor Scrollable for the
                // canvas's own pan gesture to lose a gesture-arena contest
                // against on a touch device (that was the root cause of
                // "trying to draw just scrolls the page" on phones).
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _kCanvasSize.width / _kCanvasSize.height,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: Container(
                            width: _kCanvasSize.width,
                            height: _kCanvasSize.height,
                            decoration:
                                BoxDecoration(color: AppColors.surfaceMuted, border: Border.all(color: AppColors.border)),
                            child: ClipRect(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _drawMode ? (d) => setState(() => _strokes.add([d.localPosition])) : null,
                                onPanUpdate: _drawMode
                                    ? (d) => setState(() => _strokes.isNotEmpty ? _strokes.last.add(d.localPosition) : null)
                                    : null,
                                child: CustomPaint(
                                  size: _kCanvasSize,
                                  painter: _GridPainter(coords: coords),
                                  foregroundPainter: _StrokesPainter(_strokes),
                                  child: Stack(
                                    children: [
                                      for (final item in _items)
                                        _DraggableSketchItem(
                                          key: ObjectKey(item),
                                          item: item,
                                          interactive: !_drawMode,
                                          canvasKey: _repaintKey,
                                          onDrag: (delta) => _onItemDrag(item, delta),
                                          onRotate: (pos) => _onItemRotate(item, pos),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _ToolButton(label: 'Vozilo A', color: AppColors.navy, onTap: () => _recenter(_ItemKind.carA)),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(label: 'Vozilo B', color: AppColors.amber, onTap: () => _recenter(_ItemKind.carB)),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(label: 'Udar', color: AppColors.errorBorder, onTap: () => _recenter(_ItemKind.impact)),
                    const SizedBox(width: AppSpacing.sm),
                    _ToolButton(label: 'Znak', color: AppColors.textMuted, onTap: _addMarker),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Prevucite ikonicu da je pomerite, a ručku u uglu da je rotirate.',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
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
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Poništi',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : _reset,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: _saving
                      ? (_saveProgress != null ? 'Čuvanje… ${(_saveProgress! * 100).round()}%' : 'Čuvanje…')
                      : 'Sačuvaj skicu',
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What party B sees instead of the editable canvas — see the class doc on
/// [SketchStep] for why only party A draws. Purely reactive: `report` is
/// already live-synced via SessionController, so this switches from the
/// waiting placeholder to the actual image the moment party A saves, with
/// no polling.
class _ReadOnlySketchView extends StatelessWidget {
  const _ReadOnlySketchView({required this.sketchFileId, required this.onNext});

  final String? sketchFileId;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Vozač A crta skicu nezgode. Ovde ćete videti šta je nacrtano.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _kCanvasSize.width / _kCanvasSize.height,
                      child: sketchFileId == null
                          ? const _WaitingForSketchPlaceholder()
                          : Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Image.network(
                                '${Env.apiUrl}/api/files/$sketchFileId',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stack) =>
                                    const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
                              ),
                            ),
                    ),
                  ),
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
          child: AppButton(label: 'Dalje', onPressed: onNext),
        ),
      ],
    );
  }
}

class _WaitingForSketchPlaceholder extends StatelessWidget {
  const _WaitingForSketchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.pendingBg, border: Border.all(color: AppColors.pendingBorder)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, color: AppColors.pendingText),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vozač A još nije nacrtao skicu.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.pendingText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surface),
          child: Column(
            children: [
              Container(width: 16, height: 16, color: color),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraggableSketchItem extends StatelessWidget {
  const _DraggableSketchItem({
    super.key,
    required this.item,
    required this.interactive,
    required this.canvasKey,
    required this.onDrag,
    required this.onRotate,
  });

  final _SketchItem item;
  final bool interactive;

  /// Key of the canvas's RepaintBoundary — used to convert the rotate
  /// handle's drag position into canvas-local coordinates (its own
  /// `onPanUpdate.localPosition` is relative to the handle itself, which
  /// sits inside this item's `Transform.rotate` and so isn't in the same
  /// frame as `item.position`).
  final GlobalKey canvasKey;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onRotate;

  static const _size = Size(40, 40);
  static const _handleOffset = Offset(24, -24);

  // The outer hit-testable/layout box for this item — deliberately much
  // bigger than the icon itself (_size). A Positioned ancestor's hit-test
  // rejects any pointer position outside its own declared width/height
  // *before* it ever tries the children inside it (RenderBox.hitTest's
  // `size.contains(position)` check) — so when the old code sized this box
  // to exactly _size (40x40) and only *painted* the rotate handle outside
  // those bounds (via clipBehavior: Clip.none), the handle was visible but
  // not reliably tappable: most of its visible area sat outside the
  // hit-testable region. _boundsSize is sized to comfortably contain the
  // handle's full swept circle around the icon at any rotation angle
  // (icon center to handle-corner distance is ~45px at most), fixing the
  // "rotation handle doesn't work at all" bug rather than working around it.
  static const _boundsSize = Size(112, 112);

  void _handleRotateDrag(DragUpdateDetails details) {
    final box = canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    onRotate(box.globalToLocal(details.globalPosition));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: item.position.dx - _boundsSize.width / 2,
      top: item.position.dy - _boundsSize.height / 2,
      width: _boundsSize.width,
      height: _boundsSize.height,
      child: Transform.rotate(
        angle: item.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (_boundsSize.width - _size.width) / 2,
              top: (_boundsSize.height - _size.height) / 2,
              width: _size.width,
              height: _size.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: interactive ? (d) => onDrag(d.delta) : null,
                child: _ItemIcon(kind: item.kind),
              ),
            ),
            if (interactive && item.kind != _ItemKind.impact)
              Positioned(
                left: _boundsSize.width / 2 + _handleOffset.dx - 8,
                top: _boundsSize.height / 2 + _handleOffset.dy - 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _handleRotateDrag,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.navy, width: 1.5),
                    ),
                    child: const Icon(Icons.rotate_right, size: 10, color: AppColors.navy),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemIcon extends StatelessWidget {
  const _ItemIcon({required this.kind});

  final _ItemKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _ItemKind.carA:
        return _CarIcon(label: 'A', body: AppColors.navy, windshield: AppColors.onNavyMuted, border: null);
      case _ItemKind.carB:
        return _CarIcon(
          label: 'B',
          body: AppColors.amber,
          windshield: const Color(0xFFFAE3A8),
          border: AppColors.pendingText,
        );
      case _ItemKind.impact:
        return Center(
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 20, height: 20, color: AppColors.errorBorder),
          ),
        );
      case _ItemKind.marker:
        return Center(
          child: Container(
            width: 28,
            height: 5,
            decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
          ),
        );
    }
  }
}

class _CarIcon extends StatelessWidget {
  const _CarIcon({required this.label, required this.body, required this.windshield, required this.border});

  final String label;
  final Color body;
  final Color windshield;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 26,
        height: 38,
        decoration: BoxDecoration(
          color: body,
          borderRadius: BorderRadius.circular(5),
          border: border != null ? Border.all(color: border!, width: 1.5) : null,
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(width: 16, height: 12, decoration: BoxDecoration(color: windshield, borderRadius: BorderRadius.circular(2))),
            ),
            Positioned(
              bottom: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: body,
                child: Text(
                  label,
                  style: AppTypography.monoMeta.copyWith(
                    color: body == AppColors.amber ? AppColors.navy : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dotted 12x6 grid background + "SEVER ↑ · lat, lng" coordinate
/// caption. Used to draw a hardcoded crossroads (two solid road strips with
/// dashed center lines) on top of the grid — removed per user feedback:
/// a real accident scene is drawn freeform on a blank grid, not constrained
/// to a fixed intersection shape.
class _GridPainter extends CustomPainter {
  _GridPainter({this.coords});

  final String? coords;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1;
    final cellWidth = size.width / _kGridColumns;
    final cellHeight = size.height / _kGridRows;
    for (var col = 0; col <= _kGridColumns; col++) {
      final x = col * cellWidth;
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), gridPaint, dash: 3, gap: 3);
    }
    for (var row = 0; row <= _kGridRows; row++) {
      final y = row * cellHeight;
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), gridPaint, dash: 3, gap: 3);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: coords != null ? 'SEVER ↑ · $coords' : 'SEVER ↑',
        style: AppTypography.monoMeta.copyWith(color: AppColors.textMuted, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 8, size.height - textPainter.height - 6));
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, {required double dash, required double gap}) {
    final total = (end - start).distance;
    if (total == 0) return;
    var covered = 0.0;
    final direction = (end - start) / total;
    while (covered < total) {
      final segStart = start + direction * covered;
      final segEnd = start + direction * math.min(covered + dash, total);
      canvas.drawLine(segStart, segEnd, paint);
      covered += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.coords != coords;
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  // Always repaint rather than comparing `strokes` by identity: `_strokes`
  // is the same List instance mutated in place (.add) on every pointer
  // move, not reassigned, so an identity/equality check here always saw
  // "no change" and skipped repainting mid-stroke — strokes only appeared
  // once some *other* state change (like toggling draw mode off) forced a
  // full rebuild. This is what caused "drawings only become visible after
  // switching back to the hand tool."
  @override
  bool shouldRepaint(covariant _StrokesPainter oldDelegate) => true;
}
