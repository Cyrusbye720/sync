import 'package:flutter/material.dart';

/// Domain model for the Supabase `profiles` table.
@immutable
class ProfileModel {
  final String id;
  final String username;
  final String? avatarUrl;
  final String? fcmToken;
  final String timezone;
  final String sleepStatus;
  final int batteryPercent;
  final DateTime createdAt;

  const ProfileModel({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.fcmToken,
    required this.timezone,
    required this.sleepStatus,
    required this.batteryPercent,
    required this.createdAt,
  });

  static const String awake = 'awake';
  static const String asleep = 'asleep';

  bool get isAwake => sleepStatus == awake;
  bool get isAsleep => sleepStatus == asleep;

  bool get isLowBattery => batteryPercent < 20;

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      username: (map['username'] as String?) ?? 'user',
      avatarUrl: map['avatar_url'] as String?,
      fcmToken: map['fcm_token'] as String?,
      timezone: (map['timezone'] as String?) ?? 'UTC',
      sleepStatus: (map['sleep_status'] as String?) ?? awake,
      batteryPercent: (map['battery_percent'] as int?) ?? 100,
      createdAt: DateTime.parse(
          (map['created_at'] as String?) ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
      'fcm_token': fcmToken,
      'timezone': timezone,
      'sleep_status': sleepStatus,
      'battery_percent': batteryPercent,
    };
  }

  ProfileModel copyWith({
    String? username,
    String? avatarUrl,
    String? fcmToken,
    String? timezone,
    String? sleepStatus,
    int? batteryPercent,
  }) {
    return ProfileModel(
      id: id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      fcmToken: fcmToken ?? this.fcmToken,
      timezone: timezone ?? this.timezone,
      sleepStatus: sleepStatus ?? this.sleepStatus,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      createdAt: createdAt,
    );
  }
}
