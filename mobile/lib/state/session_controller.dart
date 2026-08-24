import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/report_model.dart';
import '../models/session_model.dart';
import '../services/socket_client.dart';

/// Owns the live Socket.IO connection for one session and exposes the
/// latest known session/report snapshot plus each party's connectivity.
/// Created per session (by `SessionShellScreen`) and disposed when the
/// shell is left. Phases 7+ can `watch`/`read` this same controller from
/// nested screens to send `report:patch`/`party:ready` and to react to
/// `report:patched` — none of that is wired up yet since no screen needs it
/// this phase.
class SessionController extends ChangeNotifier {
  SessionController({
    required String baseUrl,
    required this.sessionId,
    required this.sessionCode,
    required this.selfParty,
  }) : _socket = SocketClient(baseUrl: baseUrl) {
    _connectionSub = _socket.connectionState.listen(_onConnectionState);
    _sessionStateSub = _socket.sessionState.listen(_onSessionState);
    _partyStatusSub = _socket.partyStatus.listen(_onPartyStatus);
    _reportPatchedSub = _socket.reportPatched.listen(_onReportPatched);
    _errorSub = _socket.errors.listen(_onError);
    _socket.connect(sessionId: sessionId, party: selfParty);
  }

  final String sessionId;
  final String sessionCode;

  /// `'A'` or `'B'` — which party this device is in the session.
  final String selfParty;

  final SocketClient _socket;

  late final StreamSubscription<SocketConnectionState> _connectionSub;
  late final StreamSubscription<SessionStateEvent> _sessionStateSub;
  late final StreamSubscription<PartyStatusEvent> _partyStatusSub;
  late final StreamSubscription<ReportPatchedEvent> _reportPatchedSub;
  late final StreamSubscription<SessionErrorEvent> _errorSub;

  SocketConnectionState connectionState = SocketConnectionState.connecting;
  SessionModel? session;
  ReportModel? report;
  bool otherPartyConnected = false;
  String? otherPartyStage;
  bool otherPartyReady = false;
  SessionErrorEvent? lastError;

  /// The most recent applied `report:patched` event, exposed so screens can
  /// tell *which* field just changed (e.g. to skip re-syncing a field the
  /// user is actively typing into) rather than only knowing that the report
  /// as a whole changed.
  ReportPatchedEvent? lastPatch;

  String get otherParty => selfParty == 'A' ? 'B' : 'A';

  void _onConnectionState(SocketConnectionState state) {
    connectionState = state;
    notifyListeners();
  }

  void _onSessionState(SessionStateEvent event) {
    session = event.session;
    report = event.report;
    if (event.session.partyFor(otherParty).isConnected) {
      otherPartyConnected = true;
    }
    notifyListeners();
  }

  void _onPartyStatus(PartyStatusEvent event) {
    if (event.party == otherParty) {
      otherPartyConnected = true;
      otherPartyStage = event.stage;
      otherPartyReady = event.ready;
    }
    notifyListeners();
  }

  void _onError(SessionErrorEvent event) {
    lastError = event;
    notifyListeners();
  }

  // Applies every broadcast patch (including the sender's own echoed-back
  // patch, per .claude/rules/backend.md) onto the local report snapshot.
  // Screens decide for themselves whether to actually pull the new value
  // into a given field (see PatchTextField) — this only keeps `report`
  // itself the source of truth.
  void _onReportPatched(ReportPatchedEvent event) {
    final current = report;
    if (current != null) report = current.applyPatch(event.path, event.value);
    lastPatch = event;
    notifyListeners();
  }

  void sendReady(String stage) => _socket.ready(stage);

  void sendPatch(String path, dynamic value) => _socket.patch(path, value);

  @override
  void dispose() {
    _connectionSub.cancel();
    _sessionStateSub.cancel();
    _partyStatusSub.cancel();
    _reportPatchedSub.cancel();
    _errorSub.cancel();
    _socket.dispose();
    super.dispose();
  }
}
