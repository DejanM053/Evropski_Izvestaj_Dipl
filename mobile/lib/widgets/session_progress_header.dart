import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One party's slice of the session progress header: their label ("VI ·
/// VOZAČ A" / "DRUGI VOZAČ · B"), their current stage name, and how far
/// through the report they are (0..1).
class SessionPartyProgress {
  const SessionPartyProgress({
    required this.label,
    required this.stageLabel,
    required this.progress,
    required this.isSelf,
  });

  final String label;
  final String stageLabel;
  final double progress;
  final bool isSelf;
}

/// The persistent header (screen 1d) that wraps the shared-form screens:
/// session code + live indicator on top, then a two-column split showing
/// each party's current stage and progress bar. The self party is
/// highlighted in amber; the other party fades to the muted on-navy tokens.
class SessionProgressHeader extends StatelessWidget {
  const SessionProgressHeader({
    super.key,
    required this.sessionCode,
    required this.self,
    required this.other,
    this.isLive = true,
  });

  final String sessionCode;
  final SessionPartyProgress self;
  final SessionPartyProgress other;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md + 2, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Sesija $sessionCode', style: AppTypography.labelLarge.copyWith(color: Colors.white)),
              if (isLive)
                Text('● UŽIVO', style: AppTypography.monoEyebrow.copyWith(color: AppColors.amber)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _PartyPanel(party: self)),
              const SizedBox(width: 1),
              Expanded(child: _PartyPanel(party: other)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartyPanel extends StatelessWidget {
  const _PartyPanel({required this.party});

  final SessionPartyProgress party;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: party.isSelf ? AppColors.sessionSelfPanelBg : AppColors.sessionOtherPanelBg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            party.label,
            style: AppTypography.monoEyebrow.copyWith(
              fontSize: 10,
              color: party.isSelf ? AppColors.amber : AppColors.onNavyMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            party.stageLabel,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
              color: party.isSelf ? Colors.white : AppColors.onNavySecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 4,
            color: AppColors.navyTrack,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: party.progress.clamp(0, 1),
              child: Container(color: party.isSelf ? AppColors.amber : AppColors.onNavyMuted),
            ),
          ),
        ],
      ),
    );
  }
}
