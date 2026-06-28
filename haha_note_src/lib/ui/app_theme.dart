import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const defaultThemeMode = ThemeMode.light;
  static const defaultColorScheme = FlexScheme.amber;
  static const defaultValue = AppTheme(themeMode: defaultThemeMode, colorScheme: defaultColorScheme);

  final ThemeMode themeMode;
  final FlexScheme colorScheme;

  const AppTheme({required this.themeMode, required this.colorScheme});

  AppTheme copyWith({
    ThemeMode? themeMode,
    FlexScheme? colorScheme,
  }) {
    return AppTheme(themeMode: themeMode ?? this.themeMode, colorScheme: colorScheme ?? this.colorScheme);
  }

  @override
  String toString() {
    return 'themeMode: $themeMode, colorScheme: $colorScheme';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AppTheme && runtimeType == other.runtimeType &&
              themeMode == other.themeMode && colorScheme == other.colorScheme;

  @override
  int get hashCode => Object.hash(themeMode, colorScheme);

}
