/// Nudge event.
///
/// One row is inserted into `nudges` every time a user taps the
/// `WAKE THEM` button. The Worker broadcasts new rows over WebSocket while
/// the app is open and reconciliation polling recovers missed deliveries.
class NudgeModel {
  final String id;
  final String fromUser;
  final String toUser;
  final DateTime createdAt;
  final DateTime? readAt;

  const NudgeModel({
    required this.id,
    required this.fromUser,
    required this.toUser,
    required this.createdAt,
    this.readAt,
  });

  factory NudgeModel.fromMap(Map<String, dynamic> m) => NudgeModel(
        id: m['id'] as String,
        fromUser: m['from_user'] as String,
        toUser: m['to_user'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toUtc(),
      );
}