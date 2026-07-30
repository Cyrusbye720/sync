import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Smooth 12-hour (1..12 + AM/PM) time picker used inside the alarm form.
class TimePickerField extends StatefulWidget {
  const TimePickerField({
    super.key,
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour; // 0..23
  final int minute; // 0..59
  final void Function(int hour, int minute) onChanged;

  @override
  State<TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<TimePickerField> {
  late FixedExtentScrollController _hourCtl;
  late FixedExtentScrollController _minuteCtl;
  late FixedExtentScrollController _ampmCtl;

  int get _hour12 {
    final h = widget.hour % 12;
    return h == 0 ? 12 : h;
  }

  bool get _isPm => widget.hour >= 12;

  @override
  void initState() {
    super.initState();
    _hourCtl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteCtl = FixedExtentScrollController(initialItem: widget.minute);
    _ampmCtl = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);
  }

  @override
  void didUpdateWidget(covariant TimePickerField old) {
    super.didUpdateWidget(old);
    if (old.hour != widget.hour) {
      _hourCtl.jumpToItem(_hour12 - 1);
      _ampmCtl.jumpToItem(_isPm ? 1 : 0);
    }
    if (old.minute != widget.minute) {
      _minuteCtl.jumpToItem(widget.minute);
    }
  }

  void _notify(int h12, int m, bool isPm) {
    final norm12 = h12 == 12 ? 0 : h12;
    final h24 = isPm ? (norm12 + 12) : norm12;
    widget.onChanged(h24, m);
  }

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('hh:mm a').format(
      DateTime(2024, 1, 1, widget.hour, widget.minute),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.black,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 12-Hour Wheel (1..12)
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: _Wheel(
                    controller: _hourCtl,
                    max: 12,
                    format: (v) => (v + 1).toString().padLeft(2, '0'),
                    label: 'H',
                    onChanged: (idx) => _notify(idx + 1, widget.minute, _isPm),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Minute Wheel (0..59)
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: _Wheel(
                    controller: _minuteCtl,
                    max: 60,
                    format: (v) => v.toString().padLeft(2, '0'),
                    label: 'M',
                    onChanged: (m) => _notify(_hour12, m, _isPm),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // AM / PM Wheel
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: _Wheel(
                    controller: _ampmCtl,
                    max: 2,
                    format: (v) => v == 0 ? 'AM' : 'PM',
                    label: '',
                    onChanged: (idx) => _notify(_hour12, widget.minute, idx == 1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatted.toUpperCase(),
            style: TextStyle(
              color: AppColors.white,
              fontFamily: 'RobotoMono',
              fontWeight: FontWeight.w800,
              fontSize: 28.sp,
              letterSpacing: 2.0,
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
      itemExtent: 38,
      perspective: 0.002,
      diameterRatio: 1.8,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          if (index < 0 || index >= max) return const SizedBox.shrink();
          final text = label.isEmpty ? format(index) : '${format(index)} $label';
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.black,
              border: Border.all(color: AppColors.border, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.white,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          );
        },
        childCount: max,
      ),
    );
  }
}
