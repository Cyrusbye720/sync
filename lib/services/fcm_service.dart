import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Firebase Cloud Messaging integration.
///
/// The service stores the device's FCM token on `profiles.fcm_token` so
/// the partner can push to it via `EdgeFunction nudge`.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] Firebase init failed: $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      _persistToken(token);
    });

    final initial = await messaging.getToken();
    if (initial != null) {
      await _persistToken(initial);
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        debugPrint('[FcmService] Foreground message: ${message.messageId}');
      }
      _handleData(message.data);
    });

    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
  }

  Future<void> _persistToken(String token) async {
    final userId = SupabaseService.instance.currentUserId;
    if (userId == null) return;
    try {
      await SupabaseService.instance.updateProfile(
        userId,
        {'fcm_token': token},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[FcmService] Persist token error: $e');
    }
  }

  void _handleData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (kDebugMode) debugPrint('[FcmService] data type: $type');
    if (type == 'alarm_sync' || type == 'nudge') {
      _syncEvents.add(data);
    }
  }

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get syncEvents => _controller.stream;

  void _syncEvents(Map<String, dynamic> data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _controller.close();
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // This handler runs in a separate isolate. Make sure Firebase is
  // initialized here even if the host isolate is cold-starting.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (kDebugMode) debugPrint('[FcmService] bg: ${message.messageId}');
}
