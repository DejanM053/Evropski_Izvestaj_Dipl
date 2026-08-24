import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/socket_client.dart';
import '../state/session_controller.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'finalizing_screen.dart';
import 'report_complete_screen.dart';
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
/// photos, review, signature). Once the report locks (both parties signed),
/// this same body swaps entirely to [FinalizingScreen] and then
/// [ReportCompleteScreen] (screens 12-13) rather than nesting them inside
/// the step `IndexedStack` — both are full-bleed navy/paper screens in the
/// source design with their own header treatment, not another step behind
/// this shell's own header/step bar. Doing this as a conditional swap
/// inside `_SessionShellBodyState.build` (instead of `Navigator.push`) keeps
/// the same long-lived `SessionController`/socket alive across the
/// transition — routing away would tear down the `ChangeNotifierProvider`
/// that owns it.
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

    // Screens 12-13: once locked (both signed), editing is moot — swap the
    // whole shell body for the Finalizing/Report-complete screens instead
    // of showing a dimmed, still-technically-there form underneath. Sealed
    // takes priority over merely-locked so a client that reconnects after
    // finalize already completed lands straight on the complete screen
    // rather than briefly showing the finalizing one.
    if (controller.report?.status == 'sealed') {
      return ReportCompleteScreen(reportId: widget.reportId);
    }
    if (controller.isLocked) {
      return FinalizingScreen(reportId: widget.reportId);
    }

    final connected = controller.connectionState == SocketConnectionState.connected;
    final selfLabel = controller.selfParty == 'A' ? 'VI · VOZAČ A' : 'VI · VOZAČ B';
    final otherLabel = controller.selfParty == 'A' ? 'DRUGI VOZAČ · B' : 'DRUGI VOZAČ · A';
    final otherStage = controller.otherPartyStage;

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
            if (!connected) const _ReconnectingBanner(),
            _StepHeaderBar(
              title: _kSteps[_stepIndex].title,
              stepLabel: 'KORAK ${_stepIndex + _kFirstGlobalStep} / $_kTotalSteps',
              onBack: _handleBack,
            ),
            Expanded(
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
