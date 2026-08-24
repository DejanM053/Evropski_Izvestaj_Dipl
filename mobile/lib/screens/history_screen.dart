import 'package:flutter/material.dart';

import '../config/env.dart';
import '../models/report_model.dart';
import '../services/api_client.dart';
import '../services/device_id_service.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'report_complete_screen.dart';

/// Screen 15 (docs/master_plan.md §6) — past reports scoped by this
/// device's locally generated deviceId (§6 client rules,
/// `DeviceIdService`), newest first. No source mockup exists for this
/// screen (see .claude/rules/mobile.md) — the list reuses [ReportListTile],
/// shared with the Verify picker (screen 14) since both need the same
/// date/other-party/plate/status summary row.
///
/// A sealed report's row taps through to [ReportCompleteScreen] (screen
/// 13), which itself has a "Proveri integritet" action leading to
/// [VerifyScreen] (screen 14) — satisfying "tapping through to screens 13
/// and 14" without a second tap target per row. Already-fetched full
/// report JSON (`GET /api/reports?deviceId=` returns whole documents, not
/// summaries) is passed straight into `ReportCompleteScreen.report`, so no
/// second network round trip is needed and no live `SessionController` has
/// to exist for a session whose 24h TTL may be long gone. A non-sealed row
/// (still in progress, or abandoned) has no live session left to resume
/// into from History, so it just explains that instead of dead-navigating.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);

  List<ReportModel>? _reports;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final deviceId = await DeviceIdService.getOrCreate();
      final reports = await _api.getReports(deviceId: deviceId);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _openReport(ReportModel report) {
    if (report.status != 'sealed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ovaj izveštaj još nije zapečaćen — sesija se ne može ponovo otvoriti odavde.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportCompleteScreen(reportId: report.id, report: report)),
    );
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
            Text('Istorija izveštaja', style: AppTypography.titleSmall.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xs - 2),
            Text('OVAJ UREĐAJ', style: AppTypography.monoEyebrow.copyWith(color: AppColors.onNavyMuted)),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Istorija nije učitana',
                style: AppTypography.titleMedium.copyWith(color: AppColors.errorText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: 'Pokušaj ponovo', onPressed: _load),
            ],
          ),
        ),
      );
    }

    final reports = _reports ?? const [];
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open_outlined, size: 40, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Nema sačuvanih izveštaja',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Izveštaji koje kreirate ili kojima se pridružite na ovom uređaju pojaviće se ovde.',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView.builder(
        itemCount: reports.length,
        itemBuilder: (context, i) => ReportListTile(report: reports[i], onTap: () => _openReport(reports[i])),
      ),
    );
  }
}
