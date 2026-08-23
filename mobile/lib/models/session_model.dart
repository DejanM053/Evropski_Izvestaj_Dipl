import 'party_state.dart';

/// Mirrors `backend/src/models/statuses.js` `STATUSES`. Kept as plain
/// strings (not a Dart enum) since the client only ever compares/forwards
/// this value — it never needs to switch on every case, and a raw string
/// survives a backend adding a new status without a client rebuild.
const List<String> kSessionStatuses = [
  'waiting',
  'joined',
  'filling',
  'review',
  'signing',
  'finalizing',
  'sealed',
  'abandoned',
];

/// Dart mirror of the backend `Session` document (docs/master_plan.md §5.1,
/// `backend/src/models/Session.js`) — the ephemeral coordination object a
/// session's two parties join.
class SessionModel {
  const SessionModel({
    required this.id,
    required this.sessionCode,
    required this.status,
    required this.partyA,
    required this.partyB,
    this.reportId,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String sessionCode;
  final String status;
  final PartyState partyA;
  final PartyState partyB;
  final String? reportId;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// `'A'` or `'B'` -> that party's [PartyState].
  PartyState partyFor(String party) => party == 'A' ? partyA : partyB;

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
        id: json['_id'] as String,
        sessionCode: json['sessionCode'] as String,
        status: json['status'] as String? ?? 'waiting',
        partyA: PartyState.fromJson((json['partyA'] as Map?)?.cast<String, dynamic>() ?? const {}),
        partyB: PartyState.fromJson((json['partyB'] as Map?)?.cast<String, dynamic>() ?? const {}),
        reportId: json['reportId'] as String?,
        createdAt: json['createdAt'] == null ? null : DateTime.parse(json['createdAt'] as String),
        expiresAt: json['expiresAt'] == null ? null : DateTime.parse(json['expiresAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'sessionCode': sessionCode,
        'status': status,
        'partyA': partyA.toJson(),
        'partyB': partyB.toJson(),
        'reportId': reportId,
        'createdAt': createdAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };
}
