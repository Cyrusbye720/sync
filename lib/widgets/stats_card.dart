import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../providers/connectivity_provider.dart';
import '../theme/app_theme.dart';

/// Stats summary card displayed on Home — snooze streak, on-time rate,
/// and last wake-up time. All monochrome.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.stats});
  final AlarmStats stats;

  String _formatLastWake() {
    final t = stats.lastWakeUp;
    if (t == null) return '—';
    final fmt = DateFormat('E hh:mm a');
    return fmt.format(t.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          bottom: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THIS WEEK',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'RobotoMono',
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              fontSize: 11.sp,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'SNOOZE',
                  value: '${stats.snoozeStreak}',
                  sub: 'TIMES',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: 'ON-TIME',
                  value: '${stats.onTimeRate.toStringAsFixed(0)}%',
                  sub: 'RATE',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: 'LAST',
                  value: _formatLastWake(),
                  sub: 'WAKE-UP',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.sub,
  });
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.black,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: const BorderRadius.all(Radius.circular(maxRadius)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'RobotoMono',
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: AppColors.white,
              fontFamily: 'RobotoMono',
              fontWeight: FontWeight.w800,
              fontSize: 22.sp,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'RobotoMono',
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
