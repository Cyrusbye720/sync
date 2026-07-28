import 'package:flutter/material.dart';

/// Domain model for the Supabase `alarm_logs` table.
///
/// One row per fired-alarm action. `reaction` is set after dismiss from
/// the ring screen.
@immutable
class AlarmLogModel {
  final String id;
  final String alarmId;
  final String action;
  final String? reaction;
  final String? actedBy;
  final DateTime createdAt;

  const AlarmLogModel({
    required this.id,
    required this.alarmId,
    required this.action,
    required this.reaction,
    required this.actedBy,
    required this.createdAt,
  });

  static const String fired = 'fired';
  static const String snoozed = 'snoozed';
  static const String dismissed = 'dismissed';

  factory AlarmLogModel.fromMap(Map<String, dynamic> map) {
    return AlarmLogModel(
      id: map['id'] as String,
      alarmId: (map['alarm_id'] as String?) ?? '',
      action: (map['action'] as String?) ?? fired,
      reaction: map['reaction'] as String?,
      actedBy: map['acted_by'] as String?,
      createdAt: DateTime.parse(
          (map['created_at'] as String?) ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'alarm_id': alarmId,
      'action': action,
      'reaction': reaction,
      'acted_by': actedBy,
    };
  }
}
