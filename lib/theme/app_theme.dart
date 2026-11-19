import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  static const cream = Color(0xFFFFF8EF);
  static const creamStrong = Color(0xFFF7EBDC);
  static const cocoa = Color(0xFF3B2F2A);
  static const ink = Color(0xFF4A3C35);
  static const muted = Color(0xFF807069);
  static const coral = Color(0xFFE78372);
  static const coralDark = Color(0xFFC86456);
  static const peach = Color(0xFFF6CDBA);
  static const sage = Color(0xFF91A78E);
  static const white = Color(0xFFFFFFFF);
  static const border = Color(0xFFE8DACE);
  static const surface = white;
  static const surfaceAlt = creamStrong;
  static const textSecondary = muted;
  static const textDisabled = Color(0xFFAAA098);
  static const primary = coral;
  static const onPrimary = white;
  static const background = cream;
  static const onBackground = cocoa;
  static const error = Color(0xFFB94A42);
  static const onError = white;
  static const black = cream;
}

const Border standardBorder =
    Border.fromBorderSide(BorderSide(color: AppColors.border, width: 1));
const double maxRadius = 24;

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.cocoa,
      displayColor: AppColors.cocoa,
    );

    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.sage,
        onSecondary: AppColors.cocoa,
        surface: AppColors.surface,
        onSurface: AppColors.cocoa,
        error: AppColors.error,
        onError: AppColors.onError,
      ),
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.cocoa),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.cocoa,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.cocoa,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: AppColors.cocoa),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.coral,
        unselectedItemColor: AppColors.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.cocoa,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.coral,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.coral
              : AppColors.border,
        ),
        thumbColor: const WidgetStatePropertyAll(AppColors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.coral, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cocoa,
        contentTextStyle: const TextStyle(color: AppColors.white),
        actionTextColor: AppColors.peach,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.coral,
        linearTrackColor: AppColors.creamStrong,
        circularTrackColor: AppColors.creamStrong,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.coral,
        foregroundColor: AppColors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      splashColor: AppColors.peach,
      highlightColor: AppColors.creamStrong,
    );
  }
}
