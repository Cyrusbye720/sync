import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../models/alarm_log_model.dart';
import '../providers/alarm_provider.dart';
import '../theme/app_theme.dart';

/// Reactions feed — chronologically lists partner reactions to alarms.
class ReactionsScreen extends ConsumerWidget {
  const ReactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(alarmLogsProvider);
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text('REACTIONS',
            style: TextStyle(fontSize: 14.sp, letterSpacing: 2)),
      ),
      body: SafeArea(
        child: logsAsync.when(
          data: (logs) => _buildList(context, logs),
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.white)),
          error: (e, _) => const Center(
            child: Text('Could not load reactions.',
                style: TextStyle(color: AppColors.white)),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<AlarmLogModel> logs) {
    if (logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No reactions yet. Once somebody dismisses an alarm you’ll see them here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'RobotoMono',
              fontSize: 12.sp,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final dismissed = logs
        .where((l) =>
            l.reaction != null && l.action == AlarmLogModel.dismissed)
        .toList(growable: false);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: dismissed.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ReactionRow(log: dismissed[i]),
    );
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.log});
  final AlarmLogModel log;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('E hh:mm a');
    final time = fmt.format(log.createdAt.toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          bottom: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(log.reaction ?? '•', style: TextStyle(fontSize: 28.sp)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              log.action.toUpperCase(),
              style: TextStyle(
                color: AppColors.white,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'RobotoMono',
              fontSize: 10.sp,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
