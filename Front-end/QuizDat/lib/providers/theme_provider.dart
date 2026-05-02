import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // Theme style: 'light', 'dark', 'custom'
  String _themeStyle = 'light';
  double _textScaleFactor = 1.0;

  // Custom colors with defaults
  Color _customPrimary = const Color(0xFF1976D2);     // Blue
  Color _customBackground = const Color(0xFFF5F5F5);  // Light grey
  Color _customText = const Color(0xFF212121);         // Near black
  Color _customCard = const Color(0xFFFFFFFF);         // White
  Color _customAccent = const Color(0xFFFF9800);       // Orange

  // Getters
  String get themeStyle => _themeStyle;
  double get textScaleFactor => _textScaleFactor;
  Color get customPrimary => _customPrimary;
  Color get customBackground => _customBackground;
  Color get customText => _customText;
  Color get customCard => _customCard;
  Color get customAccent => _customAccent;

  bool get isCustomMode => _themeStyle == 'custom';

  ThemeMode get themeMode {
    switch (_themeStyle) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
      case 'custom':
      default:
        return ThemeMode.light;
    }
  }

  bool get isDarkMode => _themeStyle == 'dark';

  ThemeProvider() {
    _loadSettings();
  }

  // --- Setters ---

  void setThemeStyle(String style) {
    _themeStyle = style;
    _saveSettings();
    notifyListeners();
  }

  void toggleTheme(bool isDark) {
    _themeStyle = isDark ? 'dark' : 'light';
    _saveSettings();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == ThemeMode.dark) {
      _themeStyle = 'dark';
    } else {
      _themeStyle = 'light';
    }
    _saveSettings();
    notifyListeners();
  }

  void setTextScaleFactor(double factor) {
    _textScaleFactor = factor;
    _saveSettings();
    notifyListeners();
  }

  void setCustomColor(String key, Color color) {
    switch (key) {
      case 'primary':
        _customPrimary = color;
        break;
      case 'background':
        _customBackground = color;
        break;
      case 'text':
        _customText = color;
        break;
      case 'card':
        _customCard = color;
        break;
      case 'accent':
        _customAccent = color;
        break;
    }
    _saveSettings();
    notifyListeners();
  }

  // --- Custom ThemeData builder ---

  ThemeData get customTheme {
    final brightness = ThemeData.estimateBrightnessForColor(_customBackground);
    final bool isDarkBg = brightness == Brightness.dark;

    return ThemeData(
      fontFamilyFallback: const ['Malgun Gothic', 'Roboto', 'Gulim'],
      brightness: brightness,
      primaryColor: _customPrimary,
      scaffoldBackgroundColor: _customBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: _customBackground,
        foregroundColor: _customText,
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: _customCard,
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: _customPrimary,
        onPrimary: ThemeData.estimateBrightnessForColor(_customPrimary) == Brightness.dark
            ? Colors.white
            : Colors.black,
        secondary: _customAccent,
        onSecondary: ThemeData.estimateBrightnessForColor(_customAccent) == Brightness.dark
            ? Colors.white
            : Colors.black,
        surface: _customCard,
        onSurface: _customText,
        error: Colors.red,
        onError: Colors.white,
      ),
      dividerColor: _customText.withOpacity(0.12),
      iconTheme: IconThemeData(color: _customText),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: _customText),
        bodyMedium: TextStyle(color: _customText.withOpacity(isDarkBg ? 0.87 : 1.0)),
        titleLarge: TextStyle(color: _customText, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _customPrimary,
          foregroundColor: ThemeData.estimateBrightnessForColor(_customPrimary) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
      cardColor: _customCard,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _customCard,
        selectedItemColor: _customPrimary,
        unselectedItemColor: _customText.withOpacity(0.54),
      ),
    );
  }

  // --- Persistence ---

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load theme style
    _themeStyle = prefs.getString('themeStyle') ?? 'light';

    // Load text scale
    _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;

    // Load custom colors
    _customPrimary = Color(prefs.getInt('customPrimary') ?? 0xFF1976D2);
    _customBackground = Color(prefs.getInt('customBackground') ?? 0xFFF5F5F5);
    _customText = Color(prefs.getInt('customText') ?? 0xFF212121);
    _customCard = Color(prefs.getInt('customCard') ?? 0xFFFFFFFF);
    _customAccent = Color(prefs.getInt('customAccent') ?? 0xFFFF9800);

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Save theme style
    await prefs.setString('themeStyle', _themeStyle);

    // Save text scale
    await prefs.setDouble('textScaleFactor', _textScaleFactor);

    // Save custom colors
    await prefs.setInt('customPrimary', _customPrimary.value);
    await prefs.setInt('customBackground', _customBackground.value);
    await prefs.setInt('customText', _customText.value);
    await prefs.setInt('customCard', _customCard.value);
    await prefs.setInt('customAccent', _customAccent.value);
  }
}
