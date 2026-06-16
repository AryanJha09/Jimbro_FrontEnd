import 'package:flutter/material.dart';

import 'jim_tokens.dart';

class JimTheme {
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: JimColors.shell,
      colorScheme: ColorScheme.fromSeed(
        seedColor: JimColors.accent,
        brightness: Brightness.light,
        primary: JimColors.accent,
        secondary: JimColors.accent,
        tertiary: JimColors.accentSoft,
        surface: JimColors.plaque,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: _sans(base.textTheme.displayLarge, 48, FontWeight.w700),
        displayMedium: _sans(base.textTheme.displayMedium, 40, FontWeight.w700),
        displaySmall: _sans(base.textTheme.displaySmall, 30, FontWeight.w700),
        headlineLarge: _sans(base.textTheme.headlineLarge, 28, FontWeight.w700),
        headlineMedium:
            _sans(base.textTheme.headlineMedium, 24, FontWeight.w700),
        headlineSmall: _sans(base.textTheme.headlineSmall, 20, FontWeight.w700),
        titleLarge: _sans(base.textTheme.titleLarge, 18, FontWeight.w700),
        titleMedium: _sans(base.textTheme.titleMedium, 16, FontWeight.w600),
        titleSmall: _sans(base.textTheme.titleSmall, 14, FontWeight.w600),
        bodyLarge: _sans(base.textTheme.bodyLarge, 16, FontWeight.w400),
        bodyMedium: _sans(base.textTheme.bodyMedium, 14, FontWeight.w400),
        bodySmall: _sans(base.textTheme.bodySmall, 12, FontWeight.w400),
        labelLarge: _sans(base.textTheme.labelLarge, 13, FontWeight.w700),
        labelMedium: _sans(base.textTheme.labelMedium, 12, FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: JimColors.plaque,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.card),
          side: const BorderSide(color: JimColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JimColors.plaque.withValues(alpha: .92),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.md,
          vertical: 18,
        ),
        hintStyle: _sans(base.textTheme.bodyMedium, 14, FontWeight.w500)
            ?.copyWith(color: JimColors.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JimRadius.control),
          borderSide: const BorderSide(color: JimColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JimRadius.control),
          borderSide: const BorderSide(color: JimColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JimRadius.control),
          borderSide: const BorderSide(
            color: JimColors.accentLine,
            width: 1.4,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: JimColors.plaque,
        selectedItemColor: JimColors.accent,
        unselectedItemColor: JimColors.accentLine,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        selectedColor: JimColors.accentSoft,
        backgroundColor: JimColors.plaque,
        labelStyle: _sans(base.textTheme.labelLarge, 13, FontWeight.w700),
        side: const BorderSide(color: JimColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.pill),
        ),
      ),
    );
  }

  static TextStyle? _sans(TextStyle? base, double size, FontWeight weight) {
    return base?.copyWith(
      fontFamily: 'Avenir Next',
      fontFamilyFallback: const ['Futura', 'Helvetica Neue', '.SF Pro Text'],
      fontSize: size,
      fontWeight: weight,
      color: JimColors.ink,
      letterSpacing: 0,
      height: 1.36,
    );
  }
}
