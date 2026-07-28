import 'package:flutter/material.dart';

/// Domain model mirroring the Supabase `alarms` table.
///
/// The full schema is in `supabase/init.sql`. `weekdays` is stored as a
/// Postgres `int[]` of 1..7 (Mon..Sun) — this matches what `intl` and
/// `DateTime.weekday` return.
@immutable
class AlarmModel {
  final String id;
  final String ownerId;
  final String createdBy;
  final String label;
  final String message;
  final int hour;
  final int minute;
  final List<int> daysOfWeek;
  final bool isActive;
  final bool vibrate;
  final String soundName;
  final int snoozeMinutes;
  final DateTime createdAt;

  const AlarmModel({
    required this.id,
    required this.ownerId,
    required this.createdBy,
    required this.label,
    required this.message,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.isActive,
    required this.vibrate,
    required this.soundName,
    required this.snoozeMinutes,
    required this.createdAt,
  });

  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    final rawDays = map['days_of_week'];
    final days = <int>[];
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is int) {
          days.add(d);
        } else if (d is num) {
          days.add(d.toInt());
        }
      }
    }
    return AlarmModel(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      createdBy: map['created_by'] as String,
      label: (map['label'] as String?) ?? 'Alarm',
      message: (map['message'] as String?) ?? 'Wake up!',
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      daysOfWeek: days,
      isActive: (map['is_active'] as bool?) ?? true,
      vibrate: (map['vibrate'] as bool?) ?? true,
      soundName: (map['sound_name'] as String?) ?? 'default',
      snoozeMinutes: (map['snooze_minutes'] as int?) ?? 5,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap({required String createdByLocal}) {
    return <String, dynamic>{
      'owner_id': ownerId,
      'created_by': createdByLocal,
      'label': label,
      'message': message,
      'hour': hour,
      'minute': minute,
      'days_of_week': daysOfWeek,
      'is_active': isActive,
      'vibrate': vibrate,
      'sound_name': soundName,
      'snooze_minutes': snoozeMinutes,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return <String, dynamic>{
      'label': label,
      'message': message,
      'hour': hour,
      'minute': minute,
      'days_of_week': daysOfWeek,
      'is_active': isActive,
      'vibrate': vibrate,
      'sound_name': soundName,
      'snooze_minutes': snoozeMinutes,
    };
  }

  String formattedTime() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// True if the alarm fires every day (no days selected means once-only).
  bool get isEveryDay => daysOfWeek.length == 7;

  bool get isOneShot => daysOfWeek.isEmpty;

  AlarmModel copyWith({
    String? id,
    String? ownerId,
    String? createdBy,
    String? label,
    String? message,
    int? hour,
    int? minute,
    List<int>? daysOfWeek,
    bool? isActive,
    bool? vibrate,
    String? soundName,
    int? snoozeMinutes,
    DateTime? createdAt,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      createdBy: createdBy ?? this.createdBy,
      label: label ?? this.label,
      message: message ?? this.message,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      isActive: isActive ?? this.isActive,
      vibrate: vibrate ?? this.vibrate,
      soundName: soundName ?? this.soundName,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
