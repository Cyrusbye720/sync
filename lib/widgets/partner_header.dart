import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../models/profile_model.dart';
import '../theme/app_theme.dart';

/// Header strip showing the partner's identity, sleep status, timezone,
/// and battery — all monochrome.
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
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final sign = hours >= 0 ? '+' : '-';
    return 'GMT$sign${hours.abs().toString().padLeft(2, '0')}:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAwake ? AppColors.white : AppColors.textDisabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partner.username.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    fontSize: 14.sp,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isAwake ? "AWAKE" : "ASLEEP"} · ${_formatLocal()} (${_formatOffset()})',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'RobotoMono',
                    fontSize: 11.sp,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          if (partner.isLowBattery)
            _BatteryChip(percent: batteryPercent)
          else if (isAwake == false)
            const _StatusChip(label: 'ZZZ')
          else
            const _StatusChip(label: 'ON'),
          if (unpair != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: unpair,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 1),
                  borderRadius:
                      const BorderRadius.all(Radius.circular(maxRadius)),
                ),
                child: const Text(
                  'UNPAIR',
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: const BorderRadius.all(Radius.circular(maxRadius)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.white,
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  const _BatteryChip({required this.percent});
  final int percent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          color: AppColors.black,
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          fontSize: 10,
        ),
      ),
    );
  }
}
