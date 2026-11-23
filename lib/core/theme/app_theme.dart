import 'package:flutter/material.dart';

/// Semantic status colours (always pair with an icon + label in widgets).
class StatusColors {
  static const success = Color(0xFF2E9E5B);
  static const warning = Color(0xFFF2A100);
  static const danger = Color(0xFFD64545);
  static const info = Color(0xFF2F6FDE);
  static const inactive = Color(0xFF8A8F98);
}

class AppTheme {
  static const _seed = Color(0xFF0B5FA5);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
