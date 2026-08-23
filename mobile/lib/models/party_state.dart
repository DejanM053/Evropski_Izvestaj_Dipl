/// Dart mirror of the embedded `PartyA`/`PartyB` sub-document on the backend
/// `Session` schema (docs/master_plan.md §5.1, `backend/src/models/Session.js`).
class PartyState {
  const PartyState({this.socketId, this.joinedAt, this.ready = false});

  final String? socketId;
  final DateTime? joinedAt;
  final bool ready;

  /// A non-null `socketId` means that party currently has a live socket
  /// joined to the session room (docs/master_plan.md §5.3 `session:join`).
  bool get isConnected => socketId != null;

  factory PartyState.fromJson(Map<String, dynamic> json) => PartyState(
        socketId: json['socketId'] as String?,
        joinedAt: json['joinedAt'] == null ? null : DateTime.parse(json['joinedAt'] as String),
        ready: json['ready'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'socketId': socketId,
        'joinedAt': joinedAt?.toIso8601String(),
        'ready': ready,
      };
}
