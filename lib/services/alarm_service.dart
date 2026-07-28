import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm_model.dart';

/// Wraps the `alarm` + `flutter_local_notifications` packages.
///
/// - On Android: schedules a true exact alarm with the OS that rings a
///   full-screen activity when the alarm fires.
/// - On iOS: schedules a critical local notification at the same time as
///   a fallback (iOS does not support background alarm ringing).
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const String ringChannelId = 'sync_ring';
  static const String ringChannelName = 'SYNC Ring';
  static const String reminderChannelId = 'sync_reminder';
  static const String reminderChannelName = 'SYNC Reminder';
  static const String defaultChannelId = 'sync_default';
  static const String defaultChannelName = 'SYNC Default';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _ensureAndroidChannels();
    await Alarm.init();
  }

  Future<void> _ensureAndroidChannels() async {
    final android = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const ring = AndroidNotificationChannel(
      ringChannelId,
      ringChannelName,
      description: 'Ring alarms',
      importance: Importance.max,
      playSound: true,
    );
    const reminder = AndroidNotificationChannel(
      reminderChannelId,
      reminderChannelName,
      description: 'Bedtime reminders',
      importance: Importance.high,
      playSound: false,
    );
    const defaultChannel = AndroidNotificationChannel(
      defaultChannelId,
      defaultChannelName,
      description: 'Generic FCM messages',
      importance: Importance.high,
      playSound: false,
    );
    await android.createNotificationChannel(ring);
    await android.createNotificationChannel(reminder);
    await android.createNotificationChannel(defaultChannel);
  }

  Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.scheduleExactAlarm.status;
    if (status.isGranted) return true;
    final result = await Permission.scheduleExactAlarm.request();
    if (!result.isGranted) return false;
    // Some OEM builds — request USE_EXACT_ALARM as well.
    await Permission.requestExactAlarm.request();
    return true;
  }

  Future<void> requestNotificationPermission() async {
    await Permission.notification.request();
    if (Platform.isIOS) {
      final ios = _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> scheduleAlarm(AlarmModel alarm) async {
    await cancelAlarm(alarm.id);
    if (!alarm.isActive) return;
    if (alarm.daysOfWeek.isEmpty) return;
    await _scheduleWeekly(alarm);
    await _scheduleBedtimeReminderIfApplicable(alarm);
  }

  Future<void> _scheduleWeekly(AlarmModel alarm) async {
    for (final day in alarm.daysOfWeek) {
      final id = _idFor(alarm.id, day);
      final settings = AlarmSettings(
        id: id,
        dateTime: _nextInstanceOf(alarm.hour, alarm.minute, day),
        loopAudio: true,
        vibrate: alarm.vibrate,
        volumeMax: true,
        notificationTitle: alarm.label,
        notificationBody: alarm.message,
        fullScreen: true,
        allowWhileIdle: true,
        androidFullScreenIntent: true,
        payload: _payload(alarm),
      );
      await Alarm.set(settings: settings);
    }
  }

  Future<void> _scheduleBedtimeReminderIfApplicable(AlarmModel alarm) async {
    if (alarm.daysOfWeek.isEmpty) return;
    final now = DateTime.now();
    final fireAt =
        DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
    final delta = fireAt.difference(now);

    DateTime reminderAt;
    if (delta.inHours > 8 || delta.isNegative) {
      final tomorrow = fireAt.add(const Duration(days: 1));
      if (tomorrow.difference(now).inHours > 8) return;
      reminderAt = tomorrow.subtract(const Duration(hours: 8));
    } else {
      reminderAt = fireAt.subtract(const Duration(hours: 8));
    }

    final tzWhen = tz.TZDateTime.from(reminderAt, tz.local);
    const androidDetails = AndroidNotificationDetails(
      reminderChannelId,
      reminderChannelName,
      channelDescription: 'Bedtime reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _local.zonedSchedule(
      _idFor('reminder-${alarm.id}', 0),
      'Bedtime',
      'Alarm at ${alarm.formattedTime()} — consider sleeping now.',
      tzWhen,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAlarm(String alarmId) async {
    for (var d = DateTime.monday; d <= DateTime.sunday; d += 1) {
      await Alarm.cancel(_idFor(alarmId, d));
    }
    await _local.cancel(_idFor('reminder-$alarmId', 0));
  }

  /// Snoozes the currently ringing alarm by `snoozeMinutes`.
  Future<void> snoozeAlarm(AlarmModel alarm) async {
    final now = DateTime.now();
    final snoozeAt = now.add(Duration(minutes: alarm.snoozeMinutes));
    final settings = AlarmSettings(
      id: _idFor('snooze-${alarm.id}', now.minute),
      dateTime: snoozeAt,
      loopAudio: true,
      vibrate: alarm.vibrate,
      volumeMax: true,
      notificationTitle: alarm.label,
      notificationBody: alarm.message,
      fullScreen: true,
      allowWhileIdle: true,
      androidFullScreenIntent: true,
      payload: _payload(alarm),
    );
    await Alarm.set(settings: settings);
  }

  Future<void> stopRinging() => Alarm.stopAll();

  // ---------------- Payload decoders ----------------

  String? decodeAlarmId(String payload) {
    final match = RegExp(r'alarm:([^|]+)').firstMatch(payload);
    return match?.group(1);
  }

  String decodeLabel(String payload) {
    final match = RegExp(r'label:([^|]+)').firstMatch(payload);
    return (match?.group(1) ?? 'Alarm').replaceAll('_PIPE_', '|');
  }

  String decodeMessage(String payload) {
    final match = RegExp(r'message:([^|]+)').firstMatch(payload);
    return (match?.group(1) ?? 'Wake up!').replaceAll('_PIPE_', '|');
  }

  int decodeSnoozeMinutes(String payload, {int fallback = 5}) {
    final match = RegExp(r'snooze:(\d+)').firstMatch(payload);
    if (match == null) return fallback;
    return int.tryParse(match.group(1) ?? '') ?? fallback;
  }

  // ---------------- Helpers ----------------

  int _idFor(String alarmId, int day) {
    final combined = '$alarmId-$day';
    final hash = combined.hashCode;
    // Stay within int32 positive range for platform APIs.
    return hash & 0x7FFFFFFF;
  }

  String _payload(AlarmModel alarm) =>
      'alarm:${alarm.id}|label:${alarm.label.replaceAll('|', '_PIPE_')}|'
      'message:${alarm.message.replaceAll('|', '_PIPE_')}|'
      'snooze:${alarm.snoozeMinutes}|vibrate:${alarm.vibrate}';

  DateTime _nextInstanceOf(int hour, int minute, int weekday) {
    final now = DateTime.now();
    final adjusted = DateTime(now.year, now.month, now.day, hour, minute);
    var diff = weekday - now.weekday;
    if (diff < 0 || (diff == 0 && adjusted.isBefore(now))) diff += 7;
    return adjusted.add(Duration(days: diff));
  }
}
