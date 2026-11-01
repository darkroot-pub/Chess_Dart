import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class C {
  static const primary = Color(0xFF2563EB);
  static const secondary = Color(0xFF60A5FA);
  static const bg = Color(0xFFF5F8FF);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF10264A);
  static const text2 = Color(0xFF64748B);
  static const border = Color(0xFFE2EAF5);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const softBlue = Color(0xFFE8F0FF);
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: C.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: C.primary, brightness: Brightness.light)
            .copyWith(primary: C.primary, secondary: C.secondary, surface: C.surface, error: C.error),
        appBarTheme: const AppBarTheme(
          backgroundColor: C.bg,
          foregroundColor: C.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(color: C.text, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: C.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
        textTheme: const TextTheme().apply(bodyColor: C.text, displayColor: C.text),
      );
}

BoxDecoration cardDeco({double radius = 16, Color color = C.surface}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: C.border),
      boxShadow: const [BoxShadow(color: Color(0x0F2563EB), blurRadius: 14, offset: Offset(0, 4))],
    );
