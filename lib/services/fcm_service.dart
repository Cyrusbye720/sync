import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Show a local notification for a received FCM nudge. Used by the
/// background handler (which can't rely on the system tray) and the
/// foreground handler (so the user sees the nudge even with the app open).
Future<void> _showNudgeNotification(Map<String, dynamic> data) async {
  try {
    final title = (data['title'] as String?) ?? 'NUDGE';
    final body = (data['body'] as String?) ?? 'Your partner is trying to wake you up!';
    final fromUserName = (data['from_user_name'] as String?) ?? 'YOUR PARTNER';

    final local = FlutterLocalNotificationsPlugin();
    // No-op if already initialized — safe to call from any isolate.
    try {
      await local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      'sync_default',
      'SYNC Default',
      channelDescription: 'Nudge alerts from your partner',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: 'Wake up!',
    );

    await local.show(
      1001,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: fromUserName,
    );
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FCM] local notification failed: $e');
    }
  }
}

/// Schedule an alarm locally from FCM data payload.
/// Called from both the background handler and the foreground handler.
Future<void> _scheduleAlarmFromFcm(Map<String, dynamic> data) async {
  try {
    final alarmId = data['alarm_id'] as String?;
    final hour = int.tryParse(data['hour']?.toString() ?? '');
    final minute = int.tryParse(data['minute']?.toString() ?? '');
    if (alarmId == null || hour == null || minute == null) return;

    final label = (data['label'] as String?) ?? 'Alarm';
    final message = (data['message'] as String?) ?? 'Wake up!';
    final vibrate = data['vibrate']?.toString() != 'false';
    final snoozeMinutes = int.tryParse(data['snooze_minutes']?.toString() ?? '') ?? 5;

    List<int> daysOfWeek = [];
    try {
      final raw = data['days_of_week'];
      if (raw is String) {
        daysOfWeek = (List<dynamic>.from(
            (raw.startsWith('[') ? (const JsonDecoder().convert(raw) as List) : []) as List))
            .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
            .where((d) => d > 0)
            .toList();
      } else if (raw is List) {
        daysOfWeek = raw.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
            .where((d) => d > 0)
            .toList();
      }
    } catch (_) {}

    // Initialize alarm plugin (safe to call from any isolate).
    try { await Alarm.init(); } catch (_) {}

    DateTime scheduled;
    if (daysOfWeek.isEmpty) {
      final now = DateTime.now();
      scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    } else {
      // For weekly alarms, schedule the nearest upcoming day.
      final now = DateTime.now();
      scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      var bestDiff = 8;
      for (final day in daysOfWeek) {
        var diff = day - now.weekday;
        if (diff < 0 || (diff == 0 && scheduled.isBefore(now))) diff += 7;
        if (diff < bestDiff) bestDiff = diff;
      }
      if (bestDiff < 8) scheduled = scheduled.add(Duration(days: bestDiff));
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }

    final settings = AlarmSettings(
      id: alarmId.hashCode & 0x7FFFFFFF,
      dateTime: scheduled,
      assetAudioPath: 'assets/audio/alarm.mp3',
      loopAudio: true,
      vibrate: vibrate,
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
      volume: 1.0,
      notificationSettings: NotificationSettings(
        title: '$alarmId|$label|$snoozeMinutes',
        body: message,
        stopButton: 'DISMISS',
      ),
    );
    await Alarm.set(alarmSettings: settings);

    if (kDebugMode) debugPrint('[FcmService] Alarm scheduled: $alarmId at $scheduled');
  } catch (e) {
    if (kDebugMode) debugPrint('[FcmService] _scheduleAlarmFromFcm failed: $e');
  }
}

/// Cancel a local alarm from FCM delete event.
Future<void> _cancelAlarmFromFcm(Map<String, dynamic> data) async {
  try {
    final alarmId = data['alarm_id'] as String?;
    if (alarmId == null) return;
    try { await Alarm.init(); } catch (_) {}
    await Alarm.stop(alarmId.hashCode & 0x7FFFFFFF);
    // Also stop any day-specific variants.
    for (var d = 1; d <= 7; d++) {
      await Alarm.stop(('$alarmId-$d').hashCode & 0x7FFFFFFF);
    }
    if (kDebugMode) debugPrint('[FcmService] Alarm cancelled: $alarmId');
  } catch (e) {
    if (kDebugMode) debugPrint('[FcmService] _cancelAlarmFromFcm failed: $e');
  }
}

/// Background isolate entry point. Must be a top-level function and
/// annotated with @pragma so the Dart compiler doesn't tree-shake it.
/// Runs in a separate isolate; do not call into Riverpod providers
/// from here — those live in the main isolate.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (kDebugMode) {
    // ignore: avoid_print
    print('[FCM background] ${message.messageId} ${message.data}');
  }
  final type = message.data['type'] as String?;
  if (type == 'alarm') {
    final action = message.data['action'] as String?;
    if (action == 'delete') {
      await _cancelAlarmFromFcm(message.data);
    } else {
      await _scheduleAlarmFromFcm(message.data);
    }
    // Also show a local notification so the user knows an alarm was set/changed.
    await _showAlarmNotification(message.data);
  } else {
    // Show a local notification ourselves. The Worker sends data-only
    // FCM messages so the system tray doesn't auto-display anything.
    await _showNudgeNotification(message.data);
  }
}

/// Show a local notification for alarm FCM events.
Future<void> _showAlarmNotification(Map<String, dynamic> data) async {
  try {
    final action = data['action'] as String? ?? 'create';
    final label = data['label'] as String? ?? 'Alarm';
    final hour = data['hour']?.toString() ?? '?';
    final minute = data['minute']?.toString() ?? '?';

    String title;
    String body;
    if (action == 'delete') {
      title = 'Alarm Removed';
      body = 'Your partner removed "$label".';
    } else {
      title = 'New Alarm Set';
      body = 'Your partner set "$label" at ${hour.padLeft(2, '0')}:${minute.padLeft(2, '0')}';
    }

    final local = FlutterLocalNotificationsPlugin();
    try {
      await local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      'sync_default',
      'SYNC Default',
      channelDescription: 'Alarm alerts from your partner',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    await local.show(
      1002,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[FcmService] alarm notification failed: $e');
  }
}

/// Single owner of Firebase Cloud Messaging wiring.
///
/// Responsibilities:
///   1. Initialise Firebase + the messaging plugin.
///   2. Ask for notification permission on Android 13+ / iOS.
///   3. Get the device FCM token and save it on the server via
///      the Worker API so the Worker can target it for nudge pushes.
///   4. Listen for foreground message events and re-emit them on
///      [syncEvents] so the rest of the app can react (push the
///      IncomingNudgeScreen if needed).
///   5. Wire the background isolate handler before init so the OS
///      doesn't silently drop messages on cold start.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  /// Default channel used by the system tray when the OS displays a
  /// notification that wasn't suppressed by Flutter. Set in the
  /// manifest as `default_notification_channel_id`; created at
  /// runtime by `AlarmService._ensureAndroidChannels`.
  static const String defaultChannelId = 'sync_default';

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcast stream of foreground + tap-launched FCM message
  /// payloads. Payload is `message.data` (a `Map<String, dynamic>`).
  Stream<Map<String, dynamic>> get syncEvents => _events.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Must be registered before any other FCM call.
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // Firebase auto-configures from google-services.json (Android)
      // or GoogleService-Info.plist (iOS) — no explicit options needed.
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      await _persistToken(token);

      // React to OS-issued token rotations (rare but real).
      FirebaseMessaging.instance.onTokenRefresh.listen(_persistToken);

      // Foreground messages.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Background notification taps (app in memory but not foreground).
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _events.add(message.data);
      });
    } catch (e, stack) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FcmService] FCM initialization failed: $e\n$stack');
      }
    }
  }

  /// If the user launched the app by tapping a system-tray FCM
  /// notification, expose that payload through [syncEvents] so the
  /// nudge UI can react. Call once from the root widget's initState.
  Future<void> replayInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _events.add(initial.data);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FcmService] replayInitialMessage failed: $e');
      }
    }
  }

  Future<void> refreshFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      await _persistToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] refreshFcmToken error: $e');
    }
  }

  Future<void> _persistToken(String? token) async {
    if (token == null) return;
    final userId = ApiService.instance.currentUserId;
    if (userId == null) return;
    try {
      await ApiService.instance.updateProfile(userId, {
        'fcm_token': token,
      });
      if (kDebugMode) debugPrint('[FcmService] FCM token saved for $userId: $token');
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] FCM token update failed: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (type == 'alarm') {
      final action = message.data['action'] as String?;
      if (action == 'delete') {
        _cancelAlarmFromFcm(message.data);
      } else {
        _scheduleAlarmFromFcm(message.data);
      }
      _showAlarmNotification(message.data);
    } else if (type == 'nudge') {
      // Show a local notification so the user sees the nudge even
      // when the app is in the foreground.
      _showNudgeNotification(message.data);
    }
    _events.add(message.data);
  }

  /// Schedule an alarm locally from FCM data (public API for main.dart replay).
  static Future<void> scheduleAlarmFromFcm(Map<String, dynamic> data) =>
      _scheduleAlarmFromFcm(data);

  /// Cancel a local alarm from FCM data (public API for main.dart replay).
  static Future<void> cancelAlarmFromFcm(Map<String, dynamic> data) =>
      _cancelAlarmFromFcm(data);

  /// Reconstruct a [NudgeModel]-compatible map from FCM data payload.
  /// The Worker sends: type, nudge_id, from_user, from_user_name, created_at.
  /// Returns null if the data is not a nudge or is missing required fields.
  static Map<String, dynamic>? parseNudgeFromFcmData(Map<String, dynamic> data) {
    if (data['type'] != 'nudge') return null;
    final nudgeId = data['nudge_id'] as String?;
    final fromUser = data['from_user'] as String?;
    final createdAt = data['created_at'] as String?;
    if (nudgeId == null || fromUser == null || createdAt == null) return null;
    return {
      'id': nudgeId,
      'from_user': fromUser,
      'to_user': '', // not needed for display; IncomingNudgeScreen uses partner from pairing
      'created_at': createdAt,
      'read_at': null,
    };
  }
}
