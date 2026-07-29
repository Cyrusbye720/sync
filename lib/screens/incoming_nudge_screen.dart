import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/nudge_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/monochrome_button.dart';

/// Full-screen overlay shown when the partner nudges us via
/// Supabase Realtime. Plays the standard alarm chime, holds the
/// screen on, and waits for a single DISMISS tap.
class IncomingNudgeScreen extends ConsumerWidget {
  const IncomingNudgeScreen({super.key, required this.nudge});

  /// The nudge row to display. Caller pops the route when dismissed.
  final NudgeModel nudge;

  String get _formattedTime {
    final local = nudge.createdAt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}'
        ':${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'NUDGE',
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w800,
                    fontSize: 14.sp,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: Text(
                  _formattedTime,
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w800,
                    fontSize: 96.sp,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.white, width: 1),
                    bottom: BorderSide(color: AppColors.white, width: 1),
                    left: BorderSide(color: AppColors.white, width: 1),
                    right: BorderSide(color: AppColors.white, width: 1),
                  ),
                ),
                child: Text(
                  'YOUR PARTNER IS TRYING TO WAKE YOU UP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    letterSpacing: 2,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'This only fires while both apps are open. Background push is not part of v1.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'RobotoMono',
                  fontSize: 10.sp,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              MonochromeButton(
                label: 'DISMISS',
                variant: MonoVariant.primary,
                onPressed: () async {
                  try {
                    await ApiService.instance.markNudgeRead(nudge.id);
                  } catch (_) {}
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}