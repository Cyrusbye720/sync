import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Custom monochrome time picker used inside the alarm form.
///
/// Instead of dropping back to the platform picker we render two
/// vertical wheels (hour + minute). The wheels are styled in pure
/// black-and-white and use a deterministic tick generator.
class TimePickerField extends StatefulWidget {
  const TimePickerField({
    super.key,
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  State<TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<TimePickerField> {
  late FixedExtentScrollController _hourCtl;
  late FixedExtentScrollController _minuteCtl;

  @override
  void initState() {
    super.initState();
    _hourCtl = FixedExtentScrollController(initialItem: widget.hour);
    _minuteCtl = FixedExtentScrollController(
      initialItem: widget.minute,
    );
  }

  @override
  void didUpdateWidget(covariant TimePickerField old) {
    super.didUpdateWidget(old);
    if (old.hour != widget.hour) {
      _hourCtl.jumpToItem(widget.hour);
    }
    if (old.minute != widget.minute) {
      _minuteCtl.jumpToItem(widget.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('HH:mm').format(
      DateTime(2024, 1, 1, widget.hour, widget.minute),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          bottom: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 140,
              child: _Wheel(
                controller: _hourCtl,
                max: 24,
                format: (v) => v.toString().padLeft(2, '0'),
                label: 'H',
                onChanged: (v) =>
                    widget.onChanged(v, widget.minute),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 140,
              child: _Wheel(
                controller: _minuteCtl,
                max: 60,
                format: (v) => v.toString().padLeft(2, '0'),
                label: 'M',
                onChanged: (v) =>
                    widget.onChanged(widget.hour, v),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text(
                formatted,
                style: TextStyle(
                  color: AppColors.white,
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w800,
                  fontSize: 38.sp,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.max,
    required this.format,
    required this.label,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int max;
  final String Function(int) format;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 36,
      perspective: 0.001,
      diameterRatio: 1.6,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          if (index < 0 || index >= max) return const SizedBox.shrink();
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Text(
              '${format(index)} $label',
              style: const TextStyle(
                color: AppColors.white,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          );
        },
        childCount: max,
      ),
    );
  }
}
