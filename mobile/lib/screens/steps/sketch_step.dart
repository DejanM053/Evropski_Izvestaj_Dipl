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

const _kCanvasSize = Size(320, 320);

/// Screen 8 (docs/master_plan.md §6) — the scene sketch: draggable/rotatable
/// car icons + an impact marker on a road outline, exported to PNG on save
/// (matches design "1g": grid background, crossing road strips, dashed
/// center lines, "SEVER ↑ · lat, lng" caption bottom-right). Freehand
/// drawing is layered on top as a bonus per the Phase 7 task brief ("if not
/// too complicated") — a pencil toggle switches the canvas gesture between
/// arranging icons and drawing strokes so the two don't fight over drags.
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
        _SketchItem(kind: _ItemKind.carA, position: const Offset(130, 110)),
        _SketchItem(kind: _ItemKind.carB, position: const Offset(190, 210)),
        _SketchItem(kind: _ItemKind.impact, position: const Offset(160, 160)),
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
    final accident = context.watch<SessionController>().report?.accident;
    final coords = accident?.location.lat != null && accident?.location.lng != null
        ? '${accident!.location.lat!.toStringAsFixed(4)}, ${accident.location.lng!.toStringAsFixed(4)}'
        : null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
                RepaintBoundary(
                  key: _repaintKey,
                  child: Container(
                    width: _kCanvasSize.width,
                    height: _kCanvasSize.height,
                    decoration: BoxDecoration(color: AppColors.surfaceMuted, border: Border.all(color: AppColors.border)),
                    child: ClipRect(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _drawMode ? (d) => setState(() => _strokes.add([d.localPosition])) : null,
                        onPanUpdate: _drawMode
                            ? (d) => setState(() => _strokes.isNotEmpty ? _strokes.last.add(d.localPosition) : null)
                            : null,
                        child: CustomPaint(
                          size: _kCanvasSize,
                          painter: _RoadPainter(coords: coords),
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

  void _handleRotateDrag(DragUpdateDetails details) {
    final box = canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    onRotate(box.globalToLocal(details.globalPosition));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: item.position.dx - _size.width / 2,
      top: item.position.dy - _size.height / 2,
      width: _size.width,
      height: _size.height,
      child: Transform.rotate(
        angle: item.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: interactive ? (d) => onDrag(d.delta) : null,
              child: _ItemIcon(kind: item.kind),
            ),
            if (interactive && item.kind != _ItemKind.impact)
              Positioned(
                left: _size.width / 2 + _handleOffset.dx - 8,
                top: _size.height / 2 + _handleOffset.dy - 8,
                child: GestureDetector(
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

/// The road-outline background (grid + crossing strips + dashed center
/// lines + "SEVER ↑" coordinate caption) from design "1g", drawn once as a
/// painter rather than nested Positioned/Container divs like the mockup's
/// own HTML — cheaper to repaint and it's what gets captured into the PNG
/// export alongside the draggable items.
class _RoadPainter extends CustomPainter {
  _RoadPainter({this.coords});

  final String? coords;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final roadPaint = Paint()..color = AppColors.illustrationRoad;
    final vStrip = Rect.fromLTWH(size.width * 0.36, 0, size.width * 0.28, size.height);
    final hStrip = Rect.fromLTWH(0, size.height * 0.38, size.width, size.height * 0.24);
    canvas.drawRect(vStrip, roadPaint);
    canvas.drawRect(hStrip, roadPaint);

    _drawDashedLine(canvas, Offset(vStrip.center.dx, 0), Offset(vStrip.center.dx, size.height));
    _drawDashedLine(canvas, Offset(0, hStrip.center.dy), Offset(size.width, hStrip.center.dy));

    final textPainter = TextPainter(
      text: TextSpan(
        text: coords != null ? 'SEVER ↑ · $coords' : 'SEVER ↑',
        style: AppTypography.monoMeta.copyWith(color: AppColors.textMuted, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 8, size.height - textPainter.height - 6));
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    final total = (end - start).distance;
    const dash = 14.0, gap = 14.0;
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
  bool shouldRepaint(covariant _RoadPainter oldDelegate) => oldDelegate.coords != coords;
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

  @override
  bool shouldRepaint(covariant _StrokesPainter oldDelegate) => oldDelegate.strokes != strokes;
}
