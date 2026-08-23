import 'package:dio/dio.dart';

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
}
