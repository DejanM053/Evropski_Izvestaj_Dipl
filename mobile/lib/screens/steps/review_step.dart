import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/env.dart';
import '../../models/circumstances.dart';
import '../../models/report_model.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../widgets/widgets.dart';

/// Screen 10 (docs/master_plan.md §6) — the full assembled report from both
/// sides, read-only, ending in the explicit "I confirm this is accurate"
/// action that sets `partyX.confirmedReview`. Reuses the generic
/// `report:patch` mechanism for that (own-subtree, already allowed per
/// .claude/rules/backend.md) rather than a dedicated endpoint — the same
/// broadcast that carries it back also gives the other party's
/// confirmation state live, with no extra plumbing.
///
/// Forward navigation to this step (and from here to Signature) only ever
/// happens via each screen's own "next" button, so a party can only reach
/// this screen after their own half is filled — no separate gate needed
/// here for "is my data complete".
class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.onNext});

  final VoidCallback onNext;

  void _confirm(BuildContext context) {
    final controller = context.read<SessionController>();
    final partyKey = controller.selfParty == 'A' ? 'partyA' : 'partyB';
    controller.sendPatch('$partyKey.confirmedReview', true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final report = controller.report;
    final accident = report?.accident ?? const AccidentModel();
    final own = report?.partyFor(controller.selfParty) ?? const PartyReportModel();
    final other = report?.partyFor(controller.otherParty) ?? const PartyReportModel();
    final selfLabel = controller.selfParty == 'A' ? 'Vozač A (vi)' : 'Vozač B (vi)';
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
                  'Proverite ceo izveštaj pre potpisivanja. Podaci ostaju otključani za izmenu dok oba vozača ne potpišu.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                _AccidentReviewCard(accident: accident),
                const SizedBox(height: AppSpacing.lg),
                _PartyReviewCard(label: selfLabel, party: own),
                const SizedBox(height: AppSpacing.lg),
                _PartyReviewCard(label: otherLabel, party: other),
                const SizedBox(height: AppSpacing.lg),
                _SketchReviewCard(fileId: report?.sketchFileId),
                const SizedBox(height: AppSpacing.lg),
                _PhotosReviewCard(photos: report?.photos ?? const []),
                const SizedBox(height: AppSpacing.lg),
                _ConfirmationCard(
                  selfLabel: selfLabel,
                  otherLabel: otherLabel,
                  selfConfirmed: own.confirmedReview,
                  otherConfirmed: other.confirmedReview,
                  onConfirm: own.confirmedReview ? null : () => _confirm(context),
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
          child: AppButton(
            label: 'Nastavi na potpisivanje',
            onPressed: own.confirmedReview ? onNext : null,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(label: title),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

String _dash(String? value) => (value != null && value.isNotEmpty) ? value : '—';

class _AccidentReviewCard extends StatelessWidget {
  const _AccidentReviewCard({required this.accident});

  final AccidentModel accident;

  @override
  Widget build(BuildContext context) {
    final dt = accident.dateTime;
    final dateLabel = dt == null
        ? '—'
        : '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}. '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return _Card(
      title: 'Nezgoda',
      children: [
        MonoDataRow(label: 'Datum i vreme', value: dateLabel),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Mesto', value: _dash(accident.location.address)),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Ima povređenih', value: accident.injuries ? 'Da' : 'Ne'),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Oštećena druga vozila', value: accident.otherVehicleDamage ? 'Da' : 'Ne'),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Oštećena imovina trećih lica', value: accident.thirdPartyDamage ? 'Da' : 'Ne'),
        if (accident.witnesses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Svedoci', style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted)),
          for (final w in accident.witnesses)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
              child: MonoDataRow(label: _dash(w.name), value: _dash(w.phone)),
            ),
        ],
      ],
    );
  }
}

class _PartyReviewCard extends StatelessWidget {
  const _PartyReviewCard({required this.label, required this.party});

  final String label;
  final PartyReportModel party;

  @override
  Widget build(BuildContext context) {
    final fullName = [party.driver.firstName, party.driver.lastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final vehicleLine =
        [party.vehicle.make, party.vehicle.model].where((s) => s != null && s.isNotEmpty).join(' ');
    final circumstanceLabels = party.circumstances
        .where((i) => i >= 0 && i < kCircumstances.length)
        .map((i) => kCircumstances[i])
        .toList();

    return _Card(
      title: label,
      children: [
        MonoDataRow(label: 'Vozač', value: fullName.isEmpty ? '—' : fullName),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Telefon', value: _dash(party.driver.phone)),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Vozilo', value: vehicleLine.isEmpty ? '—' : vehicleLine),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Reg. tablica', value: _dash(party.vehicle.plate)),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Osiguravač', value: _dash(party.insurer.company)),
        const SizedBox(height: AppSpacing.sm),
        MonoDataRow(label: 'Broj polise', value: _dash(party.insurer.policyNumber)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Okolnosti (${circumstanceLabels.length})',
          style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted),
        ),
        if (circumstanceLabels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
            child: Text(
              'Nema označenih okolnosti.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          )
        else
          for (final label in circumstanceLabels)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(width: 4, height: 4, color: AppColors.navy),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))),
                ],
              ),
            ),
        if (party.visibleDamage.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Vidljiva oštećenja', style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          Text(party.visibleDamage, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
        if (party.remarks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Napomene', style: AppTypography.monoFieldLabel.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          Text(party.remarks, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

class _SketchReviewCard extends StatelessWidget {
  const _SketchReviewCard({required this.fileId});

  final String? fileId;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Skica',
      children: [
        if (fileId == null)
          Text('Skica nije dodata.', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted))
        else
          AspectRatio(
            aspectRatio: 2,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surfaceMuted),
              child: Image.network(
                '${Env.apiUrl}/api/files/$fileId',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotosReviewCard extends StatelessWidget {
  const _PhotosReviewCard({required this.photos});

  final List<PhotoModel> photos;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Fotografije (${photos.length})',
      children: [
        if (photos.isEmpty)
          Text('Nema dodatih fotografija.', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted))
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1,
            children: [
              for (final photo in photos)
                ClipRect(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), color: AppColors.surfaceAlt),
                    child: Image.network(
                      '${Env.apiUrl}/api/files/${photo.fileId}',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.selfLabel,
    required this.otherLabel,
    required this.selfConfirmed,
    required this.otherConfirmed,
    required this.onConfirm,
  });

  final String selfLabel;
  final String otherLabel;
  final bool selfConfirmed;
  final bool otherConfirmed;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Potvrda pregleda',
      children: [
        Row(
          children: [
            Expanded(child: Text(selfLabel, style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary))),
            StatusChip(
              label: selfConfirmed ? 'Potvrđeno' : 'Na čekanju',
              variant: selfConfirmed ? AppStatusChipVariant.confirmed : AppStatusChipVariant.pending,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: Text(otherLabel, style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary))),
            StatusChip(
              label: otherConfirmed ? 'Potvrđeno' : 'Na čekanju',
              variant: otherConfirmed ? AppStatusChipVariant.confirmed : AppStatusChipVariant.pending,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (onConfirm != null)
          AppButton(label: 'Potvrđujem da su podaci tačni', onPressed: onConfirm)
        else
          Text(
            'Potvrdili ste tačnost podataka.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
      ],
    );
  }
}
