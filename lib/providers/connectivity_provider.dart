import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/battery_service.dart';
import '../services/supabase_service.dart';
import 'alarm_provider.dart';
import 'auth_provider.dart';

/// Battery level of *this* device, in percent (0..100).
class BatteryNotifier extends StateNotifier<int> {
  BatteryNotifier() : super(100) {
    _bind();
  }

  StreamSubscription<int>? _sub;

  void _bind() {
    BatteryService.instance.initialize().then((_) async {
      state = BatteryService.instance.currentLevel;
      _sub = BatteryService.instance.levelStream.listen((v) => state = v);
      _pushToServer();
    });
  }

  Future<void> refresh() async {
    state = BatteryService.instance.currentLevel;
    await _pushToServer();
  }

  Future<void> _pushToServer() async {
    final me = SupabaseService.instance.currentUserId;
    if (me == null) return;
    try {
      await SupabaseService.instance.updateProfile(
        me,
        {'battery_percent': state},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Battery] push: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final batteryProvider =
    StateNotifierProvider<BatteryNotifier, int>((ref) => BatteryNotifier());

/// Partner's current battery level (read from profile).
final partnerBatteryProvider = StateProvider<int>((_) => 100);

/// Partner's sleep status — derived from profile but also locally updated
/// when a snoozed alarm is within the next 8 hours.
class SleepStatusNotifier extends StateNotifier<String> {
  SleepStatusNotifier(this._ref) : super('awake') {
    _bootstrap();
  }

  final Ref _ref;

  void _bootstrap() {
    final profile = _ref.read(authProvider).profile;
    if (profile != null) state = profile.sleepStatus;
    _ref.listen<dynamic>(authProvider.select((s) => s.profile), (prev, next) {
      if (next != null && next.sleepStatus != state) state = next.sleepStatus;
    });
  }

  Future<void> setSleep(String status) async {
    state = status;
    final me = SupabaseService.instance.currentUserId;
    if (me == null) return;
    try {
      await SupabaseService.instance.updateProfile(
        me,
        {'sleep_status': status},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Sleep] push: $e');
    }
  }

  Future<void> markAsleepIfImminent(DateTime nextFire) async {
    final delta = nextFire.difference(DateTime.now());
    if (delta.inHours <= 8 && delta.inHours > 0) {
      await setSleep('asleep');
    }
  }
}

final sleepStatusProvider =
    StateNotifierProvider<SleepStatusNotifier, String>(
        (ref) => SleepStatusNotifier(ref));

/// Connectivity status — used to retry alarm sync attempts.
class ConnectivityNotifier extends StateNotifier<bool> {
  ConnectivityNotifier() : super(true);
  Future<void> setOnline(bool online) async => state = online;
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, bool>(
        (ref) => ConnectivityNotifier());

/// Device timezone — populated at app start.
final deviceTimezoneProvider = StateProvider<String>((ref) => 'UTC');

/// Stats derived from the most recent alarm logs for the pair.
class AlarmStats {
  final int snoozeStreak; // snoozes this week
  final double onTimeRate; // dismissed / (dismissed + snoozed) * 100
  final DateTime? lastWakeUp;

  const AlarmStats({
    required this.snoozeStreak,
    required this.onTimeRate,
    required this.lastWakeUp,
  });

  static const empty = AlarmStats(
    snoozeStreak: 0,
    onTimeRate: 0,
    lastWakeUp: null,
  );
}

class StatsNotifier extends StateNotifier<AlarmStats> {
  StatsNotifier(this._ref) : super(AlarmStats.empty) {
    _bind();
  }

  final Ref _ref;
  StreamSubscription<dynamic>? _logsSub;
  String? _userId;

  void _subscribeToLogs() {
    _logsSub?.cancel();
    _logsSub = _ref.read(alarmLogsProvider.stream).listen((async) {
      // Only refresh on data transitions; loading/error are no-ops.
      async.whenData((_) => _refresh());
    });
  }

  void _bind() {
    _refresh();
    _userId = _ref.read(authProvider).userId;
    _subscribeToLogs();
    _ref.listen<String?>(authProvider.select((s) => s.userId), (prev, next) {
      if (next != _userId) {
        _userId = next;
        _subscribeToLogs();
        _refresh();
      }
    });
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    final userId = SupabaseService.instance.currentUserId;
    if (userId == null) return;
    try {
      final alarms = await SupabaseService.instance.fetchAlarmsFor(userId);
      if (alarms.isEmpty) {
        state = AlarmStats.empty;
        return;
      }
      final ids = alarms.map((e) => e.id).toList(growable: false);
      final logs = await SupabaseService.instance.fetchLogsForPair(ids);

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final recent = logs.where((l) => l.createdAt.isAfter(cutoff)).toList();
      final snoozes = recent.where((l) => l.action == 'snoozed').length;
      final dismissed = recent.where((l) => l.action == 'dismissed').length;
      final denom = dismissed + snoozes;
      final rate = denom == 0 ? 0.0 : (dismissed / denom) * 100;

      final lastDismiss = recent
          .where((l) => l.action == 'dismissed')
          .map((l) => l.createdAt)
          .fold<DateTime?>(null, (acc, t) {
        if (acc == null) return t;
        return t.isAfter(acc) ? t : acc;
      });

      state = AlarmStats(
        snoozeStreak: snoozes,
        onTimeRate: rate,
        lastWakeUp: lastDismiss,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Stats] refresh: $e');
    }
  }

  @override
  void dispose() {
    _logsSub?.cancel();
    super.dispose();
  }
}

final alarmStatsProvider =
    StateNotifierProvider<StatsNotifier, AlarmStats>(
        (ref) => StatsNotifier(ref));
