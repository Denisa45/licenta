import 'package:flutter/material.dart';

/// Colors from the web app spec (Mână în mână).
const kBlue = Color(0xFF2F80C9);
const kCoral = Color(0xFFFF8A65);
const kInk = Color(0xFF12304D);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kBlue, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFF8CC2F0) : kBlue,
        secondary: kCoral,
        onSurface: dark ? const Color(0xFFE8F1FA) : kInk,
      );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0B1A2B)
        : const Color(0xFFEAF4FB),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
    ),
  );
}
