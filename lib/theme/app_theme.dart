import 'package:flutter/material.dart';

class AppTheme {
  // Zone palette — used across app and ring
  static const zoneColors = [
    Color(0xFF9E9E9E), // Zone 1: Fed State       (gray)
    Color(0xFFFFC107), // Zone 2: Early Fast       (amber)
    Color(0xFFFF7043), // Zone 3: Glycogen Burn    (deep orange)
    Color(0xFF29B6F6), // Zone 4: Metabolic Switch (light blue)
    Color(0xFF26A69A), // Zone 5: Fat Burning      (teal)
    Color(0xFF9C27B0), // Zone 6: Autophagy        (purple)
    Color(0xFF3F51B5), // Zone 7: Deep Renewal     (indigo)
  ];

  static const _seed = Color(0xFF26A69A);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F9F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F9F8),
          elevation: 0,
          centerTitle: true,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C1C1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C1C1A),
          elevation: 0,
          centerTitle: true,
        ),
      );
}
