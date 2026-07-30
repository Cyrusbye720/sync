import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../models/profile_model.dart';
import '../theme/app_theme.dart';

/// Live status widget for partner — displays active screen status,
/// battery level, timezone offset / IST time, and unpair option.
class PartnerHeader extends StatelessWidget {
  const PartnerHeader({
    super.key,
    required this.partner,
    required this.isAwake,
    required this.localTime,
    required this.batteryPercent,
    this.unpair,
  });

  final ProfileModel partner;
  final bool isAwake;
  final DateTime localTime;
  final int batteryPercent;
  final VoidCallback? unpair;

  String _formatLocal() {
    final fmt = DateFormat('hh:mm a');
    return fmt.format(localTime);
  }

  String _formatOffset() {
    final offset = localTime.timeZoneOffset;
    final hours = offset.inHours;
    final minutes = offset.inMinutes.abs() % 60;
    if (hours == 5 && minutes == 30) {
      return 'IST';
    }
    final minStr = minutes.toString().padLeft(2, '0');
    final sign = hours >= 0 ? '+' : '-';
    return 'GMT$sign${hours.abs().toString().padLeft(2, '0')}:$minStr';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = isAwake ? "SCREEN ON · ACTIVE" : "SCREEN OFF · SLEEPING";
    final tzLabel = _formatOffset();
    final timeStr = "${_formatLocal()} ($tzLabel)";
    final battStr = "$batteryPercent%";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.black,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isAwake ? AppColors.white : AppColors.textDisabled,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                partner.username.toUpperCase(),
                style: TextStyle(
                  color: AppColors.white,
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  fontSize: 15.sp,
                ),
              ),
              const Spacer(),
              if (unpair != null)
                GestureDetector(
                  onTap: unpair,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'UNPAIR',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      color: isAwake ? AppColors.white : AppColors.textSecondary,
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TIME: ${_formatLocal()} ($tzLabel)',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'RobotoMono',
                      fontSize: 11.sp,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(
                    batteryPercent <= 20
                        ? Icons.battery_alert
                        : Icons.battery_full,
                    size: 16,
                    color: batteryPercent <= 20
                        ? AppColors.white
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$batteryPercent%',
                    style: TextStyle(
                      color: AppColors.white,
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
