import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact Mon–Sun day selector. Selection is stored as `List<int>`
/// matching the Supabase schema and Dart's `DateTime.weekday` (1=Mon..7=Sun).
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  static const List<DayLabel> _days = [
    DayLabel(weekday: DateTime.monday, short: 'M'),
    DayLabel(weekday: DateTime.tuesday, short: 'T'),
    DayLabel(weekday: DateTime.wednesday, short: 'W'),
    DayLabel(weekday: DateTime.thursday, short: 'T'),
    DayLabel(weekday: DateTime.friday, short: 'F'),
    DayLabel(weekday: DateTime.saturday, short: 'S'),
    DayLabel(weekday: DateTime.sunday, short: 'S'),
  ];

  void _toggle(int weekday) {
    final next = List<int>.from(selected);
    if (next.contains(weekday)) {
      next.remove(weekday);
    } else {
      next.add(weekday);
      next.sort();
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((day) {
        final isSelected = selected.contains(day.weekday);
        final cell = GestureDetector(
          onTap: () => _toggle(day.weekday),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.white : AppColors.black,
              border: Border.all(
                color: isSelected ? AppColors.white : AppColors.border,
                width: 1,
              ),
              borderRadius:
                  const BorderRadius.all(Radius.circular(maxRadius)),
            ),
            child: Text(
              day.short,
              style: TextStyle(
                color: isSelected ? AppColors.black : AppColors.white,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return cell;
      }).toList(),
    );
  }
}

class DayLabel {
  final int weekday;
  final String short;
  const DayLabel({required this.weekday, required this.short});
}
