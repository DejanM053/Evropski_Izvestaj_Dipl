import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../models/report_model.dart';
import '../models/verify_result_model.dart';
import '../services/api_client.dart';
import '../services/device_id_service.dart';
import '../theme/theme.dart';
import '../utils/block_explorer.dart';
import '../widgets/widgets.dart';

/// Screen 14 (docs/master_plan.md §6/§5.5) — the thesis centerpiece. Two
/// entry paths:
///  - with [reportId] already known (from ReportCompleteScreen's "Proveri
///    integritet" action, or a History row's verify shortcut) — runs
///    verification immediately.
///  - without one (Home's "Provera izveštaja" row) — shows a picker of this
///    device's own sealed reports first (only a sealed report has anything
///    to verify), then runs on the chosen one.
///
/// No source mockup exists for this screen (screens 14/15 weren't part of
/// the imported design set — see .claude/rules/mobile.md); the layout
/// reuses the existing token/widget vocabulary (SectionHeader, StatusChip,
/// MonoDataRow, and the errorHighlightBg/successHighlightBg tokens
/// `app_colors.dart` already reserves specifically for "the verify screen's
/// hash-diff highlight") rather than copying an unseen screen.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, this.reportId});

  final String? reportId;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);

  String? _selectedReportId;

  List<ReportModel>? _pickerReports;
  bool _pickerLoading = false;
  String? _pickerError;

  VerifyResult? _result;
  bool _verifying = false;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    if (widget.reportId != null) {
      _runVerify(widget.reportId!);
    } else {
      _loadPicker();
    }
  }

  Future<void> _loadPicker() async {
    setState(() {
      _pickerLoading = true;
      _pickerError = null;
    });
    try {
      final deviceId = await DeviceIdService.getOrCreate();
      final reports = await _api.getReports(deviceId: deviceId);
      if (!mounted) return;
      setState(() {
        _pickerReports = reports.where((r) => r.status == 'sealed').toList();
        _pickerLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        _pickerError = e.message;
      });
    }
  }

  Future<void> _runVerify(String reportId) async {
    setState(() {
      _selectedReportId = reportId;
      _verifying = true;
      _verifyError = null;
      _result = null;
    });
    try {
      final result = await _api.verifyReport(reportId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _verifying = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verifyError = e.message;
      });
    }
  }

  void _pickAnother() {
    setState(() {
      _selectedReportId = null;
      _result = null;
      _verifyError = null;
    });
    if (widget.reportId == null) _loadPicker();
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
            Text('Provera izveštaja', style: AppTypography.titleSmall.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xs - 2),
            Text('PROVERA INTEGRITETA', style: AppTypography.monoEyebrow.copyWith(color: AppColors.onNavyMuted)),
          ],
        ),
      ),
      body: _selectedReportId == null ? _buildPicker() : _buildResult(),
    );
  }

  Widget _buildPicker() {
    if (_pickerLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_pickerError != null) {
      return _ErrorState(message: _pickerError!, onRetry: _loadPicker);
    }
    final reports = _pickerReports ?? const [];
    if (reports.isEmpty) {
      return const _EmptyState(
        title: 'Nema zapečaćenih izveštaja',
        message: 'Proveru integriteta možete pokrenuti tek nakon što izveštaj bude zapečaćen.',
        icon: Icons.verified_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Text(
            'Izaberite izveštaj za proveru',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, i) => ReportListTile(
              report: reports[i],
              onTap: () => _runVerify(reports[i].id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_verifying) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_verifyError != null) {
      return _ErrorState(message: _verifyError!, onRetry: () => _runVerify(_selectedReportId!));
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VerdictBanner(verdict: result.verdict),
          const SizedBox(height: AppSpacing.lg),
          _HashComparisonCard(
            title: 'Heš PDF dokumenta',
            recomputedHash: result.pdf.recomputedHash,
            onChainHash: result.pdf.onChainHash,
            match: result.pdf.match,
          ),
          const SizedBox(height: AppSpacing.md),
          _HashComparisonCard(
            title: 'Heš svih priloga (bundle)',
            recomputedHash: result.bundle.recomputedHash,
            onChainHash: result.bundle.onChainHash,
            match: result.bundle.match,
          ),
          if (result.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _AttachmentsCard(attachments: result.attachments),
          ],
          const SizedBox(height: AppSpacing.lg),
          _ChainDetailsCard(chain: result.chain),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Proveri ponovo',
            variant: AppButtonVariant.secondary,
            onPressed: () => _runVerify(_selectedReportId!),
          ),
          if (widget.reportId == null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Izaberi drugi izveštaj', variant: AppButtonVariant.secondary, onPressed: _pickAnother),
          ],
        ],
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.verdict});

  final VerifyVerdict verdict;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color border;
    late final Color fg;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    switch (verdict) {
      case VerifyVerdict.verified:
        bg = AppColors.successBg;
        border = AppColors.successBorder;
        fg = AppColors.successText;
        icon = Icons.verified_outlined;
        title = 'VERIFIKOVANO';
        subtitle = 'Dokument i prilozi se poklapaju sa zapisom u registru.';
        break;
      case VerifyVerdict.tampered:
        bg = AppColors.errorBg;
        border = AppColors.errorBorder;
        fg = AppColors.errorText;
        icon = Icons.gpp_bad_outlined;
        title = 'IZMENJENO';
        subtitle = 'Sadržaj se ne poklapa sa zapisom u registru — izveštaj je izmenjen nakon overe.';
        break;
      case VerifyVerdict.notAnchored:
        bg = AppColors.pendingBg;
        border = AppColors.pendingBorder;
        fg = AppColors.pendingText;
        icon = Icons.hourglass_empty;
        title = 'NIJE OVEREN';
        subtitle = 'Izveštaj još nije zapisan u registru na blokčejnu, pa se ne može proveriti.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: bg, border: Border(left: BorderSide(color: border, width: 4))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleLarge.copyWith(color: fg)),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: AppTypography.bodyMedium.copyWith(color: fg, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "recomputed vs on-chain hashes side by side in monospace" spec
/// requirement — two stacked [MonoDataRow]s in a highlighted block, colored
/// via the tokens `app_colors.dart` reserves for exactly this
/// (`successHighlightBg`/`errorHighlightBg`).
class _HashComparisonCard extends StatelessWidget {
  const _HashComparisonCard({
    required this.title,
    required this.recomputedHash,
    required this.onChainHash,
    required this.match,
  });

  final String title;
  final String? recomputedHash;
  final String? onChainHash;
  final bool match;

  @override
  Widget build(BuildContext context) {
    final highlightBg = match ? AppColors.successHighlightBg : AppColors.errorHighlightBg;
    final accent = match ? AppColors.successBorder : AppColors.errorBorder;

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(label: title),
          Container(
            color: highlightBg,
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonoDataRow(label: 'Iz dokumenta (izračunato sada)', value: recomputedHash ?? 'nedostupno', stacked: true),
                const SizedBox(height: AppSpacing.md),
                MonoDataRow(label: 'Iz registra (blokčejn)', value: onChainHash ?? 'nije overeno', stacked: true),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(match ? Icons.check_circle : Icons.cancel, size: 16, color: accent),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      match ? 'Heševi se poklapaju' : 'Heševi se NE poklapaju',
                      style: AppTypography.bodySmall.copyWith(color: accent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({required this.attachments});

  final List<AttachmentVerifyResult> attachments;

  String _kindLabel(String kind) {
    switch (kind) {
      case 'photo':
        return 'Fotografija';
      case 'sketch':
        return 'Skica';
      case 'signature':
        return 'Potpis';
      default:
        return kind;
    }
  }

  String _shortId(String id) => id.length > 8 ? '…${id.substring(id.length - 8)}' : id;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(label: 'Prilozi'),
          for (var i = 0; i < attachments.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.borderLight),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.sm + 2),
              child: Row(
                children: [
                  Icon(
                    attachments[i].match ? Icons.check_circle_outline : Icons.error_outline,
                    size: 18,
                    color: attachments[i].match ? AppColors.successBorder : AppColors.errorBorder,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      _kindLabel(attachments[i].kind),
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  Text(
                    _shortId(attachments[i].fileId),
                    style: AppTypography.monoValueTiny.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(
                    label: attachments[i].match ? 'Ispravno' : 'Izmenjeno',
                    variant: attachments[i].match ? AppStatusChipVariant.verified : AppStatusChipVariant.tampered,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChainDetailsCard extends StatelessWidget {
  const _ChainDetailsCard({required this.chain});

  final VerifyChainInfo chain;

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}. '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openExplorer(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final explorerUrl = explorerTxUrl(chain.network, chain.txHash);

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(label: 'Podaci o overi'),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonoDataRow(label: 'Referenca transakcije', value: chain.txHash ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                MonoDataRow(label: 'Blok', value: chain.blockNumber?.toString() ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                MonoDataRow(label: 'Mreža', value: chain.network ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                MonoDataRow(label: 'Upisano', value: _fmtDateTime(chain.anchoredAt)),
                if (explorerUrl != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  GestureDetector(
                    onTap: () => _openExplorer(explorerUrl),
                    child: Text(
                      'Pogledaj na blok exploreru ›',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message, required this.icon});

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
              'Provera nije uspela',
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
