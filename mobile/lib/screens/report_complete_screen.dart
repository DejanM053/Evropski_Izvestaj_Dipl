import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../models/report_model.dart';
import '../services/api_client.dart';
import '../state/session_controller.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';

/// Public-testnet block explorers this app knows how to link to (Phase 12
/// only wires up Sepolia in hardhat.config.js — see PROGRESS.md — but Amoy
/// is kept here too since master_plan.md §2 allows either). Anything not in
/// this map (e.g. "localhost"/"hardhat" during dev) gets no explorer link,
/// satisfying "when CHAIN_NETWORK is a public testnet".
const _kExplorerTxBaseUrls = {
  'sepolia': 'https://sepolia.etherscan.io/tx/',
  'amoy': 'https://amoy.polygonscan.com/tx/',
  'polygon-amoy': 'https://amoy.polygonscan.com/tx/',
};

/// Screen 13 (docs/master_plan.md §6 / design "1l", "Izveštaj zapečaćen") —
/// the terminal screen once `report.status == 'sealed'`. PDF open/share both
/// go through one on-demand download (`ApiClient.downloadFile` against the
/// existing `GET /api/files/:fileId`) into a temp file, since `open_filex`/
/// `share_plus` both need a local path, not a URL.
class ReportCompleteScreen extends StatefulWidget {
  const ReportCompleteScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<ReportCompleteScreen> createState() => _ReportCompleteScreenState();
}

class _ReportCompleteScreenState extends State<ReportCompleteScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  bool _downloading = false;
  String? _localPdfPath;
  String? _pdfError;
  bool _detailsExpanded = false;

  Future<String?> _ensureLocalPdf(String pdfFileId) async {
    if (_localPdfPath != null) return _localPdfPath;
    setState(() {
      _downloading = true;
      _pdfError = null;
    });
    try {
      final bytes = await _api.downloadFile(pdfFileId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/izvestaj-$pdfFileId.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return file.path;
      setState(() => _localPdfPath = file.path);
      return file.path;
    } catch (e) {
      if (mounted) setState(() => _pdfError = 'PDF nije preuzet. Proverite konekciju.');
      return null;
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openPdf(String pdfFileId) async {
    final path = await _ensureLocalPdf(pdfFileId);
    if (path == null) return;
    await OpenFilex.open(path);
  }

  Future<void> _sharePdf(String pdfFileId) async {
    final path = await _ensureLocalPdf(pdfFileId);
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'Izveštaj o saobraćajnoj nezgodi'),
    );
  }

  void _copyTxHash(String txHash) {
    Clipboard.setData(ClipboardData(text: txHash));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referenca transakcije kopirana.')));
  }

  Future<void> _openExplorer(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _notImplemented() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Slanje osiguravaču nije deo ovog projekta.')),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}.';
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    return '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _shortHash(String? value) {
    if (value == null || value.length <= 10) return value ?? '—';
    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }

  String _partyLabel(PartyReportModel party, String fallback) {
    final name = [party.driver.lastName, party.driver.firstName].where((s) => s != null && s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final report = controller.report;

    if (report == null) {
      return const Scaffold(backgroundColor: AppColors.paper, body: Center(child: CircularProgressIndicator()));
    }

    final chain = report.chain;
    final partyLabel = '${_partyLabel(report.partyA, 'Vozač A')} ↔ ${_partyLabel(report.partyB, 'Vozač B')}';
    final shortId = '#${report.id.length >= 6 ? report.id.substring(report.id.length - 6).toUpperCase() : report.id}';
    final explorerBase = chain.network != null ? _kExplorerTxBaseUrls[chain.network!.toLowerCase()] : null;
    final explorerUrl = (explorerBase != null && chain.txHash != null) ? '$explorerBase${chain.txHash}' : null;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              color: AppColors.navy,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ZAVRŠENO', style: AppTypography.monoEyebrow.copyWith(color: AppColors.amber)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Izveštaj je zapečaćen',
                          style: AppTypography.headlineLarge.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: -0.1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.amber, width: 2)),
                      child: Column(
                        children: [
                          Text('OVEREN', style: AppTypography.monoLabel.copyWith(color: AppColors.amber)),
                          const SizedBox(height: 2),
                          Text(
                            _fmtDate(report.sealedAt),
                            style: AppTypography.monoMeta.copyWith(color: AppColors.amber),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md + 2),
                      decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 72,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.surfaceAlt, border: Border.all(color: AppColors.border)),
                            child: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.navy, size: 28),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Izveštaj $shortId', style: AppTypography.itemTitle.copyWith(color: AppColors.textPrimary)),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'PDF dokument\n$partyLabel',
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                if (report.pdfFileId != null)
                                  GestureDetector(
                                    onTap: _downloading ? null : () => _openPdf(report.pdfFileId!),
                                    child: Text(
                                      _downloading ? 'Preuzimanje…' : 'Otvori PDF ›',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pdfError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_pdfError!, style: AppTypography.bodySmall.copyWith(color: AppColors.errorText)),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Otvori PDF',
                            onPressed: report.pdfFileId == null || _downloading ? null : () => _openPdf(report.pdfFileId!),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppButton(
                            label: 'Podeli',
                            variant: AppButtonVariant.secondary,
                            onPressed:
                                report.pdfFileId == null || _downloading ? null : () => _sharePdf(report.pdfFileId!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AppColors.successBorder, width: 3)),
                            ),
                            padding: const EdgeInsets.all(AppSpacing.md + 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Pečat potvrđen u registru',
                                      style: AppTypography.itemTitle.copyWith(color: AppColors.successText, fontSize: 13),
                                    ),
                                    Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppColors.successBorder, shape: BoxShape.circle)),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: MonoDataRow(
                                        label: 'Referenca transakcije',
                                        value: _shortHash(chain.txHash),
                                        stacked: true,
                                      ),
                                    ),
                                    if (chain.txHash != null)
                                      IconButton(
                                        onPressed: () => _copyTxHash(chain.txHash!),
                                        icon: const Icon(Icons.copy_outlined, size: 18, color: AppColors.navy),
                                        tooltip: 'Kopiraj',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                InkWell(
                                  onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                    decoration: const BoxDecoration(
                                      border: Border(top: BorderSide(color: AppColors.borderLight)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Detalji overe', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
                                        Icon(
                                          _detailsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                          color: AppColors.navy,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_detailsExpanded) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  MonoDataRow(label: 'Upisano', value: _fmtDateTime(chain.anchoredAt)),
                                  const SizedBox(height: AppSpacing.sm),
                                  MonoDataRow(label: 'Blok', value: chain.blockNumber?.toString() ?? '—'),
                                  const SizedBox(height: AppSpacing.sm),
                                  MonoDataRow(label: 'Mreža', value: chain.network ?? '—'),
                                  const SizedBox(height: AppSpacing.sm),
                                  MonoDataRow(label: 'Adresa ugovora', value: _shortHash(chain.contractAddress)),
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      decoration: BoxDecoration(color: AppColors.surfaceAlt, border: Border.all(color: AppColors.border)),
                      child: Column(
                        children: [
                          _ActionRow(label: 'Pošalji osiguravaču', onTap: _notImplemented),
                          const Divider(height: 1, color: AppColors.border),
                          _ActionRow(label: 'Nazad na početni ekran', onTap: _goHome),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.md + 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.buttonLabel.copyWith(color: AppColors.textPrimary)),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
