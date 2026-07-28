import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Two-variant monochrome button: filled (white) or outline (black).
///
/// All variants keep border-radius ≤ 4px and have no shadows — elevation
/// is conveyed exclusively through 1px borders.
enum MonoVariant { primary, outline, ghost, danger }

class MonochromeButton extends StatelessWidget {
  const MonochromeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = MonoVariant.primary,
    this.icon,
    this.fullWidth = true,
    this.compact = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MonoVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;

    final Color fill;
    final Color text;
    final BorderSide border;

    switch (variant) {
      case MonoVariant.primary:
        fill = disabled ? AppColors.surface : AppColors.white;
        text = disabled ? AppColors.textDisabled : AppColors.black;
        border = const BorderSide(color: AppColors.white, width: 1);
        break;
      case MonoVariant.outline:
        fill = AppColors.black;
        text = disabled ? AppColors.textDisabled : AppColors.white;
        border = const BorderSide(color: AppColors.white, width: 1);
        break;
      case MonoVariant.ghost:
        fill = AppColors.black;
        text = disabled ? AppColors.textDisabled : AppColors.white;
        border = const BorderSide(color: AppColors.border, width: 1);
        break;
      case MonoVariant.danger:
        fill = AppColors.white;
        text = AppColors.black;
        border = const BorderSide(color: AppColors.white, width: 2);
        break;
    }

    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 16);

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(text),
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: text),
        if (loading || icon != null) const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: text,
            fontFamily: 'RobotoMono',
            fontWeight: FontWeight.w700,
            fontSize: compact ? 12 : 14,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );

    final button = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(maxRadius)),
        side: border,
      ),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        splashColor: AppColors.surface,
        highlightColor: AppColors.surface,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
