import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF4F46E5),
    brightness: Brightness.light,
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF4F46E5),
    brightness: Brightness.dark,
  );
}
