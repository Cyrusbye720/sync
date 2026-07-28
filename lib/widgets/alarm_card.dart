import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/alarm_model.dart';
import '../theme/app_theme.dart';

/// A single alarm row in the list.
///
/// Shows:
/// - time HH:MM (display)
/// - label + message preview
/// - day chips
/// - creator attribution
/// - toggle, edit, and delete actions
class AlarmCard extends StatelessWidget {
  const AlarmCard({
    super.key,
    required this.alarm,
    required this.isMine,
    required this.creatorName,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final AlarmModel alarm;
  final bool isMine;
  final String? creatorName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final daysLabel = alarm.isEveryDay
        ? 'EVERY DAY'
        : alarm.isOneShot
            ? 'ONCE'
            : _formatDays(alarm.daysOfWeek);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          bottom: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  alarm.formattedTime(),
                  style: TextStyle(
                    color: alarm.isActive ? AppColors.white : AppColors.textDisabled,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w800,
                    fontSize: 36.sp,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.white,
                          fontFamily: 'RobotoMono',
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                          letterSpacing: 1.0,
                        ),
                      ),
                      if (alarm.message.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          alarm.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.sp,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(value: alarm.isActive, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Pill(text: daysLabel),
                const SizedBox(width: 8),
                if (alarm.vibrate) const _Pill(text: 'VIB'),
                const Spacer(),
                Text(
                  isMine ? 'BELONGS TO YOU' : 'SET BY ${(creatorName ?? 'THEM').toUpperCase()}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'RobotoMono',
                    fontSize: 10.sp,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      side: const BorderSide(color: AppColors.border, width: 1),
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(maxRadius)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onEdit,
                    child: const Text(
                      'EDIT',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      side: const BorderSide(color: AppColors.border, width: 1),
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(maxRadius)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onDelete,
                    child: const Text(
                      'DELETE',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDays(List<int> weekdays) {
    const labels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final sorted = [...weekdays]..sort();
    final parts = sorted.map((d) => labels[d - 1]);
    return parts.join(' · ');
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.black,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: const BorderRadius.all(Radius.circular(maxRadius)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.white,
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 10,
        ),
      ),
    );
  }
}
