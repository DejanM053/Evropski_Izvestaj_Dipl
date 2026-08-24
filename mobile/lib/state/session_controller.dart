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
    _reportLockedSub = _socket.reportLocked.listen((_) => _onReportLocked());
    _reportProgressSub = _socket.reportProgress.listen(_onReportProgress);
    _reportSealedSub = _socket.reportSealed.listen(_onReportSealed);
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
  late final StreamSubscription<void> _reportLockedSub;
  late final StreamSubscription<ReportProgressEvent> _reportProgressSub;
  late final StreamSubscription<ReportSealedEvent> _reportSealedSub;
  late final StreamSubscription<SessionErrorEvent> _errorSub;

  SocketConnectionState connectionState = SocketConnectionState.connecting;
  SessionModel? session;
  ReportModel? report;
  bool otherPartyConnected = false;
  String? otherPartyStage;
  bool otherPartyReady = false;
  SessionErrorEvent? lastError;

  /// True once the report can no longer be edited — either derived from a
  /// `session:state` snapshot whose status is already `signing` or later
  /// (§5.3 `LOCKED_STATUSES`, e.g. after a reconnect), or set immediately by
  /// a live `report:locked` event (Phase 8: both parties confirmed review
  /// and signed). Screens use this single flag to hide/disable every edit
  /// affordance — see `SessionShellScreen`'s read-only overlay.
  bool isLocked = false;

  /// The most recent applied `report:patched` event, exposed so screens can
  /// tell *which* field just changed (e.g. to skip re-syncing a field the
  /// user is actively typing into) rather than only knowing that the report
  /// as a whole changed.
  ReportPatchedEvent? lastPatch;

  /// Phase 10: `finalize step key -> 'active'|'done'|'error'`, built up from
  /// every `report:progress` event seen live over this socket. Deliberately
  /// *not* the sole source of truth for FinalizingScreen's step list — a
  /// client that (re)connects mid-pipeline won't have seen the earlier
  /// events, so screens should cross-check against `report`'s own persisted
  /// fields (`pdfFileId`, `chain.txHash`, `chain.lastError`) wherever a
  /// ground-truth field exists, and use this map only for liveliness
  /// (spinner vs static) and in-flight detail (short SHA, progress bar).
  Map<String, String> finalizeStepStatus = {};

  /// The most recent finalize error message, from either a live
  /// `report:progress` `status: "error"` event or (after a reconnect)
  /// `report.chain.lastError`. FinalizingScreen prefers this live value but
  /// falls back to the persisted one — see `_onReportProgress`.
  String? finalizeErrorMessage;

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
    if (kLockedSessionStatuses.contains(event.session.status)) {
      isLocked = true;
    }
    notifyListeners();
  }

  void _onReportLocked() {
    isLocked = true;
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

  void _onReportProgress(ReportProgressEvent event) {
    finalizeStepStatus = {...finalizeStepStatus, event.step: event.status};
    if (event.status == 'error') {
      finalizeErrorMessage = event.error;
    } else if (event.step == 'anchor' && event.status == 'active') {
      // A fresh anchor attempt starting (e.g. after a manual retry) — clear
      // any stale error from the previous attempt rather than leaving it
      // displayed underneath a now-spinning step.
      finalizeErrorMessage = null;
    }
    notifyListeners();
  }

  // Merges the terminal event's fields onto the local report snapshot for
  // whichever client *didn't* make the POST that completed the pipeline
  // (that caller instead adopts the full response body directly — see
  // `adoptReport`). Applied as individual dot-path patches, same mechanism
  // `report:patched` already uses, so this stays correct if more fields are
  // ever added to ReportModel without needing a hand-written merge here.
  void _onReportSealed(ReportSealedEvent event) {
    final current = report;
    if (current != null) {
      var updated = current.applyPatch('status', 'sealed');
      updated = updated.applyPatch('pdf.fileId', event.pdfFileId);
      updated = updated.applyPatch('chain.txHash', event.txHash);
      updated = updated.applyPatch('chain.blockNumber', event.blockNumber);
      updated = updated.applyPatch('chain.contractAddress', event.contractAddress);
      updated = updated.applyPatch('chain.network', event.network);
      updated = updated.applyPatch('chain.anchoredAt', event.anchoredAt?.toIso8601String());
      report = updated;
    }
    notifyListeners();
  }

  void sendReady(String stage) => _socket.ready(stage);

  void sendPatch(String path, dynamic value) => _socket.patch(path, value);

  /// Wholesale-replaces the local report snapshot with one read straight
  /// from a REST response (`ApiClient.finalizeReport`'s 200 body) — used by
  /// whichever client's own `POST /finalize` call is the one that actually
  /// completed (or found the report already sealed), so it doesn't have to
  /// wait for its own broadcast to come back over the socket.
  void adoptReport(ReportModel updated) {
    report = updated;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    _sessionStateSub.cancel();
    _partyStatusSub.cancel();
    _reportPatchedSub.cancel();
    _reportLockedSub.cancel();
    _reportProgressSub.cancel();
    _reportSealedSub.cancel();
    _errorSub.cancel();
    _socket.dispose();
    super.dispose();
  }
}
