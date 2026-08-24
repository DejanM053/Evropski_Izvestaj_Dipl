import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/env.dart';
import '../services/api_client.dart';
import '../services/device_id_service.dart';
import '../services/socket_client.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'session_shell_screen.dart';

/// Screen 2 (docs/master_plan.md §6) — Vozač A creates a session and shows
/// the QR / 6-char fallback code until Vozač B joins. Watches a transient
/// socket connection purely to detect that join (`party:status`/
/// `session:state` reporting partyB connected) and then hands off to the
/// session shell, which opens its own fresh socket connection.
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  SocketClient? _socket;
  StreamSubscription<PartyStatusEvent>? _partyStatusSub;
  StreamSubscription<SessionStateEvent>? _sessionStateSub;

  CreateSessionResult? _session;
  bool _loading = true;
  String? _error;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _createSession();
  }

  Future<void> _createSession() async {
    try {
      final deviceId = await DeviceIdService.getOrCreate();
      final result = await _api.createSession(deviceId: deviceId);
      if (!mounted) return;
      setState(() {
        _session = result;
        _loading = false;
      });
      _watchForOtherParty(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _watchForOtherParty(CreateSessionResult result) {
    final socket = SocketClient(baseUrl: Env.apiUrl);
    _socket = socket;
    _sessionStateSub = socket.sessionState.listen((event) {
      if (event.session.partyB.isConnected) _advanceToShell(result);
    });
    _partyStatusSub = socket.partyStatus.listen((event) {
      if (event.party == 'B') _advanceToShell(result);
    });
    socket.connect(sessionId: result.sessionId, party: 'A');
  }

  void _advanceToShell(CreateSessionResult result) {
    if (_advanced || !mounted) return;
    _advanced = true;
    // Tear down the watcher socket before navigating rather than waiting for
    // State.dispose(): SessionShellScreen opens its own fresh socket to the
    // same session/party immediately on mount, and briefly running both at
    // once was observed to leave the new one stuck reconnecting.
    _partyStatusSub?.cancel();
    _sessionStateSub?.cancel();
    _socket?.dispose();
    _socket = null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionShellScreen(
          sessionId: result.sessionId,
          sessionCode: result.sessionCode,
          reportId: result.reportId,
          selfParty: 'A',
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _createSession();
  }

  @override
  void dispose() {
    _partyStatusSub?.cancel();
    _sessionStateSub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nova sesija', style: AppTypography.titleSmall.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xs - 2),
            Text('KORAK 1 / 8', style: AppTypography.monoEyebrow.copyWith(color: AppColors.onNavyMuted)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _retry)
              : _WaitingBody(session: _session!, onCancel: () => Navigator.of(context).pop()),
    );
  }
}

class _WaitingBody extends StatelessWidget {
  const _WaitingBody({required this.session, required this.onCancel});

  final CreateSessionResult session;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final code = session.sessionCode;
    final formattedCode = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pokažite ovaj kod drugom vozaču. Oba telefona ostaju povezana dok se izveštaj ne zapečati.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl - 2),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  size: 196,
                  backgroundColor: AppColors.surface,
                  eyeStyle: const QrEyeStyle(color: AppColors.navy),
                  dataModuleStyle: const QrDataModuleStyle(color: AppColors.navy),
                ),
                const SizedBox(height: AppSpacing.lg + 2),
                Container(height: 1, color: AppColors.borderLight),
                const SizedBox(height: AppSpacing.lg + 2),
                Text('ILI UNESITE ŠIFRU', style: AppTypography.monoEyebrow.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.sm),
                Text(formattedCode, style: AppTypography.monoDisplay.copyWith(color: AppColors.navy)),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  'Važi 24h od kreiranja',
                  style: AppTypography.monoMeta.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                const SizedBox(
                  width: AppSpacing.lg,
                  height: AppSpacing.lg,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                ),
                const SizedBox(width: AppSpacing.md + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Čeka se drugi vozač…',
                        style: AppTypography.buttonLabel.copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.xs - 2),
                      Text('Sesija je otvorena', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Otkaži sesiju', onPressed: onCancel, variant: AppButtonVariant.secondary),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sesija nije kreirana',
              style: AppTypography.titleMedium.copyWith(color: AppColors.errorText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Pokušaj ponovo', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
