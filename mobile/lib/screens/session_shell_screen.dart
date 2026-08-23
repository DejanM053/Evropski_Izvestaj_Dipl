import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/socket_client.dart';
import '../state/session_controller.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';

/// Screen 4 (docs/master_plan.md §6) — the persistent session shell: both
/// parties' live connection/progress header, wrapping whatever step content
/// comes next. Phases 7-9's screens (5-9) will render inside this shell;
/// for Phase 6 the body is a placeholder that proves the socket plumbing
/// works (session info, live "other driver connected" status) without
/// building any of the form/circumstances/sketch/photos screens yet.
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

class _SessionShellBody extends StatefulWidget {
  const _SessionShellBody({required this.reportId});

  final String reportId;

  @override
  State<_SessionShellBody> createState() => _SessionShellBodyState();
}

class _SessionShellBodyState extends State<_SessionShellBody> {
  SessionErrorEvent? _shownError;

  @override
  void initState() {
    super.initState();
    context.read<SessionController>().addListener(_maybeShowError);
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final connected = controller.connectionState == SocketConnectionState.connected;
    final selfLabel = controller.selfParty == 'A' ? 'VI · VOZAČ A' : 'VI · VOZAČ B';
    final otherLabel = controller.selfParty == 'A' ? 'DRUGI VOZAČ · B' : 'DRUGI VOZAČ · A';

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
                stageLabel: connected ? 'Povezano' : 'Povezivanje…',
                progress: 0,
                isSelf: true,
              ),
              other: SessionPartyProgress(
                label: otherLabel,
                stageLabel: controller.otherPartyConnected ? 'Povezan' : 'Čeka se povezivanje…',
                progress: 0,
                isSelf: false,
              ),
            ),
            if (!connected) const _ReconnectingBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusChip(
                      label: controller.otherPartyConnected ? 'Drugi vozač povezan' : 'Čeka se drugi vozač',
                      variant:
                          controller.otherPartyConnected ? AppStatusChipVariant.confirmed : AppStatusChipVariant.pending,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader(label: 'Podaci o sesiji'),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(
                              children: [
                                MonoDataRow(label: 'Šifra sesije', value: controller.sessionCode),
                                const SizedBox(height: AppSpacing.sm + 2),
                                MonoDataRow(label: 'Vaša uloga', value: 'Vozač ${controller.selfParty}'),
                                const SizedBox(height: AppSpacing.sm + 2),
                                MonoDataRow(label: 'ID izveštaja', value: widget.reportId),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Obrazac izveštaja stiže u sledećoj fazi razvoja. Sve promene će biti vidljive '
                      'obojici vozača u realnom vremenu čim budu dodate.',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppButton(label: 'Napusti sesiju', onPressed: _confirmLeave, variant: AppButtonVariant.secondary),
            ),
          ],
        ),
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
