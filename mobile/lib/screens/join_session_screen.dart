import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/env.dart';
import '../services/api_client.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import 'session_shell_screen.dart';

/// Excludes 0/O/1/I/L — mirrors `backend/src/services/session-code.service.js`'s
/// `ALPHABET` so the manual-entry field can reject an obviously malformed
/// code before spending a round trip on it. The server remains the actual
/// source of truth (a code that passes this check can still 404/409).
const _kSessionCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Screen 3 (docs/master_plan.md §6) — Vozač B joins by camera-scanning the
/// QR the other device rendered, or by typing the 6-char fallback code.
class JoinSessionScreen extends StatefulWidget {
  const JoinSessionScreen({super.key});

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  final _api = ApiClient(baseUrl: Env.apiUrl);
  final _scannerController = MobileScannerController();
  final _codeController = TextEditingController();

  bool _joining = false;
  String? _manualError;

  @override
  void dispose() {
    _scannerController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_joining) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw.isEmpty) return;
    _attemptJoin(raw);
  }

  bool _isValidCode(String code) {
    if (code.length != 6) return false;
    for (final char in code.split('')) {
      if (!_kSessionCodeAlphabet.contains(char)) return false;
    }
    return true;
  }

  String _messageFor(ApiException e) {
    switch (e.statusCode) {
      case 404:
        return 'Sesija nije pronađena. Proverite šifru.';
      case 409:
        return 'Sesija je već popunjena.';
      default:
        return 'Greška pri povezivanju. Pokušajte ponovo.';
    }
  }

  Future<void> _attemptJoin(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (!_isValidCode(code)) {
      setState(() => _manualError = 'Šifra mora imati 6 znakova (bez 0, O, 1, I, L).');
      return;
    }

    setState(() {
      _joining = true;
      _manualError = null;
    });
    await _scannerController.stop();

    try {
      final result = await _api.joinSession(code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SessionShellScreen(
            sessionId: result.sessionId,
            sessionCode: result.sessionCode,
            reportId: result.reportId,
            selfParty: 'B',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _manualError = _messageFor(e);
      });
      await _scannerController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scannerDarkBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pridruži se sesiji', style: AppTypography.titleSmall.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xs - 2),
            Text(
              'SKENIRAJ QR DRUGOG VOZAČA',
              style: AppTypography.monoEyebrow.copyWith(color: AppColors.onNavyMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _CameraUnavailable(error: error),
                ),
                const IgnorePointer(child: _ScannerOverlay()),
              ],
            ),
          ),
          _ManualEntryPanel(
            controller: _codeController,
            errorText: _manualError,
            loading: _joining,
            onSubmit: () => _attemptJoin(_codeController.text),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  static const _frameSize = 264.0;
  static const _cornerLength = 46.0;
  static const _cornerThickness = 5.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: _frameSize,
          height: _frameSize,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35), width: 2),
                ),
              ),
              _corner(isTop: true, isLeft: true),
              _corner(isTop: true, isLeft: false),
              _corner(isTop: false, isLeft: true),
              _corner(isTop: false, isLeft: false),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Postavite QR kod u okvir',
          style: AppTypography.bodySmall.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _corner({required bool isTop, required bool isLeft}) {
    return Align(
      alignment: Alignment(isLeft ? -1 : 1, isTop ? -1 : 1),
      child: Container(
        width: _cornerLength,
        height: _cornerLength,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: AppColors.amber, width: _cornerThickness) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: AppColors.amber, width: _cornerThickness) : BorderSide.none,
            left: isLeft ? const BorderSide(color: AppColors.amber, width: _cornerThickness) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: AppColors.amber, width: _cornerThickness) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.scannerDarkBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: AppColors.onNavyMuted, size: AppSpacing.xxl),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Kamera nije dostupna. Unesite šifru ispod.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualEntryPanel extends StatelessWidget {
  const _ManualEntryPanel({
    required this.controller,
    required this.errorText,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.paper,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('NEMA QR KODA? UNESITE ŠIFRU', style: AppTypography.monoEyebrow.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
            child: TextField(
              controller: controller,
              enabled: !loading,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: AppTypography.monoCodeInput.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                counterText: '',
              ),
              inputFormatters: [_UpperCaseTextFormatter()],
              onSubmitted: (_) => loading ? null : onSubmit(),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(errorText!, style: AppTypography.caption.copyWith(color: AppColors.errorText)),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: loading ? 'Povezivanje…' : 'Poveži se',
            onPressed: loading ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
