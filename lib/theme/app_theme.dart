import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Strict palette — these are the ONLY colors used anywhere in the app.
class AppColors {
  AppColors._();

  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceAlt = Color(0xFFF5F5F5);
  static const Color border = Color(0xFF333333);
  static const Color borderLight = Color(0xFFCCCCCC);
  static const Color textSecondary = Color(0xFF999999);
  static const Color textDisabled = Color(0xFF666666);

  /// Semantic aliases that *must* resolve to grayscale.
  static const Color primary = white;
  static const Color onPrimary = black;
  static const Color background = black;
  static const Color onBackground = white;
  static const Color error = white;
  static const Color onError = black;
}

/// Standard border — used for every elevated surface in place of shadows.
const Border standardBorder = Border(
  top: BorderSide(color: AppColors.border, width: 1),
  bottom: BorderSide(color: AppColors.border, width: 1),
  left: BorderSide(color: AppColors.border, width: 1),
  right: BorderSide(color: AppColors.border, width: 1),
);

/// Maximum border radius — sharp, brutalist corners.
const double maxRadius = 4.0;

/// Application theme.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final mono = GoogleFonts.robotoMonoTextTheme(base.textTheme);
    final sans = GoogleFonts.robotoTextTheme(base.textTheme);

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.black,
      canvasColor: AppColors.black,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.white,
        onPrimary: AppColors.black,
        secondary: AppColors.white,
        onSecondary: AppColors.black,
        surface: AppColors.surface,
        onSurface: AppColors.white,
        error: AppColors.white,
        onError: AppColors.black,
      ),
      textTheme: sans.copyWith(
        displayLarge: mono.displayLarge?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
        ),
        displayMedium: mono.displayMedium?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        displaySmall: mono.displaySmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        headlineLarge: mono.headlineLarge?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: mono.headlineMedium?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: mono.headlineSmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: mono.titleLarge?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: mono.titleMedium?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: mono.titleSmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: sans.bodyLarge?.copyWith(color: AppColors.white),
        bodyMedium: sans.bodyMedium?.copyWith(color: AppColors.white),
        bodySmall: sans.bodySmall?.copyWith(color: AppColors.textSecondary),
        labelLarge: mono.labelLarge?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelMedium: mono.labelMedium?.copyWith(color: AppColors.white),
        labelSmall: mono.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
      iconTheme: const IconThemeData(color: AppColors.white),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: mono.titleLarge?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18.sp,
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppColors.black,
          systemNavigationBarColor: AppColors.black,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.black,
        selectedItemColor: AppColors.white,
        unselectedItemColor: AppColors.textDisabled,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.white,
        unselectedLabelColor: AppColors.textDisabled,
        indicatorColor: AppColors.white,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: mono.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        unselectedLabelStyle: mono.titleSmall,
        dividerColor: AppColors.border,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.white;
          return AppColors.surface;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.black;
          return AppColors.textDisabled;
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(AppColors.border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        hoverColor: AppColors.surface,
        fillColor: AppColors.black,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        hintStyle: mono.bodyMedium?.copyWith(color: AppColors.textDisabled),
        labelStyle: mono.labelLarge?.copyWith(color: AppColors.textSecondary),
        prefixIconColor: AppColors.white,
        suffixIconColor: AppColors.white,
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          borderSide: BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          borderSide: BorderSide(color: AppColors.white, width: 1),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          borderSide: BorderSide(color: AppColors.white, width: 1),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          borderSide: BorderSide(color: AppColors.white, width: 2),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.black,
        surfaceTintColor: AppColors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: AppColors.white,
          fontFamily: 'RobotoMono',
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: AppColors.white),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(color: AppColors.white),
        actionTextColor: AppColors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.white,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.black,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(maxRadius)),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      dividerColor: AppColors.border,
      splashColor: AppColors.surface,
      highlightColor: AppColors.surface,
    );
  }
}
