class AnnouncementModel {
  final dynamic id;
  final String title;
  final String body;
  final String type;
  final String target;
  final String? sentAt;
  final String? expiresAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.target,
    this.sentAt,
    this.expiresAt,
  });

  factory AnnouncementModel.fromMap(Map<String, dynamic> map) {
    return AnnouncementModel(
      id: map['id'],
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? 'info',
      target: map['target'] as String? ?? 'all',
      sentAt: map['sent_at'] as String?,
      expiresAt: map['expires_at'] as String?,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    try {
      return DateTime.parse(expiresAt!).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }
}
