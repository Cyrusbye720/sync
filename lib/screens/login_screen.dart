import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../providers/auth_provider.dart';
import '../services/alarm_service.dart';
import '../theme/app_theme.dart';
import '../widgets/monochrome_button.dart';
import 'pair_screen.dart';

/// Login screen — first surface the user sees when unauthenticated.
///
/// Two large OAuth buttons: Discord (primary) and GitHub (fallback).
/// All errors are rendered as white-on-black text — no colored snackbars.
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
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Text(
                'SYNC',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w800,
                  fontSize: 64.sp,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'MORNINGS ARE BRUTAL ENOUGH.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'RobotoMono',
                  fontSize: 12.sp,
                  letterSpacing: 4,
                ),
              ),
              const Spacer(flex: 3),
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.white, width: 1),
                      bottom: BorderSide(color: AppColors.white, width: 1),
                      left: BorderSide(color: AppColors.white, width: 1),
                      right: BorderSide(color: AppColors.white, width: 1),
                    ),
                  ),
                  child: Text(
                    error.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.white,
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              MonochromeButton(
                label: 'Sign in with Discord',
                icon: Icons.chat_bubble_outline,
                variant: MonoVariant.primary,
                loading: _requestingPermissions,
                onPressed: _signInDiscord,
              ),
              const SizedBox(height: 12),
              MonochromeButton(
                label: 'Sign in with GitHub',
                icon: Icons.code,
                variant: MonoVariant.outline,
                onPressed: _signInGitHub,
              ),
              const SizedBox(height: 24),
              Text(
                'Sign in to sync your mornings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textDisabled,
                  fontFamily: 'RobotoMono',
                  fontSize: 10.sp,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
