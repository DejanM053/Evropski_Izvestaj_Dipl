import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/socket_client.dart';
import '../state/session_controller.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'steps/accident_details_step.dart';
import 'steps/circumstances_step.dart';
import 'steps/my_details_step.dart';
import 'steps/photos_step.dart';
import 'steps/review_step.dart';
import 'steps/signature_step.dart';
import 'steps/sketch_step.dart';

/// Screen 4 (docs/master_plan.md §6) — the persistent session shell: both
/// parties' live connection/progress header, wrapping the full step flow
/// (screens 5-11: accident details, my details, circumstances, sketch,
/// photos, review, signature).
class SessionShellScreen extends StatelessWidget {
  const SessionShellScreen({
    super.key,
    required this.sessionId,
    required this.sessionCode,
    required this.reportId,
    required this.selfParty,
  });

  final String sessionId;
  final String sessionCode;
  final String reportId;

  /// `'A'` or `'B'`.
  final String selfParty;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionController(
        baseUrl: Env.apiUrl,
        sessionId: sessionId,
        sessionCode: sessionCode,
        selfParty: selfParty,
      ),
      child: _SessionShellBody(reportId: reportId),
    );
  }
}

/// One entry per step screen (5-11). `key` is broadcast as the socket
/// `party:ready` `stage` value (an opaque display string per
/// .claude/rules/backend.md — the other party's client re-derives its own
/// label/progress from this list, it never persisted-parses server state),
/// so both clients must share this exact list/order.
class _StepInfo {
  const _StepInfo(this.key, this.title);
  final String key;
  final String title;
}

const _kSteps = [
  _StepInfo('accident', 'Nezgoda'),
  _StepInfo('details', 'Moji podaci'),
  _StepInfo('circumstances', 'Okolnosti'),
  _StepInfo('sketch', 'Skica'),
  _StepInfo('photos', 'Fotografije'),
  _StepInfo('review', 'Pregled'),
  _StepInfo('signature', 'Potpis'),
];

const _kReviewStepIndex = 5;

/// Step 1/8 is session pairing (screens 1-4, already behind us by the time
/// the shell mounts) — the flow here picks up at step 2/8.
const _kFirstGlobalStep = 2;
const _kTotalSteps = 8;

String _stageLabelFor(String key) {
  final index = _kSteps.indexWhere((s) => s.key == key);
  if (index == -1) return key;
  return 'Korak ${index + _kFirstGlobalStep}/$_kTotalSteps · ${_kSteps[index].title}';
}

double _progressFor(String key) {
  final index = _kSteps.indexWhere((s) => s.key == key);
  if (index == -1) return 0;
  return (index + _kFirstGlobalStep) / _kTotalSteps;
}

class _SessionShellBody extends StatefulWidget {
  const _SessionShellBody({required this.reportId});

  final String reportId;

  @override
  State<_SessionShellBody> createState() => _SessionShellBodyState();
}

class _SessionShellBodyState extends State<_SessionShellBody> {
  SessionErrorEvent? _shownError;
  int _stepIndex = 0;
  bool _lockJumpDone = false;

  @override
  void initState() {
    super.initState();
    context.read<SessionController>().addListener(_maybeShowError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceStep());
  }

  void _announceStep() {
    if (!mounted) return;
    context.read<SessionController>().sendReady(_kSteps[_stepIndex].key);
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _kSteps.length) return;
    setState(() => _stepIndex = index);
    _announceStep();
  }

  // Once the report locks (Phase 8: both parties confirmed + signed), jump
  // once to the Review step if the viewer is sitting on an earlier one
  // (e.g. they went back to re-check something while the other party
  // finished signing) — otherwise every earlier step's own "next" button
  // becomes unreachable under the read-only overlay below, with no other
  // way forward. Only fires once per shell lifetime so it doesn't fight a
  // deliberate back-navigation afterward.
  void _maybeJumpToReviewOnLock(bool isLocked) {
    if (!isLocked || _lockJumpDone || _stepIndex >= _kReviewStepIndex) return;
    _lockJumpDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToStep(_kReviewStepIndex));
  }

  void _maybeShowError() {
    final error = context.read<SessionController>().lastError;
    if (error == null || identical(error, _shownError)) return;
    _shownError = error;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }

  @override
  void dispose() {
    context.read<SessionController>().removeListener(_maybeShowError);
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Napusti sesiju?'),
        content: const Text('Sesija ostaje otvorena za drugog vozača dok ne istekne.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Otkaži')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Napusti')),
        ],
      ),
    );
    if (leave == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _handleBack() {
    if (_stepIndex == 0) {
      _confirmLeave();
    } else {
      _goToStep(_stepIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final connected = controller.connectionState == SocketConnectionState.connected;
    final selfLabel = controller.selfParty == 'A' ? 'VI · VOZAČ A' : 'VI · VOZAČ B';
    final otherLabel = controller.selfParty == 'A' ? 'DRUGI VOZAČ · B' : 'DRUGI VOZAČ · A';
    final otherStage = controller.otherPartyStage;
    final isLocked = controller.isLocked;
    _maybeJumpToReviewOnLock(isLocked);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            SessionProgressHeader(
              sessionCode: controller.sessionCode,
              isLive: connected,
              self: SessionPartyProgress(
                label: selfLabel,
                stageLabel: connected ? _stageLabelFor(_kSteps[_stepIndex].key) : 'Povezivanje…',
                progress: connected ? _progressFor(_kSteps[_stepIndex].key) : 0,
                isSelf: true,
              ),
              other: SessionPartyProgress(
                label: otherLabel,
                stageLabel: otherStage != null
                    ? _stageLabelFor(otherStage)
                    : (controller.otherPartyConnected ? 'Povezan' : 'Čeka se povezivanje…'),
                progress: otherStage != null ? _progressFor(otherStage) : 0,
                isSelf: false,
              ),
            ),
            if (isLocked) const _LockedBanner(),
            if (!connected) const _ReconnectingBanner(),
            _StepHeaderBar(
              title: _kSteps[_stepIndex].title,
              stepLabel: 'KORAK ${_stepIndex + _kFirstGlobalStep} / $_kTotalSteps',
              onBack: _handleBack,
            ),
            Expanded(
              // §6 client rules: "block all edit affordances when status ≥
              // signing" — a single overlay here (rather than threading
              // `enabled`/`isLocked` through every field on every step)
              // covers all of them at once, including screens the user
              // might navigate back to. Dimmed to signal read-only, not
              // hidden, since the data itself is still exactly what's on
              // the (now locked) Review screen.
              child: IgnorePointer(
                ignoring: isLocked,
                child: Opacity(
                  opacity: isLocked ? 0.6 : 1,
                  child: IndexedStack(
                    index: _stepIndex,
                    children: [
                      AccidentDetailsStep(onNext: () => _goToStep(1)),
                      MyDetailsStep(onNext: () => _goToStep(2)),
                      CircumstancesStep(onNext: () => _goToStep(3)),
                      SketchStep(reportId: widget.reportId, onNext: () => _goToStep(4)),
                      PhotosStep(reportId: widget.reportId, onNext: () => _goToStep(5)),
                      ReviewStep(onNext: () => _goToStep(6)),
                      SignatureStep(reportId: widget.reportId),
                    ],
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

/// Lightweight step wayfinding row (title + "KORAK X/8" + back arrow) below
/// the heavy navy [SessionProgressHeader] — not a second navy block, since
/// the header above already carries that weight; a plain surface bar keeps
/// the two from visually competing while still surfacing per-screen step
/// info the way each design mockup's own header did (screens "1e"-"1h").
class _StepHeaderBar extends StatelessWidget {
  const _StepHeaderBar({required this.title, required this.stepLabel, required this.onBack});

  final String title;
  final String stepLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.navy),
            tooltip: 'Nazad',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimary)),
                Text(stepLabel, style: AppTypography.monoEyebrow.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase 8: shown once `SessionController.isLocked` flips true (both
/// parties confirmed review and signed — §5.3 `report:locked`). Uses the
/// `success` triad (matching `StatusChip`'s `confirmed`/`verified`
/// variants) rather than `pending`/`error` — this is the expected, correct
/// end state of a finished report, not a problem to flag.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.successBg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: AppSpacing.md, color: AppColors.successBorder),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              'Izveštaj je zaključan — oba vozača su potpisala. Dalje izmene nisu moguće.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.successText, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Derived state, not in the source design (§1: "derive it from the
/// existing tokens rather than inventing new styling") — the mockups don't
/// show a disconnected/reconnecting state anywhere. Uses the `pending`
/// status triad rather than `error`: a drop here is an active, automatic
/// retry (socket.io's own reconnection), not a failure the user must act on.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.pendingBg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          const SizedBox(
            width: AppSpacing.md,
            height: AppSpacing.md,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pendingBorder),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              'Ponovno povezivanje sa serverom…',
              style: AppTypography.bodySmall.copyWith(color: AppColors.pendingText, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
