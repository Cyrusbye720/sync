import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/alarm_model.dart';
import '../providers/alarm_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/day_selector.dart';
import '../widgets/monochrome_button.dart';
import '../widgets/monochrome_input.dart';
import '../widgets/time_picker_field.dart';

/// Alarm form — used both for create and edit. Owner is fixed; the
/// ownership boundary (mine vs. theirs) is inferred from `ownerId`
/// compared to the current user.
class AlarmFormScreen extends ConsumerStatefulWidget {
  const AlarmFormScreen({
    super.key,
    required this.ownerId,
    this.existing,
  });

  final String ownerId;
  final AlarmModel? existing;

  @override
  ConsumerState<AlarmFormScreen> createState() => _AlarmFormScreenState();
}

class _AlarmFormScreenState extends ConsumerState<AlarmFormScreen> {
  late int _hour;
  late int _minute;
  late List<int> _days;
  late TextEditingController _label;
  late TextEditingController _message;
  late bool _vibrate;
  late int _snooze;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final src = widget.existing;
    _hour = src?.hour ?? DateTime.now().hour;
    _minute = src?.minute ?? 0;
    _days = List<int>.from(src?.daysOfWeek ?? const [1, 2, 3, 4, 5]);
    _label = TextEditingController(text: src?.label ?? 'Wake up');
    _message = TextEditingController(text: src?.message ?? '');
    _vibrate = src?.vibrate ?? true;
    _snooze = src?.snoozeMinutes ?? 5;
  }

  @override
  void dispose() {
    _label.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(alarmListProvider.notifier);
      if (widget.existing == null) {
        await notifier.create(
          ownerId: widget.ownerId,
          label: _label.text.trim().isEmpty ? 'Alarm' : _label.text.trim(),
          message: _message.text.trim(),
          hour: _hour,
          minute: _minute,
          daysOfWeek: _days,
          isActive: true,
          vibrate: _vibrate,
          snoozeMinutes: _snooze,
        );
      } else {
        final updated = widget.existing!.copyWith(
          label: _label.text.trim().isEmpty ? 'Alarm' : _label.text.trim(),
          message: _message.text.trim(),
          hour: _hour,
          minute: _minute,
          daysOfWeek: _days,
          vibrate: _vibrate,
          snoozeMinutes: _snooze,
        );
        await notifier.update(widget.existing!.id, updated);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(
          isEdit ? 'EDIT ALARM' : 'NEW ALARM',
          style: TextStyle(fontSize: 14.sp, letterSpacing: 2),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const _SectionLabel('TIME'),
            TimePickerField(
              hour: _hour,
              minute: _minute,
              onChanged: (h, m) => setState(() {
                _hour = h;
                _minute = m;
              }),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('DAYS'),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                  bottom: BorderSide(color: AppColors.border, width: 1),
                  left: BorderSide(color: AppColors.border, width: 1),
                  right: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: DaySelector(
                selected: _days,
                onChanged: (next) => setState(() => _days = next),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('LABEL'),
            MonochromeInput(
              controller: _label,
              hint: 'e.g. Workout',
              icon: Icons.label_outline,
              maxLines: 1,
            ),
            const SizedBox(height: 24),
            const _SectionLabel('MESSAGE'),
            MonochromeInput(
              controller: _message,
              hint: 'e.g. Rise and shine',
              icon: Icons.short_text,
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            const _SectionLabel('OPTIONS'),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                  bottom: BorderSide(color: AppColors.border, width: 1),
                  left: BorderSide(color: AppColors.border, width: 1),
                  right: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'VIBRATE',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        letterSpacing: 1.4,
                      ),
                    ),
                    subtitle: Text(
                      'When the alarm rings.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    value: _vibrate,
                    onChanged: (v) => setState(() => _vibrate = v),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'SNOOZE MINUTES',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: 'RobotoMono',
                        letterSpacing: 1.4,
                      ),
                    ),
                    subtitle: Text(
                      '$_snooze min',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove,
                              color: AppColors.white),
                          onPressed: _snooze > 1
                              ? () => setState(() => _snooze -= 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add,
                              color: AppColors.white),
                          onPressed: () => setState(() =>
                              _snooze = (_snooze + 1).clamp(1, 60)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            MonochromeButton(
              label: isEdit ? 'SAVE' : 'CREATE',
              icon: Icons.check,
              variant: MonoVariant.primary,
              loading: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w700,
          fontSize: 11.sp,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
