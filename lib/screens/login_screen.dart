import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../providers/auth_provider.dart';
import '../services/alarm_service.dart';
import '../theme/app_theme.dart';
import 'pair_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _requestingPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() => _requestingPermissions = true);
    try {
      await AlarmService.instance.initialize();
      await AlarmService.instance.requestExactAlarmPermission();
      await AlarmService.instance.requestNotificationPermission();
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _signInDiscord() async {
    await ref.read(authProvider.notifier).signInWithDiscord();
  }

  Future<void> _signInGitHub() async {
    await ref.read(authProvider.notifier).signInWithGitHub();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final error = auth.error;

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isAuthenticated && prev?.isAuthenticated != true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const PairScreen()),
          (_) => false,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24.w, 32, 24.w, 24),
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: AppColors.peach,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wb_twilight_rounded,
                  size: 36, color: AppColors.cocoa),
            ),
            const SizedBox(height: 28),
            Text(
              'Wake up\nbetter, together.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: 42.sp,
                    height: 1.08,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Plan shared mornings, nudge each other awake, and keep every alarm on this device.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.muted,
                    height: 1.5,
                  ),
            ),
            SizedBox(height: 36.h),
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(error,
                    style: const TextStyle(color: AppColors.error)),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _requestingPermissions ? null : _signInDiscord,
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Continue with Discord'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _requestingPermissions ? null : _signInGitHub,
              icon: const Icon(Icons.code_rounded),
              label: const Text('Continue with GitHub'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cocoa,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Local exact alarms stay active even if partner alerts are unavailable.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.sp,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
