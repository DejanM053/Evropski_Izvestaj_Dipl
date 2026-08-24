import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueChanged;

import '../models/report_model.dart';
import '../models/session_model.dart';
import '../models/verify_result_model.dart';

/// Thrown for any failed request. `statusCode` is null for network-level
/// failures (no response at all — host unreachable, timeout).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDioException(DioException e) {
    final data = e.response?.data;
    final serverMessage = data is Map && data['error'] is String ? data['error'] as String : null;
    return ApiException(serverMessage ?? e.message ?? 'Network error', statusCode: e.response?.statusCode);
  }

  @override
  String toString() => message;
}

class CreateSessionResult {
  const CreateSessionResult({required this.sessionId, required this.sessionCode, required this.reportId});

  final String sessionId;
  final String sessionCode;
  final String reportId;

  factory CreateSessionResult.fromJson(Map<String, dynamic> json) => CreateSessionResult(
        sessionId: json['sessionId'] as String,
        sessionCode: json['sessionCode'] as String,
        reportId: json['reportId'] as String,
      );
}

class JoinSessionResult {
  const JoinSessionResult({required this.sessionId, required this.sessionCode, required this.reportId});

  final String sessionId;
  final String sessionCode;
  final String reportId;

  factory JoinSessionResult.fromJson(Map<String, dynamic> json) => JoinSessionResult(
        sessionId: json['sessionId'] as String,
        sessionCode: json['sessionCode'] as String,
        reportId: json['reportId'] as String,
      );
}

class UploadResult {
  const UploadResult({required this.fileId, required this.sha256});

  final String fileId;
  final String sha256;

  factory UploadResult.fromJson(Map<String, dynamic> json) =>
      UploadResult(fileId: json['fileId'] as String, sha256: json['sha256'] as String);
}

/// Result of `ApiClient.finalizeReport`. `inProgress: true` means the
/// backend's per-report in-flight lock rejected this call with `202`
/// because another request (this device's own retry, or the other party's
/// client) already owns the pipeline run — [report] is null in that case,
/// and the caller should rely on `report:progress`/`report:sealed` instead.
class FinalizeResult {
  const FinalizeResult({this.report, required this.inProgress});

  final ReportModel? report;
  final bool inProgress;
}

class SessionStateResult {
  const SessionStateResult({required this.session, this.report});

  final SessionModel session;
  final ReportModel? report;

  factory SessionStateResult.fromJson(Map<String, dynamic> json) => SessionStateResult(
        session: SessionModel.fromJson((json['session'] as Map).cast<String, dynamic>()),
        report:
            json['report'] == null ? null : ReportModel.fromJson((json['report'] as Map).cast<String, dynamic>()),
      );
}

/// Thin REST wrapper around the backend session endpoints
/// (docs/master_plan.md §5.2). `baseUrl` always comes from the caller
/// (ultimately `Env.apiUrl`, i.e. `--dart-define=API_URL=...`) — this class
/// never hardcodes a host.
class ApiClient {
  ApiClient({required this.baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ));

  final String baseUrl;
  final Dio _dio;

  /// `deviceId` (docs/master_plan.md §6 client rules,
  /// `DeviceIdService.getOrCreate()`) is recorded on the created report so
  /// it later shows up in this device's own `getReports` history — see
  /// `Report.deviceIds` (Phase 11 schema decision, `backend/src/models/Report.js`).
  Future<CreateSessionResult> createSession({required String deviceId}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/api/sessions', data: {'deviceId': deviceId});
      return CreateSessionResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<JoinSessionResult> joinSession(String sessionCode, {required String deviceId}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/sessions/${Uri.encodeComponent(sessionCode)}/join',
        data: {'deviceId': deviceId},
      );
      return JoinSessionResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<SessionStateResult> getSession(String sessionId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/sessions/${Uri.encodeComponent(sessionId)}');
      return SessionStateResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /api/reports/:id/photos` (docs/master_plan.md §5.2) — multipart,
  /// additive. `onProgress` reports 0..1 for the Photos screen's per-file
  /// upload bar.
  Future<UploadResult> uploadPhoto({
    required String reportId,
    required String filePath,
    required String party,
    String caption = '',
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final form = FormData.fromMap({
        'party': party,
        'caption': caption,
        'file': await MultipartFile.fromFile(filePath),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/reports/${Uri.encodeComponent(reportId)}/photos',
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      return UploadResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `DELETE /api/reports/:id/photos/:fileId` — removes one photo before
  /// the report is sealed (docs/master_plan.md §6 screen 9's "delete before
  /// lock"; added to `backend/src/routes/uploads.js` in this phase, see
  /// PROGRESS.md).
  Future<void> deletePhoto({required String reportId, required String fileId}) async {
    try {
      await _dio.delete<void>(
        '/api/reports/${Uri.encodeComponent(reportId)}/photos/${Uri.encodeComponent(fileId)}',
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /api/reports/:id/sketch` — single PNG, shared between parties
  /// (`bytes` come from the sketch canvas's `RepaintBoundary.toImage`
  /// export, not a file on disk, hence `fromBytes` rather than `fromFile`).
  Future<UploadResult> uploadSketch({
    required String reportId,
    required Uint8List bytes,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'sketch.png'),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/reports/${Uri.encodeComponent(reportId)}/sketch',
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      return UploadResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /api/reports/:id/signature` — single PNG per party (docs/master_plan.md
  /// §5.2/§6 screen 11). The server broadcasts the resulting `{fileId,
  /// signedAt}` back over `report:patched` (path `partyX.signature`) so the
  /// caller doesn't need to separately sync local state — see
  /// `backend/src/routes/uploads.js`'s `broadcastPatch`.
  Future<UploadResult> uploadSignature({
    required String reportId,
    required Uint8List bytes,
    required String party,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final form = FormData.fromMap({
        'party': party,
        'file': MultipartFile.fromBytes(bytes, filename: 'signature.png'),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/reports/${Uri.encodeComponent(reportId)}/signature',
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      return UploadResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /api/reports/:id/finalize` (docs/master_plan.md §5.2/§5.4, Phase
  /// 10) — kicks off (or resumes/retries the anchor step of) the finalize
  /// pipeline. Real progress is driven by `report:progress`/`report:sealed`
  /// over the socket, not by this call's own response — this is mainly
  /// "did the request even reach the server", plus a same-tick shortcut for
  /// whichever client's call is the one that actually ran or found the
  /// report already sealed (see `SessionController.adoptReport`).
  Future<FinalizeResult> finalizeReport(String reportId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/reports/${Uri.encodeComponent(reportId)}/finalize',
      );
      if (res.statusCode == 202) {
        return const FinalizeResult(inProgress: true);
      }
      return FinalizeResult(report: ReportModel.fromJson(res.data!), inProgress: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Downloads a stored file's raw bytes (`GET /api/files/:fileId`) — used
  /// by the Report complete screen to fetch the sealed PDF before handing
  /// it to `open_filex`/`share_plus`, since both need a local file path,
  /// not a URL.
  Future<Uint8List> downloadFile(String fileId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/api/files/${Uri.encodeComponent(fileId)}',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /api/reports?deviceId=...` (docs/master_plan.md §5.2, Phase 11) —
  /// screen 15's History list. Newest first, per the backend's own sort.
  Future<List<ReportModel>> getReports({required String deviceId}) async {
    try {
      final res = await _dio.get<List<dynamic>>('/api/reports', queryParameters: {'deviceId': deviceId});
      return (res.data ?? const [])
          .map((r) => ReportModel.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /api/reports/:id/verify` (docs/master_plan.md §5.5, Phase 11) —
  /// screen 14. Always a fresh server-side recompute, never cached.
  Future<VerifyResult> verifyReport(String reportId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/reports/${Uri.encodeComponent(reportId)}/verify');
      return VerifyResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
