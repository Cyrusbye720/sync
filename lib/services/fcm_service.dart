import 'dart:async';

import 'push_provider.dart';

/// Compatibility facade for the former FCM implementation.
///
/// Google/Firebase has been removed from the Flutter build. This facade keeps
/// existing call sites stable while LocalPushProvider explicitly documents that
/// remote nudges and alarm changes are delivered only by the app/WebSocket path
/// while open/native push integration is not configured.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();
  static const String defaultChannelId = 'sync_default';
  PushProvider _provider = LocalPushProvider.instance;

  Stream<Map<String, dynamic>> get syncEvents => _provider.events;

  Future<void> initialize() async {
    await _provider.initialize();
  }

  Future<void> replayInitialMessage() async {
    await _provider.replayInitialMessage();
  }

  Future<void> refreshFcmToken() async {
    await _provider.refreshToken();
  }

  static Future<void> scheduleAlarmFromFcm(Map<String, dynamic> data) async {}

  static Future<void> cancelAlarmFromFcm(Map<String, dynamic> data) async {}

  static Map<String, dynamic>? parseNudgeFromFcmData(
    Map<String, dynamic> data,
  ) {
    return data;
  }
}
