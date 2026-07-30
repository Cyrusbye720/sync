import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm_log_model.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Live list of alarms paired with the current user, refreshed via
/// periodic polling. Local alarm scheduling happens automatically.
class AlarmListNotifier extends StateNotifier<List<AlarmModel>> {
  AlarmListNotifier(this._service) : super(const <AlarmModel>[]) {
    _bootstrap();
  }

  final ApiService _service;
  Timer? _pollTimer;
  String? _userId;

  Future<void> _bootstrap() async {
    final userId = _service.currentUserId;
    if (userId == null) return;
    _userId = userId;
    try {
      final initial = await _service.fetchAlarmsFor(userId);
      state = initial;
      await _scheduleAllLocal(initial);
    } catch (e) {
      if (kDebugMode) debugPrint('[Alarms] initial fetch: $e');
    }
    // Poll every 15 seconds for alarm changes
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    final userId = _service.currentUserId;
    if (userId == null) return;
    try {
      final rows = await _service.fetchAlarmsFor(userId);
      state = rows;
      await _scheduleAllLocal(rows);
    } catch (e) {
      if (kDebugMode) debugPrint('[Alarms] poll: $e');
    }
  }

  void rebind(String userId) {
    if (_userId == userId) return;
    _userId = userId;
    _pollTimer?.cancel();
    state = const <AlarmModel>[];
    _bootstrap();
  }

  Future<void> _scheduleAllLocal(List<AlarmModel> models) async {
    for (final alarm in models) {
      final me = _service.currentUserId;
      if (me == null) continue;
      if (alarm.ownerId == me) {
        try {
          await AlarmService.instance.scheduleAlarm(alarm);
        } catch (e) {
          if (kDebugMode) debugPrint('[Alarms] schedule ${alarm.id}: $e');
        }
      }
    }
  }

  Future<AlarmModel> create({
    required String ownerId,
    required String label,
    required String message,
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
    required bool isActive,
    required bool vibrate,
    required int snoozeMinutes,
  }) async {
    final me = _service.currentUserId!;
    final created = await _service.insertAlarm(
      ownerId: ownerId,
      createdBy: me,
      label: label,
      message: message,
      hour: hour,
      minute: minute,
      daysOfWeek: daysOfWeek,
      isActive: isActive,
      vibrate: vibrate,
      snoozeMinutes: snoozeMinutes,
    );
    await _poll();
    return created;
  }

  Future<AlarmModel> update(String id, AlarmModel updated) async {
    final res = await _service.updateAlarm(id, updated.toUpdateMap());
    if (updated.ownerId == _service.currentUserId) {
      await AlarmService.instance.scheduleAlarm(res);
    }
    await _poll();
    return res;
  }

  Future<void> toggle(String id, bool isActive) async {
    final res = await _service.updateAlarm(id, {'is_active': isActive});
    if (res.ownerId == _service.currentUserId) {
      if (isActive) {
        await AlarmService.instance.scheduleAlarm(res);
      } else {
        await AlarmService.instance.cancelAlarm(res.id);
      }
    }
    await _poll();
  }

  Future<void> delete(String id) async {
    await _service.deleteAlarm(id);
    await AlarmService.instance.cancelAlarm(id);
    await _poll();
  }

  Future<AlarmModel?> byId(String id) async {
    for (final a in state) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<AlarmModel> alarmsOwnedBy(String userId) =>
      state.where((a) => a.ownerId == userId).toList(growable: false);

  List<AlarmModel> alarmsCreatedBy(String userId) =>
      state.where((a) => a.createdBy == userId).toList(growable: false);

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final alarmListProvider =
    StateNotifierProvider<AlarmListNotifier, List<AlarmModel>>((ref) {
  final service = ApiService.instance;
  final notifier = AlarmListNotifier(service);
  // Rebind when the auth user changes.
  ref.listen<String?>(authProvider.select((a) => a.userId), (prev, next) {
    if (next != null) notifier.rebind(next);
  });
  return notifier;
});

/// Recent alarm logs across the pair — fetched periodically.
final alarmLogsProvider =
    FutureProvider.autoDispose<List<AlarmLogModel>>((ref) async {
  final alarms =
      ref.watch(alarmListProvider).map((e) => e.id).toList(growable: false);
  if (alarms.isEmpty) return const <AlarmLogModel>[];
  return ApiService.instance.fetchLogsForPair(alarms);
});
