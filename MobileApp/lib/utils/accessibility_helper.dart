import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AccessibilityHelper extends ChangeNotifier {
  static final AccessibilityHelper _instance = AccessibilityHelper._internal();
  factory AccessibilityHelper() => _instance;
  AccessibilityHelper._internal();

  static const String _boxName = 'accessibility_prefs';
  bool _enabled = false;
  bool _initialized = false;

  bool get enabled => _enabled;

  // Accessibility theme values
  static const double minFontSize = 20.0;
  static const double minTapTarget = 64.0;

  Future<void> init() async {
    if (_initialized) return;
    final box = await Hive.openBox(_boxName);
    _enabled = box.get('enabled', defaultValue: false);
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final box = await Hive.openBox(_boxName);
    await box.put('enabled', value);
    notifyListeners();
  }

  ThemeData get accessibleTheme => ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black),
          displayMedium: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
          headlineLarge: TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black),
          headlineMedium: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
          titleLarge: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
          titleMedium: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black),
          bodyLarge: TextStyle(fontSize: 20, color: Colors.black),
          bodyMedium: TextStyle(fontSize: 20, color: Colors.black),
          labelLarge: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        colorScheme: const ColorScheme.highContrastLight(
          primary: Color(0xFFB71C1C),
          secondary: Color(0xFF0D47A1),
          surface: Colors.white,
          error: Color(0xFFD50000),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(minTapTarget, minTapTarget),
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              minimumSize: const Size(minTapTarget, minTapTarget)),
        ),
        appBarTheme: const AppBarTheme(
          titleTextStyle: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );

  ThemeData get normalTheme => ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      );
}
