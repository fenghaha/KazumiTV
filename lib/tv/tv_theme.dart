import 'package:flutter/material.dart';

abstract final class TvTheme {
  static const background = Color(0xFF101C2C);
  static const surface = Color(0xFF1C2C41);
  static const ink = Color(0xFFF5F1E8);
  static const muted = Color(0xFFAAB9CB);
  static const focus = Color(0xFFEBC889);

  static ThemeData get dark {
    final colors =
        ColorScheme.fromSeed(
          seedColor: focus,
          brightness: Brightness.dark,
          surface: background,
        ).copyWith(
          primary: focus,
          onPrimary: background,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainer: surface,
          surfaceContainerHigh: const Color(0xFF263A52),
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'MI_Sans_Regular',
      colorScheme: colors,
      scaffoldBackgroundColor: background,
      focusColor: focus.withValues(alpha: .24),
    );
    final outline = WidgetStateProperty.resolveWith<BorderSide>(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? focus
            : Colors.transparent,
        width: 3,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 26),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 22),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 20),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 18),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        toolbarHeight: 72,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(56, 56)),
          side: outline,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(96, 56)),
          side: outline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(88, 56)),
          side: outline,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 18,
        iconColor: muted,
        tileColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: focus, width: 3),
        ),
        border: OutlineInputBorder(),
      ),
    );
  }
}
