import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/report_model.dart';
import '../models/session_model.dart';

enum SocketConnectionState { connecting, connected, disconnected }

class SessionStateEvent {
  const SessionStateEvent({required this.session, this.report});

  final SessionModel session;
  final ReportModel? report;

  factory SessionStateEvent.fromJson(Map<String, dynamic> json) => SessionStateEvent(
        session: SessionModel.fromJson((json['session'] as Map).cast<String, dynamic>()),
        report:
            json['report'] == null ? null : ReportModel.fromJson((json['report'] as Map).cast<String, dynamic>()),
      );
}

class PartyStatusEvent {
  const PartyStatusEvent({required this.party, this.stage, required this.ready});

  final String party;
  final String? stage;
  final bool ready;

  factory PartyStatusEvent.fromJson(Map<String, dynamic> json) => PartyStatusEvent(
        party: json['party'] as String,
        stage: json['stage'] as String?,
        ready: json['ready'] as bool? ?? false,
      );
}

class ReportPatchedEvent {
  const ReportPatchedEvent({required this.path, required this.value, required this.by});

  final String path;
  final dynamic value;
  final String by;

  factory ReportPatchedEvent.fromJson(Map<String, dynamic> json) => ReportPatchedEvent(
        path: json['path'] as String,
        value: json['value'],
        by: json['by'] as String,
      );
}

/// `report:progress` (docs/master_plan.md §5.3, Phase 10) — one event per
/// finalize pipeline step transition (`backend/src/services/finalize.service.js`).
/// `step` is an opaque key (`validate`/`lock`/`pdf`/`hash`/`store`/
/// `attachments`/`bundle`/`derive`/`anchor`/`seal`) — same convention as
/// `PartyStatusEvent.stage`: the server never sends a display label, the
/// client owns its own copy of what each key means (see FinalizingScreen).
class ReportProgressEvent {
  const ReportProgressEvent({required this.step, required this.status, this.error, this.txHash});

  final String step;

  /// `'active'` | `'done'` | `'error'`.
  final String status;
  final String? error;
  final String? txHash;

  factory ReportProgressEvent.fromJson(Map<String, dynamic> json) => ReportProgressEvent(
        step: json['step'] as String,
        status: json['status'] as String,
        error: json['error'] as String?,
        txHash: json['txHash'] as String?,
      );
}

/// `report:sealed` (docs/master_plan.md §5.3, Phase 10) — the finalize
/// pipeline's final event. Extends the plan's minimal `{pdfFileId, txHash,
/// blockNumber}` with the rest of the chain record (see
/// `.claude/rules/backend.md`) so a client that *isn't* the one whose own
/// `POST /finalize` completed the pipeline can still render the full sealed
/// state without an extra REST round-trip.
class ReportSealedEvent {
  const ReportSealedEvent({
    required this.pdfFileId,
    required this.txHash,
    required this.blockNumber,
    this.contractAddress,
    this.network,
    this.anchoredAt,
  });

  final String pdfFileId;
  final String txHash;
  final int blockNumber;
  final String? contractAddress;
  final String? network;
  final DateTime? anchoredAt;

  factory ReportSealedEvent.fromJson(Map<String, dynamic> json) => ReportSealedEvent(
        pdfFileId: json['pdfFileId'] as String,
        txHash: json['txHash'] as String,
        blockNumber: json['blockNumber'] as int,
        contractAddress: json['contractAddress'] as String?,
        network: json['network'] as String?,
        anchoredAt: json['anchoredAt'] == null ? null : DateTime.parse(json['anchoredAt'] as String),
      );
}

class SessionErrorEvent {
  const SessionErrorEvent({required this.code, required this.message});

  final String code;
  final String message;

  factory SessionErrorEvent.fromJson(Map<String, dynamic> json) => SessionErrorEvent(
        code: json['code'] as String? ?? 'UNKNOWN',
        message: json['message'] as String? ?? 'Unknown error',
      );
}

/// Wraps the Socket.IO session-room contract (docs/master_plan.md §5.3,
/// `.claude/rules/backend.md`). One instance per active session.
///
/// The underlying socket.io-client fires its `connect` event on the first
/// connection *and* on every automatic reconnect (each reconnect is a fresh
/// handshake with a new socket id), so re-emitting `session:join` from
/// [onConnect] is what drives both the initial join and the
/// reconnect-resync — the server always answers `session:join` with a fresh
/// `session:state` snapshot pulled straight from Mongo.
class SocketClient {
  SocketClient({required this.baseUrl});

  final String baseUrl;
  io.Socket? _socket;
  String? _sessionId;
  String? _party;

  final _connectionStateController = StreamController<SocketConnectionState>.broadcast();
  final _sessionStateController = StreamController<SessionStateEvent>.broadcast();
  final _partyStatusController = StreamController<PartyStatusEvent>.broadcast();
  final _reportPatchedController = StreamController<ReportPatchedEvent>.broadcast();
  final _reportLockedController = StreamController<void>.broadcast();
  final _reportProgressController = StreamController<ReportProgressEvent>.broadcast();
  final _reportSealedController = StreamController<ReportSealedEvent>.broadcast();
  final _errorController = StreamController<SessionErrorEvent>.broadcast();

  Stream<SocketConnectionState> get connectionState => _connectionStateController.stream;
  Stream<SessionStateEvent> get sessionState => _sessionStateController.stream;
  Stream<PartyStatusEvent> get partyStatus => _partyStatusController.stream;
  Stream<ReportPatchedEvent> get reportPatched => _reportPatchedController.stream;

  /// `report:locked` (docs/master_plan.md §5.3) — emitted once both parties
  /// have confirmed review and signed (Phase 8). No payload; screens react
  /// by re-reading `SessionController.isLocked`.
  Stream<void> get reportLocked => _reportLockedController.stream;

  /// `report:progress` (Phase 10) — one per finalize pipeline step transition.
  Stream<ReportProgressEvent> get reportProgress => _reportProgressController.stream;

  /// `report:sealed` (Phase 10) — the finalize pipeline's terminal event.
  Stream<ReportSealedEvent> get reportSealed => _reportSealedController.stream;
  Stream<SessionErrorEvent> get errors => _errorController.stream;

  /// Connects to [baseUrl] and joins [sessionId] as [party] ('A' or 'B').
  void connect({required String sessionId, required String party}) {
    _sessionId = sessionId;
    _party = party;
    _connectionStateController.add(SocketConnectionState.connecting);

    // Forces websocket-only (skips the polling handshake): tested against
    // this backend, the default transport list (polling first, then
    // upgrade) never completes its initial handshake at all on either the
    // Android emulator or a physical device, while websocket-only connects
    // immediately on both. The actual cause of a since-fixed emulator
    // reconnect issue was two sockets briefly overlapping across the
    // create-session -> shell screen transition (see create_session_screen's
    // _advanceToShell), not the transport choice.
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _connectionStateController.add(SocketConnectionState.connected);
      _joinSession();
    });
    socket.onReconnectAttempt((_) => _connectionStateController.add(SocketConnectionState.connecting));
    socket.onDisconnect((_) => _connectionStateController.add(SocketConnectionState.disconnected));
    socket.onConnectError((_) => _connectionStateController.add(SocketConnectionState.disconnected));

    socket.on('session:state', (data) {
      _sessionStateController.add(SessionStateEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
    socket.on('party:status', (data) {
      _partyStatusController.add(PartyStatusEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
    socket.on('report:patched', (data) {
      _reportPatchedController.add(ReportPatchedEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
    socket.on('report:locked', (_) => _reportLockedController.add(null));
    socket.on('report:progress', (data) {
      _reportProgressController.add(ReportProgressEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
    socket.on('report:sealed', (data) {
      _reportSealedController.add(ReportSealedEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
    socket.on('session:error', (data) {
      _errorController.add(SessionErrorEvent.fromJson((data as Map).cast<String, dynamic>()));
    });
  }

  void _joinSession() {
    final sessionId = _sessionId;
    final party = _party;
    if (sessionId == null || party == null) return;
    _socket?.emit('session:join', {'sessionId': sessionId, 'party': party});
  }

  /// `path` is a dot-notation path into the caller's own party subtree (or
  /// a shared one) — see §5.3's patch rules. Not used until Phase 7's form
  /// screens exist to call it.
  void patch(String path, dynamic value) {
    _socket?.emit('report:patch', {'path': path, 'value': value});
  }

  /// Not used until a later phase's screens call it (see
  /// `.claude/rules/backend.md`: `party:ready` only flips the ready flag
  /// and rebroadcasts `party:status`, it doesn't advance session status).
  void ready(String stage) {
    final party = _party;
    if (party == null) return;
    _socket?.emit('party:ready', {'party': party, 'stage': stage});
  }

  void dispose() {
    _socket?.dispose();
    _connectionStateController.close();
    _sessionStateController.close();
    _partyStatusController.close();
    _reportPatchedController.close();
    _reportLockedController.close();
    _reportProgressController.close();
    _reportSealedController.close();
    _errorController.close();
  }
}
