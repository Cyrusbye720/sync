import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/nudge_model.dart';
import '../providers/pairing_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/monochrome_button.dart';

/// Full-screen overlay shown when the partner nudges us.
class IncomingNudgeScreen extends ConsumerWidget {
  const IncomingNudgeScreen({super.key, required this.nudge});

  /// The nudge row to display. Caller pops the route when dismissed.
  final NudgeModel nudge;

  static final Set<String> _shownIds = {};
  static bool _isScreenOpen = false;

  /// Helper to safely present the IncomingNudgeScreen.
  /// Prevents double-pushing, duplicate notifications, and old historical nudges.
  static void show(BuildContext context, NudgeModel nudge) {
    if (_shownIds.contains(nudge.id)) return;
    _shownIds.add(nudge.id);

    // Only surface ringing overlay for recent nudges (within last 90 seconds)
    final age = DateTime.now().difference(nudge.createdAt);
    if (age.inSeconds > 90 || age.isNegative) return;

    if (_isScreenOpen) return;
    _isScreenOpen = true;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IncomingNudgeScreen(nudge: nudge),
      ),
    ).then((_) {
      _isScreenOpen = false;
    });
  }

  String get _formattedTime {
    final local = nudge.createdAt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}'
        ':${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(pairingProvider).partner;
    final partnerName = (partner?.username.isNotEmpty == true)
        ? partner!.username.toUpperCase()
        : 'YOUR PARTNER';

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
                  '$partnerName IS TRYING TO WAKE YOU UP.',
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
                'TAP DISMISS TO SILENCE THIS NUDGE.',
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
                  _isScreenOpen = false;
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