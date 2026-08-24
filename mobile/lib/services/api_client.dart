import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueChanged;

import '../models/report_model.dart';
import '../models/session_model.dart';

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

  Future<CreateSessionResult> createSession() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/api/sessions');
      return CreateSessionResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<JoinSessionResult> joinSession(String sessionCode) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/api/sessions/${Uri.encodeComponent(sessionCode)}/join');
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
}
