import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/alarm_log_model.dart';
import '../models/alarm_model.dart';
import '../providers/connectivity_provider.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Full-screen alarm ring UI.
///
/// - Long-press (>=1.5s) on DISMISS to confirm; quick tap is rejected.
/// - SNOOZE triggers the configured snooze minutes.
/// - After dismiss, an emoji reaction picker is shown; tapping saves
///   the reaction to the dismiss log row.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, this.initial});

  final AlarmRingPayload? initial;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  String _reactionLabel = 'WAKE';
  double _dismissProgress = 0.0;
  Timer? _dismissHold;
  static const _kHoldDuration = Duration(milliseconds: 1500);
  bool _snoozed = false;
  AlarmLogModel? _dismissedLog;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _dismissHold?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDismissStart(LongPressStartDetails _) {
    _dismissHold?.cancel();
    final start = DateTime.now();
    _dismissHold = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final elapsed = DateTime.now().difference(start);
      setState(() {
        _dismissProgress =
            (elapsed.inMilliseconds / _kHoldDuration.inMilliseconds)
                .clamp(0, 1)
                .toDouble();
      });
      if (elapsed >= _kHoldDuration) {
        t.cancel();
        _doDismiss();
      }
    });
  }

  void _onDismissEnd(LongPressEndDetails _) {
    _dismissHold?.cancel();
    if (_dismissProgress < 1.0) {
      setState(() => _dismissProgress = 0.0);
    }
  }

  Future<void> _doDismiss() async {
    if (_dismissedLog != null) return;
    final alarmId = widget.initial?.alarmId ?? '';
    try {
      final res = await ApiService.instance.insertAlarmLog(
        alarmId: alarmId,
        action: AlarmLogModel.dismissed,
        actedBy: ApiService.instance.currentUserId,
      );
      await AlarmService.instance.stopRinging();
      if (!mounted) return;
      setState(() {
        _dismissedLog = res;
        _reactionLabel = 'TAP A REACTION';
        _dismissProgress = 1.0;
      });
    } catch (e) {
      await AlarmService.instance.stopRinging();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _snooze() async {
    if (_snoozed) return;
    setState(() => _snoozed = true);
    final alarmId = widget.initial?.alarmId ?? '';
    try {
      await ApiService.instance.insertAlarmLog(
        alarmId: alarmId,
        action: AlarmLogModel.snoozed,
        actedBy: ApiService.instance.currentUserId,
      );
      final payload = widget.initial;
      if (payload != null) {
        final model = AlarmModel(
          id: payload.alarmId,
          ownerId: ApiService.instance.currentUserId ?? '',
          createdBy: ApiService.instance.currentUserId ?? '',
          label: payload.label,
          message: payload.message,
          hour: payload.hour,
          minute: payload.minute,
          daysOfWeek: const [],
          isActive: true,
          vibrate: true,
          soundName: 'default',
          snoozeMinutes: payload.snoozeMinutes,
          createdAt: DateTime.now(),
        );
        await AlarmService.instance.snoozeAlarm(model);
      }
      await AlarmService.instance.stopRinging();
    } catch (_) {
      await AlarmService.instance.stopRinging();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveReaction(String emoji) async {
    final log = _dismissedLog;
    if (log == null) return;
    try {
      await ApiService.instance.updateAlarmLogReaction(log.id, emoji);
      ref.read(alarmStatsProvider.notifier).refresh();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.now().format(context);
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (widget.initial?.label ?? 'ALARM').toUpperCase(),
                    style: TextStyle(
                      color: AppColors.white,
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'RobotoMono',
                      fontSize: 12.sp,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.initial?.currentTimeFormatted ?? '00:00',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w800,
                        fontSize: 96.sp,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                          left: BorderSide(color: AppColors.border),
                          right: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Text(
                        (widget.initial?.message ?? '').toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.white,
                          fontFamily: 'RobotoMono',
                          fontWeight: FontWeight.w700,
                          fontSize: 18.sp,
                          letterSpacing: 1.6,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _reactionLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _dismissedLog != null
                            ? AppColors.white
                            : AppColors.textSecondary,
                        fontFamily: 'RobotoMono',
                        fontSize: 12.sp,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_dismissedLog == null)
              _RingControls(
                onSnooze: _snoozed ? null : _snooze,
                onDismissStart: _onDismissStart,
                onDismissEnd: _onDismissEnd,
                dismissProgress: _dismissProgress,
              )
            else
              _ReactionPicker(onPick: _saveReaction),
          ],
        ),
      ),
    );
  }
}

/// Payload describing the alarm being dismissed.
class AlarmRingPayload {
  final String alarmId;
  final String label;
  final String message;
  final int hour;
  final int minute;
  final int snoozeMinutes;
  final String currentTimeFormatted;
  const AlarmRingPayload({
    required this.alarmId,
    required this.label,
    required this.message,
    required this.hour,
    required this.minute,
    required this.snoozeMinutes,
    required this.currentTimeFormatted,
  });

  static AlarmRingPayload? fromAlarmSettings(AlarmSettings settings) {
    final title = settings.notificationSettings.title;
    if (title.isEmpty) return null;
    final id = AlarmService.instance.decodeAlarmId(title);
    if (id == null) return null;
    final label = AlarmService.instance.decodeLabel(title);
    final message = AlarmService.instance.decodeMessage(settings);
    final snooze =
        AlarmService.instance.decodeSnoozeMinutes(settings);
    final now = DateTime.now();
    return AlarmRingPayload(
      alarmId: id,
      label: label,
      message: message,
      hour: now.hour,
      minute: now.minute,
      snoozeMinutes: snooze,
      currentTimeFormatted:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
  }
}

class _RingControls extends StatelessWidget {
  const _RingControls({
    required this.onSnooze,
    required this.onDismissStart,
    required this.onDismissEnd,
    required this.dismissProgress,
  });

  final VoidCallback? onSnooze;
  final void Function(LongPressStartDetails) onDismissStart;
  final void Function(LongPressEndDetails) onDismissEnd;
  final double dismissProgress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        children: [
          GestureDetector(
            onLongPressStart: onDismissStart,
            onLongPressEnd: onDismissEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.white, width: 1),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: MediaQuery.of(context).size.width *
                          dismissProgress.clamp(0, 1),
                      height: 56,
                      color: AppColors.black,
                    ),
                  ),
                  Center(
                    child: Text(
                      'HOLD TO STOP',
                      style: TextStyle(
                        color: dismissProgress > 0.4
                            ? AppColors.white
                            : AppColors.black,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w800,
                        fontSize: 16.sp,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.black,
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: AppColors.white, width: 1),
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            child: InkWell(
              onTap: onSnooze,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                alignment: Alignment.center,
                child: Text(
                  'SNOOZE',
                  style: TextStyle(
                    color: onSnooze == null
                        ? AppColors.textDisabled
                        : AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.onPick});
  final void Function(String emoji) onPick;

  static const _options = ['❤️', '😴', '🔥', '☕'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _options
            .map(
              (e) => GestureDetector(
                onTap: () => onPick(e),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.black,
                    border: Border(
                      top: BorderSide(color: AppColors.white, width: 1),
                      bottom: BorderSide(color: AppColors.white, width: 1),
                      left: BorderSide(color: AppColors.white, width: 1),
                      right: BorderSide(color: AppColors.white, width: 1),
                    ),
                  ),
                  child: Text(e, style: TextStyle(fontSize: 32.sp)),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
