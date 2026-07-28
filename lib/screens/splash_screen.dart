import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_theme.dart';

/// Splash screen — shown while permissions are requested and the
/// initial Supabase auth check completes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SYNC',
                style: TextStyle(
                  color: AppColors.white,
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w800,
                  fontSize: 56.sp,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'WAKE UP TOGETHER',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'RobotoMono',
                  letterSpacing: 2,
                  fontSize: 12.sp,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
