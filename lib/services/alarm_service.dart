import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm_model.dart';

/// Wraps the `alarm` + `flutter_local_notifications` packages for the
/// SYNC alarm app.
///
/// On Android the `alarm` package schedules a notification at the
/// configured time and (on v3.1.0) lets the OS launch the app when the
/// user taps it. On iOS the local notification fires instead — iOS does
/// not allow true background alarm ringing.
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const String ringChannelId = 'sync_ring';
  static const String ringChannelName = 'SYNC Ring';
  static const String reminderChannelId = 'sync_reminder';
  static const String reminderChannelName = 'SYNC Reminder';
  static const String defaultChannelId = 'sync_default';
  static const String defaultChannelName = 'SYNC Default';

  /// Placeholder asset. Drop a real `alarm.mp3` at `assets/audio/alarm.mp3`
  /// and reference it here. The alarm package requires a non-empty
  /// `assetAudioPath` even when we only want the notification to ring.
  static const String defaultAudioAsset = 'assets/audio/alarm.mp3';

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
    const backgroundChannel = AndroidNotificationChannel(
      'sync_background',
      'SYNC Background',
      description: 'Keeps alarms and nudges active',
      importance: Importance.low,
      playSound: false,
    );
    await android.createNotificationChannel(ring);
    await android.createNotificationChannel(reminder);
    await android.createNotificationChannel(defaultChannel);
    await android.createNotificationChannel(backgroundChannel);
  }

  Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.scheduleExactAlarm.status;
    if (status.isGranted) return true;
    final result = await Permission.scheduleExactAlarm.request();
    return result.isGranted;
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

  /// Request exemption from battery optimizations (Doze mode).
  /// On OEMs like Xiaomi, Samsung, Huawei this is critical for
  /// background execution. The user sees a system dialog.
  Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Some devices don't support this permission — fail silently.
    }
  }

  Future<void> scheduleAlarm(AlarmModel alarm) async {
    await requestNotificationPermission();
    await requestExactAlarmPermission();
    await cancelAlarm(alarm.id);
    if (!alarm.isActive) return;
    if (alarm.daysOfWeek.isEmpty) {
      final id = _idFor(alarm.id, 0);
      final settings = AlarmSettings(
        id: id,
        dateTime: _nextInstanceOfTime(alarm.hour, alarm.minute),
        assetAudioPath: defaultAudioAsset,
        loopAudio: true,
        vibrate: alarm.vibrate,
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        volume: 1.0,
        notificationSettings: NotificationSettings(
          title: _encodeTitle(alarm),
          body: alarm.message,
          stopButton: 'DISMISS',
        ),
      );
      await Alarm.set(alarmSettings: settings);
    } else {
      await _scheduleWeekly(alarm);
    }
    await _scheduleBedtimeReminderIfApplicable(alarm);
  }

  DateTime _nextInstanceOfTime(int hour, int minute) {
    final now = DateTime.now();
    final scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      return scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> _scheduleWeekly(AlarmModel alarm) async {
    for (final day in alarm.daysOfWeek) {
      final id = _idFor(alarm.id, day);
      final settings = AlarmSettings(
        id: id,
        dateTime: _nextInstanceOf(alarm.hour, alarm.minute, day),
        assetAudioPath: defaultAudioAsset,
        loopAudio: true,
        vibrate: alarm.vibrate,
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        volume: 1.0,
        notificationSettings: NotificationSettings(
          title: _encodeTitle(alarm),
          body: alarm.message,
          stopButton: 'DISMISS',
        ),
      );
      await Alarm.set(alarmSettings: settings);
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
    await Alarm.stop(_idFor(alarmId, 0));
    for (var d = DateTime.monday; d <= DateTime.sunday; d += 1) {
      await Alarm.stop(_idFor(alarmId, d));
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
      assetAudioPath: defaultAudioAsset,
      loopAudio: true,
      vibrate: alarm.vibrate,
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
      volume: 1.0,
      notificationSettings: NotificationSettings(
        title: _encodeTitle(alarm),
        body: alarm.message,
        stopButton: 'DISMISS',
      ),
    );
    await Alarm.set(alarmSettings: settings);
  }

  Future<void> stopRinging() => Alarm.stopAll();

  // ---------------- Decoders ----------------

  /// Decode the alarm id out of a fired `AlarmSettings.notificationTitle`.
  String? decodeAlarmId(String title) {
    final parts = title.split('|');
    return parts.isNotEmpty ? parts.first : null;
  }

  String decodeLabel(String title) {
    final parts = title.split('|');
    return parts.length > 1 ? parts[1] : 'Alarm';
  }

  String decodeMessage(AlarmSettings settings) =>
      settings.notificationSettings.body;

  int decodeSnoozeMinutes(AlarmSettings settings, {int fallback = 5}) {
    try {
      final title = settings.notificationSettings.title;
      final parts = title.split('|');
      if (parts.length >= 3) {
        final minutes = int.tryParse(parts[2]);
        if (minutes != null && minutes > 0) return minutes;
      }
    } catch (_) {}
    return fallback;
  }

  // ---------------- Helpers ----------------

  int _idFor(String alarmId, int day) {
    final combined = '$alarmId-$day';
    final hash = combined.hashCode;
    // Stay within int32 positive range for platform APIs.
    return hash & 0x7FFFFFFF;
  }

  /// Encode the alarm id + label into the notification title so we can
  /// recover them when the alarm fires. The alarm package v3.x doesn't
  /// expose a `payload` field on AlarmSettings.
  String _encodeTitle(AlarmModel alarm) =>
      '${alarm.id}|${alarm.label.replaceAll('|', '_PIPE_')}|${alarm.snoozeMinutes}';

  DateTime _nextInstanceOf(int hour, int minute, int weekday) {
    final now = DateTime.now();
    final adjusted = DateTime(now.year, now.month, now.day, hour, minute);
    var diff = weekday - now.weekday;
    if (diff < 0 || (diff == 0 && adjusted.isBefore(now))) diff += 7;
    return adjusted.add(Duration(days: diff));
  }
}