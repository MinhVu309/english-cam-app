import 'package:flutter/material.dart';

import 'palette.dart';

/// Tên font tròn (Nunito, giấy phép OFL) đóng gói trong assets/fonts.
const String kFontFamily = 'Nunito';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.orange,
    surface: Palette.cream,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kFontFamily,
  );
  const shapeRadius = 28.0;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(shapeRadius),
  );
  const buttonText = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );
  return base.copyWith(
    scaffoldBackgroundColor: Palette.cream,
    textTheme: base.textTheme
        .copyWith(
          // Mọi chữ thân bài >= 18sp cho bé dễ đọc.
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 18),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 18),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 20),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 20),
        )
        .apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Palette.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: buttonText,
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      titleTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Palette.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 20,
        color: Palette.ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 18,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
