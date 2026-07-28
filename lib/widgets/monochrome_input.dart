import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Sharp-cornered monochrome text input. Available as a wrapper around
/// `TextField` for consistency across forms.
class MonochromeInput extends StatelessWidget {
  const MonochromeInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      obscureText: obscureText,
      enabled: enabled,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: AppColors.white),
      cursorColor: AppColors.white,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
      inputFormatters: keyboardType == TextInputType.number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
          : null,
    );
  }
}
