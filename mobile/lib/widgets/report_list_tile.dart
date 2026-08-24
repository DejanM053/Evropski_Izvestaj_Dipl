import 'package:flutter/material.dart';

import '../models/report_model.dart';
import '../theme/theme.dart';
import 'status_chip.dart';

/// One row in the report history / verify-picker lists (screens 14/15).
/// No source mockup exists for this exact row (screens 14/15 weren't part
/// of the imported design set — see .claude/rules/mobile.md), so this is
/// derived from the same section/token pattern used elsewhere (e.g.
/// ReportCompleteScreen's party-label formatting) rather than copied from a
/// screen. "Other party" is shown as both drivers rather than guessing
/// which one is "self": a device's local deviceId isn't tied to a fixed
/// party slot — it can be A in one report and B in another.
class ReportListTile extends StatelessWidget {
  const ReportListTile({super.key, required this.report, required this.onTap});

  final ReportModel report;
  final VoidCallback onTap;

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}.';
  }

  String _driverLabel(PartyReportModel party, String fallback) {
    final name = [party.driver.firstName, party.driver.lastName].where((s) => s != null && s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : fallback;
  }

  AppStatusChipVariant _chipVariantFor(String status) {
    if (status == 'sealed') return AppStatusChipVariant.confirmed;
    return AppStatusChipVariant.pending;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'sealed':
        return 'Zapečaćen';
      case 'signing':
      case 'finalizing':
        return 'U obradi';
      case 'abandoned':
        return 'Napušten';
      default:
        return 'U toku';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateA = report.partyA.vehicle.plate;
    final plateB = report.partyB.vehicle.plate;
    final plates = [plateA, plateB].where((p) => p != null && p.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.md + 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderLight))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_driverLabel(report.partyA, 'Vozač A')} ↔ ${_driverLabel(report.partyB, 'Vozač B')}',
                    style: AppTypography.itemTitle.copyWith(color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${_fmtDate(report.sealedAt ?? report.createdAt)}${plates.isNotEmpty ? ' · $plates' : ''}',
                    style: AppTypography.monoMeta.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(label: _statusLabel(report.status), variant: _chipVariantFor(report.status)),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
