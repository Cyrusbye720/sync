/// Nudge event.
///
/// One row is inserted into `nudges` every time a user taps the
/// `WAKE THEM` button. The recipient's app subscribes to new rows via
/// Supabase Realtime while it is open and shows a full-screen overlay.
/// This is the in-app-only replacement for the FCM push that the
/// project used to send — fewer moving parts, no third-party push
/// dependencies, and no Firebase credentials to manage.
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