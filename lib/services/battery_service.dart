import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// Reads battery level periodically and exposes it as a stream.
///
/// Updated every 15 minutes while the app is alive. The widget tree
/// pushes the current value to Supabase (`profiles.battery_percent`)
/// whenever the app resumes.
class BatteryService {
  BatteryService._();
  static final BatteryService instance = BatteryService._();

  final Battery _battery = Battery();

  int _lastReported = 100;
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _pollTimer;

  final StreamController<int> _controller = StreamController<int>.broadcast();
  Stream<int> get levelStream => _controller.stream;

  int get currentLevel => _lastReported;

  Future<void> initialize() async {
    try {
      _lastReported = await _battery.batteryLevel;
      _controller.add(_lastReported);
    } catch (e) {
      if (kDebugMode) debugPrint('[BatteryService] init: $e');
    }

    _stateSub = _battery.onBatteryStateChanged.listen((state) {
      _refresh();
    });

    _pollTimer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    try {
      final level = await _battery.batteryLevel;
      if (level != _lastReported) {
        _lastReported = level;
        if (!_controller.isClosed) _controller.add(level);
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    _pollTimer?.cancel();
    await _controller.close();
  }
}
