import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

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
    _events.add(message.data);
  }
}
