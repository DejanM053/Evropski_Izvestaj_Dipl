import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../services/api_client.dart';
import '../state/session_controller.dart';
import '../theme/theme.dart';

enum _StepState { pending, active, done, error }

class _StepRowData {
  const _StepRowData({
    required this.title,
    required this.subtitle,
    required this.state,
    this.progress,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final _StepState state;
  final double? progress;
  final VoidCallback? onRetry;
}

/// Screen 12 (docs/master_plan.md §6 / design "1k", "Zapečaćivanje —
/// napredak") — shown the instant `SessionController.isLocked` flips true
/// (both parties signed). Every step's done/active/error state is derived
/// primarily from the *report's own persisted fields* (`pdfFileId`,
/// `chain.txHash`, `chain.lastError`) rather than solely from the live
/// `report:progress` event stream — a client that reaches this screen via a
/// reconnect (having missed the earlier events) still renders the correct
/// state instead of showing "pending" forever for work that already
/// finished. The live stream is used on top of that ground truth only for
/// in-flight flavor (spinner vs static icon, the short SHA hint, the
/// progress bar) — see `_buildRows`.
///
/// Triggers the pipeline itself with one `POST /finalize` on mount — safe
/// even if both parties' clients do this at the same moment, since the
/// backend's per-report in-flight lock (`finalize.service.js`) makes the
/// loser's call a no-op `202`; both clients still converge on the same
/// `report:progress`/`report:sealed` broadcasts regardless of who "won".
class FinalizingScreen extends StatefulWidget {
  const FinalizingScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<FinalizingScreen> createState() => _FinalizingScreenState();
}

class _FinalizingScreenState extends State<FinalizingScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  bool _requesting = false;
  String? _requestError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoStart());
  }

  // Deliberately does NOT branch on `report.status` ("signing" vs
  // "finalizing") — that field is only ever refreshed from a full
  // `session:state` snapshot (join/reconnect) or a `report:sealed` patch;
  // the live `report:locked` event that gets this screen on screen at all
  // carries no payload and never updates it, so in a live (non-reconnect)
  // session `report.status` stays stale at whatever it was before locking
  // and never actually reads "signing". Gating on it here meant `_start()`
  // was never called at all on a fresh lock — the finalize POST silently
  // never left the client, which showed up as "stuck on PDF generation"
  // (row 2 has no real pending state, just done/active, so it just spun
  // forever). `SessionController.isLocked` is the one flag that *is*
  // reliably live-synced (own dedicated event), and this screen only ever
  // renders once it's already true (see SessionShellScreen) — so the only
  // real question here is whether we already know about a stored failure
  // from a *previous* attempt that needs an explicit retry tap instead of
  // silently auto-retrying.
  void _maybeAutoStart() {
    if (!mounted) return;
    final controller = context.read<SessionController>();
    if (controller.report?.status == 'sealed') return;
    final hasKnownError = controller.finalizeErrorMessage != null || controller.report?.chain.lastError != null;
    if (!hasKnownError) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    try {
      final result = await _api.finalizeReport(widget.reportId);
      if (!mounted) return;
      if (result.report != null) {
        context.read<SessionController>().adoptReport(result.report!);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _requestError = e.message);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  String _fmtTime(DateTime? d) {
    if (d == null) return '—';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  List<_StepRowData> _buildRows(SessionController controller) {
    final report = controller.report;
    final statuses = controller.finalizeStepStatus;

    final selfSignedAt = report?.partyA.signature.signedAt;
    final otherSignedAt = report?.partyB.signature.signedAt;
    final row1 = _StepRowData(
      title: 'Oba potpisa prikupljena',
      subtitle: '${_fmtTime(selfSignedAt)} · ${_fmtTime(otherSignedAt)}',
      state: _StepState.done,
    );

    final pdfDone = report?.pdfFileId != null;
    final row2 = _StepRowData(
      title: 'PDF generisan',
      subtitle: pdfDone ? 'PDF izveštaja je sačuvan.' : 'Generisanje u toku…',
      state: pdfDone ? _StepState.done : _StepState.active,
    );

    final anchorDone = report?.chain.txHash != null;
    final anchorErrorMessage = controller.finalizeErrorMessage ?? report?.chain.lastError;
    final anchorErrored = !anchorDone && anchorErrorMessage != null;
    final registryState = anchorErrored
        ? _StepState.error
        : anchorDone
            ? _StepState.done
            : (pdfDone ? _StepState.active : _StepState.pending);

    final sha = report?.pdfSha256;
    final shortSha =
        (sha != null && sha.length > 10) ? '${sha.substring(0, 6)}…${sha.substring(sha.length - 4)}' : null;

    String row3Subtitle;
    if (registryState == _StepState.error) {
      row3Subtitle = anchorErrorMessage!;
    } else if (registryState == _StepState.done) {
      row3Subtitle = 'Zapisano u registru.';
    } else if (registryState == _StepState.active) {
      row3Subtitle = shortSha != null
          ? 'SHA-256 $shortSha\nPotvrda obično traje 20–40 sekundi.'
          : 'Potvrda obično traje 20–40 sekundi.';
    } else {
      row3Subtitle = 'Na čekanju';
    }

    double? row3Progress;
    if (registryState == _StepState.done) {
      row3Progress = 1;
    } else if (registryState == _StepState.active) {
      const order = ['attachments', 'bundle', 'derive', 'anchor'];
      final doneCount = order.where((k) => statuses[k] == 'done').length;
      row3Progress = doneCount == 0 ? 0.15 : (doneCount + (statuses['anchor'] == 'active' ? 0.5 : 0)) / order.length;
    }

    final row3 = _StepRowData(
      title: 'Upis heša u registar',
      subtitle: row3Subtitle,
      state: registryState,
      progress: row3Progress,
      onRetry: registryState == _StepState.error ? _start : null,
    );

    return [row1, row2, row3];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final rows = _buildRows(controller);

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg + 4, AppSpacing.xl, AppSpacing.lg + 4, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ZAPEČAĆIVANJE U TOKU', style: AppTypography.monoEyebrow.copyWith(color: AppColors.amber)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Izveštaj se zaključava\ni overava',
                style: AppTypography.headlineLarge.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _FinalizeStepRow(row: rows[i], isLast: i == rows.length - 1),
                      if (_requestError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _requestError!,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.errorOnDark),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md + 2),
                decoration: BoxDecoration(border: Border.all(color: AppColors.navyBorder)),
                child: Text(
                  'Možete zatvoriti aplikaciju. Zapečaćivanje se nastavlja, a obaveštenje dobijate kada bude završeno.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.onNavySecondary, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinalizeStepRow extends StatelessWidget {
  const _FinalizeStepRow({required this.row, required this.isLast});

  final _StepRowData row;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final titleColor = row.state == _StepState.pending ? AppColors.onNavyFaintTitle : Colors.white;
    final subtitleColor = row.state == _StepState.error
        ? AppColors.errorOnDark
        : row.state == _StepState.pending
            ? AppColors.onNavyFaint
            : AppColors.onNavyMuted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                _StepIcon(state: row.state),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.navyBorder)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md + 2),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? AppSpacing.sm : AppSpacing.lg + 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: AppTypography.buttonLabel.copyWith(color: titleColor)),
                  const SizedBox(height: AppSpacing.xs - 1),
                  Text(row.subtitle, style: AppTypography.monoMeta.copyWith(color: subtitleColor, height: 1.5)),
                  if (row.progress != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: row.progress,
                          backgroundColor: AppColors.navyTrack,
                          valueColor: const AlwaysStoppedAnimation(AppColors.amber),
                        ),
                      ),
                    ),
                  ],
                  if (row.onRetry != null) ...[
                    const SizedBox(height: AppSpacing.sm + 2),
                    _RetryButton(onTap: row.onRetry!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _StepState.done:
        return Container(
          width: 20,
          height: 20,
          color: AppColors.amber,
          child: const Icon(Icons.check, size: 14, color: AppColors.navy),
        );
      case _StepState.active:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
        );
      case _StepState.error:
        return Container(
          width: 20,
          height: 20,
          color: AppColors.errorBorder,
          child: const Icon(Icons.priority_high, size: 14, color: Colors.white),
        );
      case _StepState.pending:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(border: Border.all(color: AppColors.navyBorder, width: 2)),
        );
    }
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amber,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          child: Text(
            'Pokušaj ponovo',
            style: AppTypography.buttonLabel.copyWith(color: AppColors.navy, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
