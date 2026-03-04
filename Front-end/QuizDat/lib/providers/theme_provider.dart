import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // In a real app, you might want to check platform brightness here,
      // but for simplicity, we'll let Flutter handle system mode or default to light.
      // This getter is mainly for UI toggles if needed.
      return false; // Or check WidgetsBinding.instance.window.platformBrightness
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeProvider() {
    _loadTheme();
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _saveTheme();
    notifyListeners();
  }
  
  void setThemeMode(ThemeMode mode) {
      _themeMode = mode;
      _saveTheme();
      notifyListeners();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('themeMode');
    if (themeString == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (themeString == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.dark) {
      await prefs.setString('themeMode', 'dark');
    } else if (_themeMode == ThemeMode.light) {
      await prefs.setString('themeMode', 'light');
    } else {
      await prefs.remove('themeMode');
    }
  }
}
