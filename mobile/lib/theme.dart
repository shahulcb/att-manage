import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens (neutral base + blue accent: charcoal text, light-grey canvas, white cards; navy #10367D for primary buttons, sky #74B4DA for highlights).
class C {
  static const ink = Color(0xFF14181F);       // neutral charcoal: text, dark cards, nav
  static const brand = Color(0xFF10367D);     // palette navy: primary buttons only
  static const accent = Color(0xFF74B4DA);     // sky blue (palette 3): buttons, highlights, charts
  static const accentDeep = Color(0xFF3F8FBF);
  static const accentSoft = Color(0xFFE4EDF4);
  static const bg = Color(0xFFF4F5F7);       // neutral light grey canvas (white cards sit on it)
  static const card = Colors.white;
  static const grey = Color(0xFFE5E7EB);     // neutral chips / tracks
  static const lavender = Color(0xFFB7B9F0); // late
  static const lavenderSoft = Color(0xFFECE9FA);
  static const sky = Color(0xFFFFE08A);      // leave (warm amber, distinct from the blue accent)
  static const danger = Color(0xFFD9534F);
  static const ok = Color(0xFF2E9E5B);
  static const muted = Color(0xFF6B7280);
}

/// Colour per attendance status, used everywhere so the meaning is always the same.
Color statusColor(String? s) => switch (s) {
      'PRESENT' => C.accent,
      'LATE' => C.lavender,
      'ABSENT' => C.ink,
      'LEAVE' => C.sky,
      _ => C.grey,
    };

const kRadius = 28.0;
const kMaxWidth = 560.0; // content never gets wider than this (tablets / landscape)

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, primary: C.ink, secondary: C.accent, surface: C.card),
    textTheme: text,
    primaryTextTheme: text,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, foregroundColor: C.ink, titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      labelStyle: const TextStyle(color: C.muted), hintStyle: const TextStyle(color: C.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFDDE0E6), width: 1.2)), // visible on both white sheets and the grey canvas
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: C.brand, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: C.danger, width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.brand, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink, minimumSize: const Size.fromHeight(52), side: const BorderSide(color: C.ink, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: C.ink, textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32)))),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.ink : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.grey),
    ),
    dividerTheme: const DividerThemeData(color: C.grey, thickness: 1),
  );
}
