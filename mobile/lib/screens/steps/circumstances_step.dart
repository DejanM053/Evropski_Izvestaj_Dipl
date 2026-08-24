import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/circumstances.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../widgets/widgets.dart';

const _kInitiallyShown = 6;

/// Screen 7 (docs/master_plan.md §6) — the circumstances checkbox grid.
/// Matches design "1f" closely: 2-column [CircumstanceTile] grid, a live
/// "N označeno" count for the viewer's own party, a "show more" affordance
/// (6 shown, 11 more behind it — see `models/circumstances.dart`), and a
/// summary card of the other party's count (own-subtree circumstances are
/// still broadcast to the whole room per .claude/rules/backend.md, so this
/// updates live).
class CircumstancesStep extends StatefulWidget {
  const CircumstancesStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<CircumstancesStep> createState() => _CircumstancesStepState();
}

class _CircumstancesStepState extends State<CircumstancesStep> {
  bool _expanded = false;

  void _toggle(String party, Set<int> current, int index) {
    final next = Set<int>.from(current);
    if (!next.add(index)) next.remove(index);
    final sorted = next.toList()..sort();
    context.read<SessionController>().sendPatch('$party.circumstances', sorted);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final party = controller.selfParty == 'A' ? 'partyA' : 'partyB';
    final own = controller.report?.partyFor(controller.selfParty);
    final other = controller.report?.partyFor(controller.otherParty);
    final checked = (own?.circumstances ?? const []).toSet();
    final otherCount = other?.circumstances.length ?? 0;

    final visibleCount = _expanded ? kCircumstances.length : _kInitiallyShown;
    final selfLabel = controller.selfParty == 'A' ? 'VI · VOZAČ A' : 'VI · VOZAČ B';
    final otherLabel = controller.otherParty == 'A' ? 'VOZAČ A' : 'VOZAČ B';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(selfLabel, style: AppTypography.monoLabel.copyWith(color: AppColors.textMuted)),
                    Text(
                      '${checked.length} označeno',
                      style: AppTypography.monoValueTiny.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                // Built as manual paired rows rather than a GridView with a
                // fixed childAspectRatio: a fixed aspect ratio caps each
                // tile's height regardless of how much text it holds, which
                // clipped the longer circumstance labels under Android's
                // font metrics (fine under Chrome's, since text there
                // measured slightly narrower — device-dependent, not a
                // width/breakpoint issue). Pairing tiles in a plain Row lets
                // each row grow to fit its own tallest tile's wrapped text.
                // Deliberately NOT `crossAxisAlignment: stretch` — combined
                // with this Row sitting inside a SingleChildScrollView's
                // unbounded-height Column, stretch triggered a real Flutter
                // layout bug ("Cannot hit test a render box that has never
                // been laid out", surfaced via mouse-hover tracking on web)
                // where the Row was left NEEDS-LAYOUT with no size. Each
                // tile just sizes to its own content now; the two tiles in
                // a row occasionally differ in height, which is a fine
                // trade for not crashing.
                for (var i = 0; i < visibleCount; i += 2)
                  Padding(
                    padding: EdgeInsets.only(bottom: i + 2 < visibleCount ? AppSpacing.sm : 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CircumstanceTile(
                            label: kCircumstances[i],
                            checked: checked.contains(i),
                            onTap: () => _toggle(party, checked, i),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: i + 1 < visibleCount
                              ? CircumstanceTile(
                                  label: kCircumstances[i + 1],
                                  checked: checked.contains(i + 1),
                                  onTap: () => _toggle(party, checked, i + 1),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                if (!_expanded && kCircumstances.length > _kInitiallyShown)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: InkWell(
                      onTap: () => setState(() => _expanded = true),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Prikaži još ${kCircumstances.length - _kInitiallyShown} okolnosti',
                            style: AppTypography.buttonLabel.copyWith(color: AppColors.navy),
                          ),
                          Text('▾', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.zero,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md + 2),
                  child: Row(
                    children: [
                      Container(width: 4, height: 32, color: AppColors.onNavyMuted),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$otherLabel ZA SEBE OZNAČIO',
                              style: AppTypography.monoMeta.copyWith(color: AppColors.textMuted),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '$otherCount okolnosti · vidljivo u pregledu pre potpisa',
                              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
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
          child: AppButton(label: 'Potvrdi ${checked.length} okolnosti', onPressed: widget.onNext),
        ),
      ],
    );
  }
}
