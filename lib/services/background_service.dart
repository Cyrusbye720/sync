import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Manages the foreground service that keeps the app alive in the background.
///
/// The service shows a persistent notification which prevents Android from
/// killing the process. This keeps the WebSocket connection alive and
/// ensures nudge FCM messages are processed promptly.
class BackgroundService {
  BackgroundService._();

  static final BackgroundService instance = BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Whether the service is currently running.
  bool _running = false;

  /// Start the foreground service. Call after login.
  Future<void> start() async {
    if (_running) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'sync_background',
        initialNotificationTitle: 'SYNC',
        initialNotificationContent: 'Alarms & nudges active',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
      ),
    );

    await _service.startService();
    _running = true;
  }

  /// Stop the foreground service. Call on logout.
  Future<void> stop() async {
    if (!_running) return;
    _service.invoke('stop');
    _running = false;
  }
}

/// Entry point for the background isolate.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    // Periodically update the notification to show liveness.
    Future<void>.delayed(const Duration(minutes: 10), () async {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'SYNC',
          content: 'Alarms & nudges active',
        );
      }
    });
  }

  service.on('stop').listen((_) {
    service.stopSelf();
  });
}
