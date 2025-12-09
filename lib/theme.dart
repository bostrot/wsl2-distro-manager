import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:system_theme/system_theme.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:wsl2distromanager/components/helpers.dart';

enum NavigationIndicators { sticky, end }

class ThemeModeManager {}

class AppTheme extends ChangeNotifier {
  static var themeMode = ThemeMode.system;

  AppTheme() {
    _loadTheme();
  }

  void _loadTheme() {
    String? theme = prefs.getString('themeMode');
    if (theme == 'dark') {
      _mode = ThemeMode.dark;
    } else if (theme == 'light') {
      _mode = ThemeMode.light;
    } else {
      _mode = ThemeMode.system;
    }
    themeMode = _mode;
  }

  AccentColor _color = systemAccentColor;
  AccentColor get color => _color;
  set color(AccentColor color) {
    _color = color;
    notifyListeners();
  }

  AccentColor _backgroundColor = systemBackgroundColor;
  AccentColor get backgroundColor => _backgroundColor;
  set backgroundColor(AccentColor color) {
    _backgroundColor = color;
    notifyListeners();
  }

  Color _textColor = systemTextColor;
  Color get textColor => _textColor;
  set textColor(Color color) {
    _textColor = textColor;
    notifyListeners();
  }

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  set mode(ThemeMode mode) {
    _mode = mode;
    themeMode = mode;
    if (mode == ThemeMode.dark) {
      prefs.setString('themeMode', 'dark');
    } else if (mode == ThemeMode.light) {
      prefs.setString('themeMode', 'light');
    } else {
      prefs.setString('themeMode', 'system');
    }
    notifyListeners();
  }

  PaneDisplayMode _displayMode = PaneDisplayMode.auto;
  PaneDisplayMode get displayMode => _displayMode;
  set displayMode(PaneDisplayMode displayMode) {
    _displayMode = displayMode;
    notifyListeners();
  }

  NavigationIndicators _indicator = NavigationIndicators.sticky;
  NavigationIndicators get indicator => _indicator;
  set indicator(NavigationIndicators indicator) {
    _indicator = indicator;
    notifyListeners();
  }

  WindowEffect _windowEffect = WindowEffect.disabled;
  WindowEffect get windowEffect => _windowEffect;
  set windowEffect(WindowEffect windowEffect) {
    _windowEffect = windowEffect;
    notifyListeners();
  }

  void setEffect(WindowEffect effect, BuildContext context) {
    Window.setEffect(
      effect: effect,
      color: [
        WindowEffect.solid,
        WindowEffect.acrylic,
      ].contains(effect)
          ? FluentTheme.of(context).micaBackgroundColor.withOpacity(0.05)
          : Colors.transparent,
      dark: FluentTheme.of(context).brightness.isDark,
    );
  }

  TextDirection _textDirection = TextDirection.ltr;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection direction) {
    _textDirection = direction;
    notifyListeners();
  }

  Locale? _locale;
  Locale? get locale => _locale;
  set locale(Locale? locale) {
    _locale = locale;
    notifyListeners();
  }
}

AccentColor get systemAccentColor {
  if ((defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android) &&
      !kIsWeb) {
    return AccentColor('normal', {
      'darkest': SystemTheme.accentColor.darkest,
      'darker': SystemTheme.accentColor.darker,
      'dark': SystemTheme.accentColor.dark,
      'normal': SystemTheme.accentColor.accent,
      'light': SystemTheme.accentColor.light,
      'lighter': SystemTheme.accentColor.lighter,
      'lightest': SystemTheme.accentColor.lightest,
    });
  }
  return Colors.blue;
}

AccentColor get systemBackgroundColor {
  if ((defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.android)) {
    // Fluent UI background colors (grey)
    if (AppTheme.themeMode == ThemeMode.dark) {
      return AccentColor('normal', {
        'darkest': Colors.grey[200],
        'darker': Colors.grey[190],
        'dark': Colors.grey[180],
        'normal': Colors.grey[170],
        'light': Colors.grey[160],
        'lighter': Colors.grey[150],
        'lightest': Colors.grey[140],
      });
    } else {
      return AccentColor('normal', {
        'darkest': Colors.grey[40],
        'darker': Colors.grey[30],
        'dark': Colors.grey[20],
        'normal': Colors.grey[10],
        'light': Colors.grey[10],
        'lighter': Colors.grey[10],
        'lightest': Colors.grey[10],
      });
    }
  }
  return Colors.grey.toAccentColor();
}

Color get systemTextColor {
  return AppTheme.themeMode == ThemeMode.dark ? Colors.white : Colors.black;
}
