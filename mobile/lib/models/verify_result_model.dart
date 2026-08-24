/// Dart mirror of `GET /api/reports/:id/verify`'s response
/// (docs/master_plan.md §5.5, `backend/src/services/verify.service.js`).
/// Every hash here was recomputed by the backend from bytes read back out
/// of GridFS/chain at request time — `storedHash` is only a third data
/// point for display, never what `match` is based on.
library;

enum VerifyVerdict { verified, tampered, notAnchored }

VerifyVerdict _verdictFromJson(String value) {
  switch (value) {
    case 'VERIFIED':
      return VerifyVerdict.verified;
    case 'TAMPERED':
      return VerifyVerdict.tampered;
    case 'NOT_ANCHORED':
    default:
      return VerifyVerdict.notAnchored;
  }
}

class PdfVerifyResult {
  const PdfVerifyResult({this.storedHash, this.recomputedHash, this.onChainHash, required this.match});

  final String? storedHash;
  final String? recomputedHash;
  final String? onChainHash;
  final bool match;

  factory PdfVerifyResult.fromJson(Map<String, dynamic> json) => PdfVerifyResult(
        storedHash: json['storedHash'] as String?,
        recomputedHash: json['recomputedHash'] as String?,
        onChainHash: json['onChainHash'] as String?,
        match: json['match'] as bool? ?? false,
      );
}

class BundleVerifyResult {
  const BundleVerifyResult({this.recomputedHash, this.onChainHash, required this.match});

  final String? recomputedHash;
  final String? onChainHash;
  final bool match;

  factory BundleVerifyResult.fromJson(Map<String, dynamic> json) => BundleVerifyResult(
        recomputedHash: json['recomputedHash'] as String?,
        onChainHash: json['onChainHash'] as String?,
        match: json['match'] as bool? ?? false,
      );
}

class AttachmentVerifyResult {
  const AttachmentVerifyResult({required this.fileId, required this.kind, required this.match});

  final String fileId;
  final String kind;
  final bool match;

  factory AttachmentVerifyResult.fromJson(Map<String, dynamic> json) => AttachmentVerifyResult(
        fileId: json['fileId'] as String,
        kind: json['kind'] as String? ?? '',
        match: json['match'] as bool? ?? false,
      );
}

class VerifyChainInfo {
  const VerifyChainInfo({this.txHash, this.blockNumber, this.network, this.anchoredAt});

  final String? txHash;
  final int? blockNumber;
  final String? network;
  final DateTime? anchoredAt;

  factory VerifyChainInfo.fromJson(Map<String, dynamic> json) => VerifyChainInfo(
        txHash: json['txHash'] as String?,
        blockNumber: json['blockNumber'] as int?,
        network: json['network'] as String?,
        anchoredAt: json['anchoredAt'] == null ? null : DateTime.parse(json['anchoredAt'] as String),
      );
}

class VerifyResult {
  const VerifyResult({
    required this.reportId,
    required this.pdf,
    required this.bundle,
    required this.attachments,
    required this.chain,
    required this.verdict,
  });

  final String reportId;
  final PdfVerifyResult pdf;
  final BundleVerifyResult bundle;
  final List<AttachmentVerifyResult> attachments;
  final VerifyChainInfo chain;
  final VerifyVerdict verdict;

  /// The attachments whose recomputed hash no longer matches what was
  /// recorded at finalize time — this is what lets screen 14 name exactly
  /// which file failed, not just that something did.
  List<AttachmentVerifyResult> get failedAttachments => attachments.where((a) => !a.match).toList();

  factory VerifyResult.fromJson(Map<String, dynamic> json) => VerifyResult(
        reportId: json['reportId'] as String,
        pdf: PdfVerifyResult.fromJson((json['pdf'] as Map).cast<String, dynamic>()),
        bundle: BundleVerifyResult.fromJson((json['bundle'] as Map).cast<String, dynamic>()),
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map((a) => AttachmentVerifyResult.fromJson((a as Map).cast<String, dynamic>()))
            .toList(),
        chain: json['chain'] == null
            ? const VerifyChainInfo()
            : VerifyChainInfo.fromJson((json['chain'] as Map).cast<String, dynamic>()),
        verdict: _verdictFromJson(json['verdict'] as String? ?? 'NOT_ANCHORED'),
      );
}
